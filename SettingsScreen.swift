import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SettingsScreen: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Apple Metal gebruiken", isOn: $store.useMetal)
                    TextField("Contexttokens · 0 = modelstandaard", text: $store.contextText)
                        .keyboardType(.numberPad)
                    TextField("Temperatuur", text: $store.temperatureText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Model")
                } footer: {
                    Text("De actieve context wordt begrensd door het model en het beschikbare geheugen. Bij een volle context schuift de actieve geschiedenis door; de opgeslagen chat blijft volledig bewaard. Er is geen vaste uitvoertokenlimiet of timer.")
                }

                Section {
                    TextField("Leeg = template uit model", text: $store.template)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Chattemplate")
                } footer: {
                    Text("JJS voegt geen eigen systeemprompt, inhoudsfilter of verborgen vervolgopdracht toe.")
                }

                Section("Gesprekken") {
                    Button("Exporteer alle gesprekken", systemImage: "square.and.arrow.up") {
                        Task { await store.exportChats() }
                    }
                    if let exportURL = store.exportURL {
                        ShareLink("Deel JSON-export", item: exportURL)
                    }
                    Button("Importeer gesprekken", systemImage: "square.and.arrow.down") {
                        importing = true
                    }
                }

                Section("Verwerking") {
                    Label("Lokale verwerking op dit toestel", systemImage: "iphone")
                    Text("iOS beheert de warmte, het geheugen en de achtergrondlevenscyclus. Bij hoge thermische belasting pauzeert de inferentie automatisch en gaat verder zodra het toestel voldoende is afgekoeld.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Instellingen")
            .toolbar { Button("Gereed") { dismiss() } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    Task { await store.importChats(from: url) }
                case .failure(let error):
                    store.problem = error.localizedDescription
                }
            }
        }
    }
}
