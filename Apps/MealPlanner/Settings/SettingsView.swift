import AppKit
import MealCore
import SwiftUI

/// Settings (⌘,): where the data lives and which version runs, and Claude. Reminders and the default servings
/// arrive with their stages.
struct SettingsView: View {
    enum Page: String {
        case general, claude
    }

    @AppStorage("settings.page") private var page = Page.general

    var body: some View {
        TabView(selection: $page) {
            Tab("Основные", systemImage: "gearshape", value: Page.general) {
                GeneralSettings()
            }
            Tab("Claude", systemImage: "sparkles", value: Page.claude) {
                ClaudeSettings()
            }
        }
        .frame(width: 600)
    }
}

private struct GeneralSettings: View {
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
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return AppModel.isDebugBuild ? "\(short) (\(build), Debug)" : "\(short) (\(build))"
    }
}

/// Claude Desktop: the MCP server in its config, where the «… с Claude» buttons open Claude, and the move from
/// Notion.
private struct ClaudeSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(ClaudeHandoff.targetKey) private var target = ClaudeHandoff.Target.code
    @State private var state = ClaudeConnection.State.missing
    @State private var confirming = false
    @State private var message: String?
    private let connection = ClaudeConnection.current

    var body: some View {
        Form {
            Section {
                LabeledContent("Claude Desktop") {
                    Text(status).multilineTextAlignment(.trailing)
                }
                switch state {
                case .connected:
                    Button("Убрать из Claude Desktop") {
                        change("Сервер убран из конфига Claude Desktop.") { try connection.remove() }
                    }
                case .otherCopy:
                    Button("Подключить эту копию приложения…") { confirming = true }
                case .missing:
                    Button("Добавить в Claude Desktop…") { confirming = true }
                case .unreadable:
                    Button("Показать конфиг в Finder") { reveal() }
                }
                if let message {
                    Text(message).foregroundStyle(.secondary)
                }
            } header: {
                Text("Инструменты для Claude")
            } footer: {
                Text(
                    "Claude сможет искать, заводить и править рецепты, категории и продукты Meal Planner — в той же базе, что у приложения, и открытое окно сразу покажет изменения. Claude Desktop спрашивает разрешение на каждое действие. В меню «+» поля ввода появятся готовые сценарии: импорт рецепта по ссылке, КБЖУ продуктов, перенос из Notion."
                )
                .foregroundStyle(.secondary)
            }
            Section("Вручную") {
                Text("Или добавьте фрагмент в claude_desktop_config.json сами:")
                Text(connection.snippet)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                HStack {
                    Button("Скопировать фрагмент") { copy(connection.snippet) }
                    Button("Показать конфиг в Finder") { reveal() }
                }
                Text("Для Claude Code в терминале:")
                Text(connection.cliCommand)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                Button("Скопировать команду") { copy(connection.cliCommand) }
            }
            Section {
                Picker("Где открывать", selection: $target) {
                    Text("В Claude Code, в папке Meal Planner").tag(ClaudeHandoff.Target.code)
                    Text("В новом чате").tag(ClaudeHandoff.Target.chat)
                }
                if target == .code, let workspace = model.claudeWorkspace {
                    Button("Показать папку в Finder") {
                        try? workspace.prepare()
                        NSWorkspace.shared.activateFileViewerSelecting([workspace.instructionsFile])
                    }
                }
            } header: {
                Text("Кнопки «… с Claude»")
            } footer: {
                Group {
                    if target == .code {
                        Text(
                            "Откроется новая сессия Claude Code в папке Meal Planner с запросом. В папке — указания, как заполнять рецепты и КБЖУ (CLAUDE.md); их можно править."
                        )
                    } else {
                        Text(
                            "Claude откроется в новом чате, запрос — в буфере обмена: вставьте его через ⌘V и нажмите Return."
                        )
                    }
                }
                .foregroundStyle(.secondary)
            }
            Section {
                Button("Перенести рецепты из Notion…") {
                    model.askClaude(ClaudeRequest.migrateFromNotion("Recipes"))
                }
                .disabled(state != .connected)
            } header: {
                Text("Перенос из Notion")
            } footer: {
                Text(
                    state == .connected
                        ? "Claude прочитает базу Recipes в Notion — нужен подключённый Notion в Claude — и заведёт рецепты здесь: фото, ингредиенты, шаги, категории и ссылки, а потом заполнит КБЖУ новых продуктов. Рецепты, которые уже есть, он пропустит."
                        : "Сначала подключите Meal Planner к Claude Desktop."
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { state = connection.state() }
        .confirmationDialog("Добавить Meal Planner в Claude Desktop?", isPresented: $confirming) {
            Button("Добавить") {
                change("Готово. Перезапустите Claude Desktop, чтобы он увидел инструменты Meal Planner.") {
                    try connection.install()
                }
            }
        } message: {
            Text(
                "В конфиг Claude Desktop добавится сервер «\(connection.serverName)». Прежний конфиг сохранится рядом, с датой в названии."
            )
        }
    }

    private var status: String {
        let installed = ClaudeHandoff.isDesktopInstalled
        switch state {
        case .connected: return installed ? "подключён" : "подключён, но Claude Desktop не установлен"
        case .otherCopy: return "подключён к другой копии Meal Planner"
        case .missing: return installed ? "не подключён" : "не установлен"
        case .unreadable(let problem): return "конфиг не читается: \(problem)"
        }
    }

    private func change(_ done: String, _ action: () throws -> URL?) {
        do {
            let backup = try action()
            message = [done, backup.map { "Прежний конфиг сохранён: \($0.lastPathComponent)." }].compactMap { $0 }
                .joined(separator: " ")
        } catch {
            message = "Конфиг не изменился: \(error)."
        }
        state = connection.state()
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func reveal() {
        let config = connection.config
        if FileManager.default.fileExists(atPath: config.path(percentEncoded: false)) {
            NSWorkspace.shared.activateFileViewerSelecting([config])
        } else {
            NSWorkspace.shared.open(config.deletingLastPathComponent())
        }
    }
}
