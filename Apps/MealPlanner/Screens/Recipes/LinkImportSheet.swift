import AppKit
import MealCore
import MealStore
import SwiftUI

/// «Импорт по ссылке» without Claude: the page's schema.org recipe, its lines matched with the product base —
/// found, one of several to choose, or a new product to name — saved as a recipe with its photo. A page without
/// such a recipe goes to Claude.
struct LinkImportSheet: View {
    let database: AppDatabase
    let categoryID: RecipeCategory.ID?
    let opened: (Recipe.ID) -> Void
    let withClaude: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var phase = Phase.idle
    @State private var imported: ImportedRecipe?
    @State private var title = ""
    @State private var servings = Recipe.defaultServings
    @State private var lines: [ImportLine] = []
    @State private var problem: String?

    enum Phase {
        case idle, loading, ready, notFound, saving
    }

    /// One ingredient line and the product it goes to.
    struct ImportLine: Identifiable {
        let id = UUID()
        let text: String
        let parsed: ParsedIngredient
        var candidates: [Product]
        /// The product chosen; nil — a new one named `newName`.
        var product: Product?
        var newName: String
        var include = true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Рецепт по ссылке")
                .font(.title2.bold())
            HStack {
                TextField("Ссылка", text: $link, prompt: Text("https://…"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await load() } }
                Button("Загрузить") { Task { await load() } }
                    .disabled(ClaudeImportSheet.webLink(link) == nil || phase == .loading)
            }
            content
            if let problem {
                Text(problem)
                    .foregroundStyle(Color(.statusMissing))
            }
            HStack {
                if phase == .ready || phase == .notFound {
                    Button("Открыть в Claude") {
                        withClaude(ClaudeImportSheet.webLink(link)?.absoluteString ?? link)
                        dismiss()
                    }
                }
                Spacer()
                Button("Отмена", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Сохранить рецепт") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(phase != .ready || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 680, height: 620)
        .animation(Motion.swap, value: phase)
        .onAppear {
            if let copied = NSPasteboard.general.string(forType: .string), ClaudeImportSheet.webLink(copied) != nil {
                link = copied.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    /// The phases cross-fade in one place.
    private var content: some View {
        ZStack(alignment: .topLeading) {
            switch phase {
            case .idle:
                Text(
                    "Большинство сайтов с рецептами описывают их разметкой schema.org: название, порции, ингредиенты, шаги и фото. Приложение прочитает её само; если разметки нет — поможет Claude."
                )
                .foregroundStyle(Color(.textSecondary))
            case .loading, .saving:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notFound:
                ContentUnavailableView(
                    "На странице нет разметки рецепта", systemImage: "doc.questionmark",
                    description: Text("Claude прочитает её как человек и заведёт рецепт сам."))
            case .ready:
                preview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Название", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
            HStack(spacing: 16) {
                Stepper("Порций: \(servings)", value: $servings, in: 1...50)
                    .fixedSize()
                if let imported {
                    Text(summary(imported))
                        .foregroundStyle(Color(.textSecondary))
                }
            }
            List($lines) { $line in
                ImportLineRow(line: $line)
            }
            .listStyle(.inset)
            Text(
                "Новые продукты появятся в базе без КБЖУ — потом их заполнит «Дозаполнить с Claude» на странице рецепта или вы сами в «Продуктах»."
            )
            .font(.caption)
            .foregroundStyle(Color(.textSecondary))
        }
    }

    private func summary(_ recipe: ImportedRecipe) -> String {
        var parts = [Formatting.count(recipe.steps.count, "шаг", "шага", "шагов")]
        if let minutes = recipe.totalMinutes ?? recipe.cookMinutes {
            parts.append(Formatting.minutes(minutes))
        }
        if recipe.imageURL != nil { parts.append("с фото") }
        if recipe.videoURL != nil { parts.append("с видео") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Loading and saving

    private func load() async {
        guard let url = ClaudeImportSheet.webLink(link) else { return }
        phase = .loading
        problem = nil
        do {
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw StoreError("Сайт ответил \(http.statusCode).")
            }
            let html = String(decoding: data, as: UTF8.self)
            guard let recipe = RecipeImport.recipe(inHTML: html, url: response.url ?? url) else {
                phase = .notFound
                return
            }
            imported = recipe
            title = recipe.title
            servings = recipe.servings ?? Recipe.defaultServings
            lines = try recipe.ingredients.flatMap { text in
                try IngredientParser.parse(text).map { part in try resolve(text, part) }
            }
            phase = .ready
        } catch {
            problem = "Страница не загрузилась: \(error.localizedDescription)"
            phase = .idle
        }
    }

    private func resolve(_ text: String, _ part: ParsedIngredient) throws -> ImportLine {
        let name = part.name.prefix(1).uppercased() + part.name.dropFirst()
        switch try database.matchProduct(named: part.name) {
        case .found(let product):
            return ImportLine(text: text, parsed: part, candidates: [product], product: product, newName: name)
        case .ambiguous(let candidates):
            return ImportLine(
                text: text, parsed: part, candidates: candidates, product: candidates.first, newName: name)
        case .none:
            return ImportLine(text: text, parsed: part, candidates: [], product: nil, newName: name)
        }
    }

    private func save() async {
        guard let imported else { return }
        phase = .saving
        do {
            var details = RecipeDetails(
                recipe: Recipe(
                    id: 0, title: title, videoURL: imported.videoURL, sourceURL: imported.sourceURL, servings: servings,
                    prepMinutes: imported.prepMinutes,
                    cookMinutes: imported.cookMinutes ?? (imported.prepMinutes == nil ? imported.totalMinutes : nil),
                    notes: imported.description ?? ""))
            for line in lines where line.include {
                let productID: Product.ID
                if let product = line.product {
                    productID = product.id
                } else {
                    let name = line.newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    productID = try database.product(named: name)?.id ?? database.newProduct(named: name).id
                }
                details.ingredients.append(
                    RecipeIngredient(
                        productID: productID, amount: line.parsed.amount, amountMax: line.parsed.amountMax,
                        unit: line.parsed.unit, note: line.parsed.note, isOptional: line.parsed.isOptional))
            }
            details.steps = imported.steps.map { RecipeStep(text: $0) }
            details.categoryIDs = categoryID.map { [$0] } ?? []
            var saved = try database.newRecipe(from: details)
            if let image = imported.imageURL, let photo = try? await database.images.download(image) {
                saved.recipe.photo = photo
                saved = try database.save(saved)
            }
            opened(saved.recipe.id)
            dismiss()
        } catch {
            problem = String(describing: error)
            phase = .ready
        }
    }
}

/// A line of the page and where it goes: the product found, one of several, or a new one.
private struct ImportLineRow: View {
    @Binding var line: LinkImportSheet.ImportLine

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $line.include) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
            Text(line.text)
                .foregroundStyle(line.include ? Color(.textPrimary) : Color(.textSecondary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
            Image(systemName: "arrow.right")
                .foregroundStyle(Color(.textSecondary))
            if line.product == nil {
                TextField("Новый продукт", text: $line.newName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
                    .help("Новый продукт: название в именительном падеже, как в магазине")
            }
            Picker("Продукт", selection: $line.product) {
                ForEach(line.candidates) { product in
                    Text(product.name).tag(Optional(product))
                }
                Text("Новый продукт").tag(Product?.none)
            }
            .labelsHidden()
            .frame(width: line.product == nil ? 120 : 220)
        }
    }
}
