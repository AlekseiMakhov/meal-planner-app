import AppKit
import MealCore
import SwiftUI

/// «Импорт по ссылке с Claude»: a link and, if wanted, a category; Claude reads the page and fills the recipe.
/// A link on the clipboard is offered right away.
struct ClaudeImportSheet: View {
    let categories: [RecipeCategory]
    let send: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var categoryID: RecipeCategory.ID?

    init(categories: [RecipeCategory], categoryID: RecipeCategory.ID?, send: @escaping (String) -> Void) {
        self.categories = categories
        self.send = send
        _categoryID = State(initialValue: categoryID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    TextField("Ссылка", text: $link, prompt: Text("https://…"))
                    Picker("Категория", selection: $categoryID) {
                        Text("Подберёт Claude").tag(RecipeCategory.ID?.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                } header: {
                    Text("Рецепт по ссылке")
                } footer: {
                    Text(
                        "Claude прочитает страницу или описание видео, заведёт рецепт с фото, ингредиентами и шагами и заполнит КБЖУ новых продуктов. Рецепт появится здесь, как только Claude его сохранит."
                    )
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Отмена", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Открыть в Claude") {
                    let category = categories.first { $0.id == categoryID }?.name
                    send(ClaudeRequest.importRecipe(url: url?.absoluteString ?? link, category: category))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(url == nil)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 480)
        .onAppear {
            if let copied = NSPasteboard.general.string(forType: .string), Self.webLink(copied) != nil {
                link = copied.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private var url: URL? {
        Self.webLink(link)
    }

    /// A web address, with or without its scheme: «povar.ru/recipes/…» is taken as https.
    nonisolated static func webLink(_ text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        let withScheme = text.contains("://") ? text : "https://" + text
        guard let url = URL(string: withScheme), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
            let host = url.host(), host.contains(".")
        else { return nil }
        return url
    }
}
