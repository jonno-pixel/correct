import Foundation
import llama

actor LocalInferenceEngine {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocabulary: OpaquePointer?
    private var batch: llama_batch?
    private var loadedSignature = ""
    private let processingBatchSize: Int32 = 256

    init() {
        llama_backend_init()
    }

    deinit {
        if let batch { llama_batch_free(batch) }
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        llama_backend_free()
    }

    func unload() {
        if let batch { llama_batch_free(batch) }
        batch = nil
        if let context { llama_free(context) }
        context = nil
        if let model { llama_model_free(model) }
        model = nil
        vocabulary = nil
        loadedSignature = ""
    }

    private func load(modelURL: URL, options: GenerationOptions) throws {
        let signature = "\(modelURL.path)|\(options.contextSize)|\(options.useMetal)"
        if signature == loadedSignature, context != nil { return }
        unload()

        var modelParameters = llama_model_default_params()
        modelParameters.load_mode = LLAMA_LOAD_MODE_MMAP
        modelParameters.n_gpu_layers = options.useMetal ? -1 : 0

        guard let loadedModel = modelURL.path.withCString({
            llama_model_load_from_file($0, modelParameters)
        }) else {
            throw JJSFailure(message: "Het GGUF-model kon niet worden geladen. Controleer het bestand en het beschikbare geheugen.")
        }
        model = loadedModel

        guard llama_model_has_decoder(loadedModel),
              let loadedVocabulary = llama_model_get_vocab(loadedModel) else {
            unload()
            throw JJSFailure(message: "Dit GGUF-bestand bevat geen ondersteund tekstgeneratiemodel.")
        }
        vocabulary = loadedVocabulary

        var contextParameters = llama_context_default_params()
        contextParameters.n_ctx = options.contextSize
        contextParameters.n_batch = UInt32(processingBatchSize)
        contextParameters.n_ubatch = UInt32(processingBatchSize)
        contextParameters.n_seq_max = 1
        contextParameters.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount))
        contextParameters.n_threads_batch = contextParameters.n_threads

        guard let loadedContext = llama_init_from_model(loadedModel, contextParameters) else {
            unload()
            throw JJSFailure(message: "De modelcontext kon niet worden aangemaakt. Kies een context die binnen het model en het beschikbare geheugen past.")
        }
        context = loadedContext

        guard llama_n_ctx(loadedContext) >= 8 else {
            unload()
            throw JJSFailure(message: "De modelcontext is te klein om te genereren.")
        }

        batch = llama_batch_init(processingBatchSize, 0, 1)
        loadedSignature = signature
    }

    private func format(_ turns: [EngineTurn], template: String) throws -> String {
        guard let model else { throw JJSFailure(message: "Er is geen model geladen.") }
        guard !turns.contains(where: {
            $0.role.utf8.contains(0) || $0.content.utf8.contains(0)
        }) else {
            throw JJSFailure(message: "Berichten met NUL-tekens kunnen niet naar de C-chattemplate worden gestuurd.")
        }

        let strings = turns.flatMap { [$0.role, $0.content] }
        let pointers: [UnsafeMutablePointer<CChar>?] = strings.map {
            $0.withCString { strdup($0) }
        }
        defer { pointers.forEach { free($0) } }
        guard pointers.allSatisfy({ $0 != nil }) else {
            throw JJSFailure(message: "Onvoldoende geheugen om de modelinvoer op te bouwen.")
        }

        let messages = turns.indices.map { index in
            llama_chat_message(
                role: UnsafePointer(pointers[index * 2]!),
                content: UnsafePointer(pointers[index * 2 + 1]!)
            )
        }

        func apply(_ templatePointer: UnsafePointer<CChar>?) throws -> String {
            guard let templatePointer else {
                throw JJSFailure(message: "Dit model heeft geen chattemplate. Kies een passende templatenaam in Instellingen.")
            }
            let required = messages.withUnsafeBufferPointer {
                llama_chat_apply_template(templatePointer, $0.baseAddress, $0.count, true, nil, 0)
            }
            guard required > 0 else {
                throw JJSFailure(message: "De chattemplate is niet compatibel met deze engine.")
            }

            var output = [CChar](repeating: 0, count: Int(required) + 1)
            let written = messages.withUnsafeBufferPointer { input in
                output.withUnsafeMutableBufferPointer {
                    llama_chat_apply_template(
                        templatePointer,
                        input.baseAddress,
                        input.count,
                        true,
                        $0.baseAddress,
                        required
                    )
                }
            }
            guard written >= 0, written <= required else {
                throw JJSFailure(message: "De modelchattemplate kon niet worden toegepast.")
            }
            return String(decoding: output.prefix(Int(written)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }

        if !template.isEmpty, let named = template.withCString({ llama_model_chat_template(model, $0) }), let res = try? apply(named) { return res }
        if !template.isEmpty, let res = try? template.withCString({ try apply($0) }) { return res }
        if let res = try? apply(llama_model_chat_template(model, nil)) { return res }
        let raw = llama_model_chat_template(model, nil).map { String(cString: $0) } ?? ""
        if raw.contains("<start_of_turn>") { return turns.map { "<start_of_turn>\($0.role == "assistant" ? "model" : "user")\n\($0.content)<end_of_turn>\n" }.joined() + "<start_of_turn>model\n" }
        if raw.contains("<|start_header_id|>") { return turns.map { "<|start_header_id|>\($0.role)<|end_header_id|>\n\n\($0.content)<|eot_id|>" }.joined() + "<|start_header_id|>assistant<|end_header_id|>\n\n" }
        return turns.map { "<|im_start|>\($0.role)\n\($0.content)<|im_end|>\n" }.joined() + "<|im_start|>assistant\n"
    }

    private func tokenize(_ text: String) throws -> [llama_token] {
        guard let vocabulary, let length = Int32(exactly: text.utf8.count) else {
            throw JJSFailure(message: "De tokenizer kan deze prompt niet als één C-aanroep verwerken.")
        }
        let required = text.withCString {
            llama_tokenize(vocabulary, $0, length, nil, 0, true, true)
        }
        guard required != Int32.min else {
            throw JJSFailure(message: "De tokenizer heeft een ongeldige invoergrootte teruggegeven.")
        }
        let capacity = abs(required)
        guard capacity > 0 else { throw JJSFailure(message: "De modelinvoer bevat geen tokens.") }

        var tokens = [llama_token](repeating: 0, count: Int(capacity))
        let count = text.withCString { input in
            tokens.withUnsafeMutableBufferPointer {
                llama_tokenize(vocabulary, input, length, $0.baseAddress, capacity, true, true)
            }
        }
        guard count > 0, count <= capacity else {
            throw JJSFailure(message: "De modelinvoer kon niet worden getokeniseerd.")
        }
        return Array(tokens.prefix(Int(count)))
    }

    private func tokenBytes(_ token: llama_token) throws -> [UInt8] {
        guard let vocabulary else { throw JJSFailure(message: "De modelvocabulary ontbreekt.") }
        var output = [CChar](repeating: 0, count: 32)
        var count = output.withUnsafeMutableBufferPointer {
            llama_token_to_piece(vocabulary, token, $0.baseAddress, Int32($0.count), 0, false)
        }
        if count < 0 {
            guard count != Int32.min else { throw JJSFailure(message: "De tokentekst is te groot.") }
            output = [CChar](repeating: 0, count: Int(-count))
            count = output.withUnsafeMutableBufferPointer {
                llama_token_to_piece(vocabulary, token, $0.baseAddress, Int32($0.count), 0, false)
            }
        }
        guard count >= 0, count <= output.count else {
            throw JJSFailure(message: "De tokentekst kon niet worden gelezen.")
        }
        return output.prefix(Int(count)).map { UInt8(bitPattern: $0) }
    }

    private func decode(_ tokens: ArraySlice<llama_token>, at position: Int, logits: Bool) throws {
        guard let context, var batch else { throw JJSFailure(message: "De modelcontext ontbreekt.") }
        guard tokens.count <= Int(processingBatchSize),
              tokens.count <= Int(llama_n_batch(context)) else {
            throw JJSFailure(message: "De engine kan deze verwerkingsbatch niet verwerken.")
        }

        batch.n_tokens = Int32(tokens.count)
        for (index, token) in tokens.enumerated() {
            batch.token[index] = token
            batch.pos[index] = Int32(position + index)
            batch.n_seq_id[index] = 1
            batch.seq_id[index]![0] = 0
            batch.logits[index] = logits && index == tokens.count - 1 ? 1 : 0
        }

        let result = llama_decode(context, batch)
        guard result == 0 else {
            throw JJSFailure(message: "De modelberekening stopte met enginecode \(result). Ontvangen tekst is opgeslagen.")
        }
    }

    private func waitForThermalSafety(
        emit: @Sendable (EngineUpdate) async throws -> Void
    ) async throws {
        while ProcessInfo.processInfo.thermalState == .serious
            || ProcessInfo.processInfo.thermalState == .critical {
            try Task.checkCancellation()
            try await emit(.status("Generatie wacht tot de iPhone voldoende is afgekoeld."))
            try await Task.sleep(for: .seconds(5))
        }
    }

    func generate(
        modelURL: URL,
        options: GenerationOptions,
        history: [EngineTurn],
        emit: @Sendable (EngineUpdate) async throws -> Void
    ) async throws -> GenerationResult {
        try await waitForThermalSafety(emit: emit)
        try await emit(.status("Model laden…"))
        try load(modelURL: modelURL, options: options)

        guard let context, let vocabulary else {
            throw JJSFailure(message: "Het model is niet volledig geladen.")
        }
        let prompt = try format(history, template: options.template)
        let promptTokens = try tokenize(prompt)
        let capacity = Int(llama_n_ctx(context))
        let memory = llama_get_memory(context)
        llama_memory_clear(memory, true)

        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
            throw JJSFailure(message: "De sampler kon niet worden aangemaakt.")
        }
        defer { llama_sampler_free(sampler) }
        if options.temperature == 0 {
            llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
        } else {
            llama_sampler_chain_add(sampler, llama_sampler_init_penalties(llama_vocab_n_tokens(vocabulary), 64, 1.1, 0.0, 0.0))
            llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
            llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.95, 1))
            llama_sampler_chain_add(sampler, llama_sampler_init_min_p(0.05, 1))
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(options.temperature))
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: .min ... .max)))
        }

        var window: [llama_token] = []
        var shifts = 0

        func makeRoom(for count: Int) throws {
            guard window.count + count > capacity else { return }
            let retained = Array(window.suffix(min(capacity / 2, capacity - count)))
            llama_memory_clear(memory, true)
            window.removeAll(keepingCapacity: true)
            var offset = 0
            while offset < retained.count {
                try Task.checkCancellation()
                let end = min(offset + Int(processingBatchSize), retained.count)
                try decode(retained[offset..<end], at: offset, logits: false)
                offset = end
            }
            window = retained
            shifts += 1
        }

        var offset = 0
        while offset < promptTokens.count {
            try Task.checkCancellation()
            try await waitForThermalSafety(emit: emit)
            let count = min(Int(processingBatchSize), max(1, capacity / 2), promptTokens.count - offset)
            try makeRoom(for: count)
            try decode(promptTokens[offset..<(offset + count)], at: window.count, logits: true)
            window.append(contentsOf: promptTokens[offset..<(offset + count)])
            offset += count
            try await emit(.status("Gesprek verwerken · \(offset.formatted()) / \(promptTokens.count.formatted()) tokens"))
        }

        try await emit(.status("Antwoord wordt lokaal gegenereerd…"))
        var utf8 = UTF8Stream()
        var pendingText = ""
        var generated = 0
        var lastFlush = Date()

        do {
            while true {
                try Task.checkCancellation()
                try await waitForThermalSafety(emit: emit)
                let token = llama_sampler_sample(sampler, context, -1)
                if llama_vocab_is_eog(vocabulary, token) { break }

                pendingText += utf8.append(try tokenBytes(token))
                try makeRoom(for: 1)
                try decode([token][...], at: window.count, logits: true)
                window.append(token)
                generated += 1

                if Date().timeIntervalSince(lastFlush) >= 0.1, !pendingText.isEmpty {
                    try await emit(.text(pendingText))
                    pendingText.removeAll(keepingCapacity: true)
                    lastFlush = Date()
                }
                if generated.isMultiple(of: 16) { await Task.yield() }
            }
        } catch {
            pendingText += utf8.finish()
            if !pendingText.isEmpty { try await emit(.text(pendingText)) }
            throw error
        }

        pendingText += utf8.finish()
        if !pendingText.isEmpty { try await emit(.text(pendingText)) }
        return GenerationResult(tokenCount: generated, contextShifts: shifts)
    }
}
