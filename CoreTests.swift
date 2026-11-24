import Foundation

@main
enum CoreTests {
    static func main() async throws {
        testUTF8StreamingAtEveryBoundary()
        testGenerationOptionsRoundTrip()
        try await testConversationQueueAndJSONTransfer()
        print("JJS core tests passed.")
    }

    private static func testUTF8StreamingAtEveryBoundary() {
        let expected = "JJS — café 🙂"
        let bytes = Array(expected.utf8)

        for split in 0...bytes.count {
            var stream = UTF8Stream()
            let first = stream.append(Array(bytes[..<split]))
            let second = stream.append(Array(bytes[split...]))
            let result = first + second + stream.finish()
            precondition(result == expected, "UTF-8 failed at split \(split)")
        }
    }

    private static func testGenerationOptionsRoundTrip() {
        let options = GenerationOptions(
            modelPath: "models/example.gguf",
            contextSize: 0,
            temperature: 0.7,
            useMetal: true,
            template: ""
        )
        let decoded = try! JSONDecoder().decode(
            GenerationOptions.self,
            from: JSONEncoder().encode(options)
        )
        precondition(decoded.modelPath == options.modelPath)
        precondition(decoded.contextSize == 0)
        precondition(decoded.temperature == options.temperature)
        precondition(decoded.useMetal)
    }

    private static func testConversationQueueAndJSONTransfer() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JJS-CoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try ChatDatabase(file: directory.appendingPathComponent("chats.sqlite"))
        let chat = try await database.createChat()
        let options = GenerationOptions(
            modelPath: "model.gguf",
            contextSize: 0,
            temperature: 0.7,
            useMetal: false,
            template: ""
        )
        let response = try await database.enqueue(chat: chat, input: "Vraag", options: options)
        let pending = try await database.nextJob()
        precondition(pending?.id == response)
        let history = try await database.history(chat: chat, before: response)
        precondition(history.map(\.content) == ["Vraag"])

        try await database.setState(response, .running)
        try await database.append(response, text: "Antwoord ")
        try await database.append(response, text: "compleet")
        try await database.complete(response, note: "Klaar")

        let archive = try await database.exportArchive()
        let importedDatabase = try ChatDatabase(file: directory.appendingPathComponent("imported.sqlite"))
        try await importedDatabase.importArchive(archive)
        let importedChats = try await importedDatabase.chats()
        precondition(importedChats.count == 1)
        let importedMessages = try await importedDatabase.messages(chat: importedChats[0].id)
        precondition(importedMessages.map(\.content) == ["Vraag", "Antwoord compleet"])
        precondition(importedMessages[1].state == .complete)
    }
}
