import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: TranscriptionStore

    var body: some View {
        Form {
            Picker("Default model", selection: $store.selectedModel) {
                ForEach(ParakeetModel.allCases) { model in
                    VStack(alignment: .leading) {
                        Text(model.label)
                        Text(model.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(model)
                }
            }

            LabeledContent("Backend") {
                Text("Bundled Python sidecar")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460)
    }
}
