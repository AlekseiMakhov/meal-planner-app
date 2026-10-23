import AppKit
import MealCore
import MealReminders
import SwiftUI

/// Settings (⌘,): where the data lives and which version runs, the shopping list in «Напоминания», and Claude.
struct SettingsView: View {
    enum Page: String {
        case general, reminders, claude
    }

    @AppStorage("settings.page") private var page = Page.general

    var body: some View {
        TabView(selection: $page) {
            Tab("Основные", systemImage: "gearshape", value: Page.general) {
                GeneralSettings()
            }
            Tab("Напоминания", systemImage: "checklist", value: Page.reminders) {
                RemindersSettings()
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
    @AppStorage(ShoppingScreen.stocksWithoutAskingKey) private var stocksWithoutAsking = false
    @AppStorage(AppModel.backupsInICloudKey) private var backupsInICloud = false
    @State private var lastCopy: URL?
    @State private var backupMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("Пополнять запасы без вопросов", isOn: $stocksWithoutAsking)
            } header: {
                Text("Покупки")
            } footer: {
                Text(
                    stocksWithoutAsking
                        ? "Отмеченное купленным сразу попадает в запасы в том количестве, что было в списке."
                        : "Купленное попадает в запасы после «Убрать в запасы…»: там можно поправить количества."
                )
                .foregroundStyle(.secondary)
            }
            BackgroundSettings()
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
            Section {
                Toggle("Хранить копии в iCloud Drive", isOn: $backupsInICloud)
                    .disabled(!FileManager.default.fileExists(atPath: AppModel.iCloudDrive.path(percentEncoded: false)))
                LabeledContent(
                    "Последняя копия", value: lastCopy.map { $0.deletingPathExtension().lastPathComponent } ?? "ещё нет"
                )
                HStack {
                    Button("Сделать копию сейчас", action: backUpNow)
                    Button("Показать в Finder") {
                        guard let backups = model.backups else { return }
                        try? FileManager.default.createDirectory(at: backups.folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(backups.folder)
                    }
                }
                if let backupMessage {
                    Text(backupMessage).foregroundStyle(.secondary)
                }
            } header: {
                Text("Резервные копии")
            } footer: {
                Text(
                    "Копия базы делается раз в день — и тогда, когда приложение неделями работает в строке меню, — хранятся последние 14. Фото лежат отдельно, в папке Images рядом с базой. Чтобы вернуть копию, выйдите из приложения и положите её вместо meals.sqlite в папке с данными."
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { lastCopy = model.backups?.copies().first }
        .onChange(of: backupsInICloud) { lastCopy = model.backups?.copies().first }
    }

    private func backUpNow() {
        guard let backups = model.backups, let database = model.database else { return }
        do {
            lastCopy = try backups.backUp(database, force: true)
            backupMessage = "Копия сохранена."
        } catch {
            backupMessage = "Копия не сохранилась: \(error)"
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return AppModel.isDebugBuild ? "\(short) (\(build), Debug)" : "\(short) (\(build))"
    }
}

/// Meal Planner as a service: in the menu bar with its window closed, and opened at login.
private struct BackgroundSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            Toggle(
                "Открывать при входе в систему",
                isOn: Binding(get: { model.loginItem.state != .disabled }, set: { model.loginItem.set($0) }))
            if model.loginItem.state == .needsApproval {
                HStack {
                    Text("Разрешите Meal Planner в Системных настройках → Основные → Объекты входа.")
                        .foregroundStyle(.secondary)
                    Button("Открыть…") { model.loginItem.openSystemSettings() }
                }
            }
        } header: {
            Text("Работа в фоне")
        } footer: {
            Text(footer)
                .foregroundStyle(.secondary)
        }
        .onAppear { model.loginItem.refresh() }
    }

    private var footer: String {
        var text =
            "Когда окно закрыто, Meal Planner остаётся в строке меню: синхронизирует покупки с «Напоминаниями», подхватывает то, что записал Claude, и раз в день делает копию. При входе в систему он открывается без окна. Выйти совсем — ⌘Q или «Выйти» в меню значка."
        if !Bundle.main.bundleURL.path(percentEncoded: false).hasPrefix("/Applications/") {
            text +=
                " Эта копия лежит не в /Applications: после новой сборки её путь изменится, поэтому вход в систему включайте у установленной."
        }
        return text
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

/// The shopping list in «Напоминания»: the list, how items read there, and what comes back from the family.
private struct RemindersSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let reminders = model.reminders {
            RemindersForm(reminders: reminders)
        } else {
            Form {
                Text("База данных не открылась.")
            }
            .formStyle(.grouped)
        }
    }
}

private struct RemindersForm: View {
    @Bindable var reminders: RemindersModel
    @AppStorage(ShoppingScreen.stocksWithoutAskingKey) private var stocksWithoutAsking = false

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Синхронизировать список покупок",
                    isOn: Binding(
                        get: { reminders.settings.isEnabled },
                        set: { isOn in
                            if isOn {
                                Task { await reminders.enable() }
                            } else {
                                reminders.disable()
                            }
                        }))
                if reminders.settings.isEnabled {
                    Picker("Список", selection: $reminders.settings.listID) {
                        Text("Не выбран").tag(String?.none)
                        ForEach(reminders.lists) { list in
                            Text("\(list.title) — \(list.account)").tag(String?.some(list.id))
                        }
                    }
                    Button("Создать список «Покупки»") { reminders.createList() }
                    if reminders.settings.listID != nil {
                        HStack {
                            Button("Синхронизировать сейчас") { Task { await reminders.syncNow() } }
                                .disabled(reminders.isSyncing)
                            Spacer()
                            Text(status)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let problem = reminders.problem {
                    Text(problem)
                        .foregroundStyle(Color(.statusMissing))
                }
            } header: {
                Text("«Напоминания»")
            } footer: {
                Text(
                    "Список из iCloud виден на iPhone. Чтобы он был и у семьи, откройте его в «Напоминаниях» и выберите «Поделиться списком» — открыть доступ можно только там. Что отмечено в магазине, станет купленным здесь; что добавили родные — появится в покупках."
                )
                .foregroundStyle(.secondary)
            }
            if reminders.settings.isEnabled {
                Section("Как выглядят пункты") {
                    Picker("Заголовок", selection: $reminders.settings.titleStyle) {
                        Text("«Молоко — 1 л»").tag(ReminderSettings.TitleStyle.nameAndAmount)
                        Text("«Молоко», количество в заметке").tag(ReminderSettings.TitleStyle.nameOnly)
                    }
                    Toggle("Эмодзи отдела в начале — для сортировки по названию", isOn: $reminders.settings.aisleEmoji)
                    Toggle("В заметке — для каких блюд", isOn: $reminders.settings.notesDishes)
                    Toggle("…и на какие дни", isOn: $reminders.settings.notesDays)
                        .disabled(!reminders.settings.notesDishes)
                    Picker("Срок — день закупки", selection: $reminders.settings.shoppingWeekday) {
                        Text("Без срока").tag(Int?.none)
                        ForEach(1...7, id: \.self) { weekday in
                            Text(Self.weekdays[weekday - 1]).tag(Int?.some(weekday))
                        }
                    }
                }
                Section("Купленное и пункты родных") {
                    Picker("Убирать купленное", selection: $reminders.settings.clearBoughtAfterDays) {
                        Text("Только кнопкой «Очистить купленное»").tag(Int?.none)
                        Text("Через день").tag(Int?.some(1))
                        Text("Через 3 дня").tag(Int?.some(3))
                        Text("Через неделю").tag(Int?.some(7))
                    }
                    Toggle("Принимать пункты, которые добавили родные", isOn: $reminders.settings.acceptsFamilyItems)
                    Toggle("Пополнять запасы без вопросов", isOn: $stocksWithoutAsking)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { reminders.refreshLists() }
    }

    static let weekdays = ["Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"]

    private var status: String {
        if reminders.isSyncing { return "синхронизируется…" }
        guard let date = reminders.lastSync else { return "ещё не синхронизировался" }
        return "в \(date.formatted(.dateTime.hour().minute().locale(Formatting.locale)))"
    }
}
