import MealCore
import MealStore
import SwiftUI

/// What another part of the app asks a screen to show: a recipe's page, a product, or a list searched for a name.
struct NavigationRequest: Equatable {
    let id = UUID()
    var section: AppModel.Section
    var recipe: Recipe.ID?
    var product: Product.ID?
    var search: String?
}

/// ⌘K: recipes, products, the pantry, the shopping list and categories in one list as the name is typed; arrows
/// move, Return opens.
struct QuickSearch: View {
    let database: AppDatabase
    let open: (Hit) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var hits: [Hit] = []
    @State private var selected = 0
    @FocusState private var focused: Bool

    /// One thing found and where it opens.
    struct Hit: Identifiable, Hashable {
        enum Kind: String {
            case recipe = "Рецепты"
            case product = "Продукты"
            case pantry = "Запасы"
            case shopping = "Покупки"
            case category = "Категории"
        }

        let kind: Kind
        let id: Int64
        let title: String
        let detail: String

        var key: String {
            "\(kind.rawValue)-\(id)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color(.textSecondary))
                TextField("Рецепт, продукт, покупка…", text: $text)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { choose(selected) }
                    .onKeyPress(.downArrow) {
                        selected = min(selected + 1, max(hits.count - 1, 0))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        selected = max(selected - 1, 0)
                        return .handled
                    }
            }
            .padding(14)
            Divider()
            ScrollViewReader { scroller in
                List {
                    ForEach(Array(hits.enumerated()), id: \.element.key) { index, hit in
                        VStack(alignment: .leading, spacing: 0) {
                            if index == 0 || hits[index - 1].kind != hit.kind {
                                Text(hit.kind.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(.textSecondary))
                                    .padding(.top, index == 0 ? 0 : 8)
                                    .padding(.bottom, 4)
                            }
                            HStack {
                                Text(hit.title)
                                    .lineLimit(1)
                                Spacer()
                                Text(hit.detail)
                                    .foregroundStyle(Color(.textSecondary))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                index == selected ? Color.accentColor.opacity(0.25) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { choose(index) }
                        }
                        .id(hit.key)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onChange(of: selected) {
                    if hits.indices.contains(selected) { scroller.scrollTo(hits[selected].key) }
                }
            }
            if hits.isEmpty {
                Text(text.isEmpty ? "Начните вводить название" : "Ничего не нашлось")
                    .foregroundStyle(Color(.textSecondary))
                    .padding(.bottom, 24)
            }
        }
        .frame(width: 560, height: 420)
        .background(Color(.surface))
        .onAppear { focused = true }
        .onExitCommand { dismiss() }
        .task(id: text) {
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            hits = (try? search(text)) ?? []
            selected = 0
        }
    }

    private func choose(_ index: Int) {
        guard hits.indices.contains(index) else { return }
        open(hits[index])
        dismiss()
    }

    private func search(_ text: String) throws -> [Hit] {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        var hits: [Hit] = []
        hits += try database.recipeCards(RecipeQuery(text: text, sort: [SortTerm(.relevance)]), limit: 6).rows.map {
            Hit(
                kind: .recipe, id: $0.id, title: $0.title,
                detail: $0.perServing.map { "\(Formatting.number($0.kcal, digits: 0)) ккал" } ?? "")
        }
        hits += try database.products(ProductQuery(text: text, sort: [SortTerm(.relevance)]), limit: 6).rows.map {
            Hit(
                kind: .product, id: $0.id, title: $0.name,
                detail: $0.kcal.map { "\(Formatting.number($0, digits: 0)) ккал/100 г" } ?? "")
        }
        hits += try database.pantry(PantryQuery(text: text), limit: 4).rows.map { entry in
            let amount = entry.item.quantity.map { Formatting.quantity($0, entry.product.baseUnit.unit) }
            return Hit(
                kind: .pantry, id: entry.product.id, title: entry.product.name,
                detail: amount ?? entry.item.status.title)
        }
        hits += try database.shopping(ShoppingQuery(text: text), limit: 4).rows.map { entry in
            Hit(kind: .shopping, id: entry.id, title: entry.name, detail: entry.item.isChecked ? "куплено" : "купить")
        }
        let key = SearchText.normalized(text)
        hits += try database.categorySummaries().filter { SearchText.normalized($0.category.name).contains(key) }
            .prefix(4).map {
                Hit(
                    kind: .category, id: $0.id, title: $0.category.name,
                    detail: Formatting.count($0.count, "рецепт", "рецепта", "рецептов"))
            }
        return hits
    }
}
