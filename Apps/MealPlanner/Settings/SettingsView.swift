import AppKit
import SwiftUI

/// Settings (⌘,). For now where the data lives and which version runs; Claude, Reminders and the
/// default servings arrive with their stages.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            LabeledContent("Папка с данными") {
                if let directory = model.dataDirectory {
                    HStack {
                        Text(directory.path(percentEncoded: false))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Показать в Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([directory])
                        }
                    }
                } else {
                    Text("недоступна")
                }
            }
            LabeledContent("Версия", value: version)
        }
        .formStyle(.grouped)
        .frame(width: 560)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return AppModel.isDebugBuild ? "\(short) (\(build), Debug)" : "\(short) (\(build))"
    }
}
