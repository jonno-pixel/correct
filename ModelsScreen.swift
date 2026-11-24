import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ModelsScreen: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var deleting: ModelEntry?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("GGUF-model importeren", systemImage: "square.and.arrow.down") {
                        importing = true
                    }
                    Text("Kies één of meer GGUF-bestanden, of een map met modelbestanden. JJS controleert de GGUF-header en behoudt de bytes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Op dit toestel") {
                    if store.models.isEmpty {
                        ContentUnavailableView("Geen modellen", systemImage: "cpu")
                    }
                    ForEach(store.models) { model in
                        Button {
                            store.selectedModel = model.path
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(model.name).foregroundStyle(.primary)
                                    Text(ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.selectedModel == model.path {
                                    Image(systemName: "checkmark").accessibilityLabel("Geselecteerd")
                                }
                            }
                        }
                        .swipeActions {
                            Button("Verwijder", role: .destructive) { deleting = model }
                                .disabled(store.isGenerating)
                        }
                    }
                }

                Section("Model laden") {
                    Text(store.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("De engine laadt het gekozen model bij de eerste vraag. Het model bepaalt zijn eigen eindtoken; JJS legt geen antwoordlengte of generatie-time-out op.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Lokale modellen")
            .toolbar { Button("Gereed") { dismiss() } }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.item, .folder],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task { await store.loadModels(urls) }
                case .failure(let error):
                    store.problem = error.localizedDescription
                }
            }
            .confirmationDialog(
                "Model verwijderen?",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Verwijder model", role: .destructive) {
                    if let deleting { Task { await store.deleteModel(deleting) } }
                    deleting = nil
                }
                Button("Annuleer", role: .cancel) { deleting = nil }
            } message: {
                Text(deleting?.name ?? "")
            }
        }
    }
}
