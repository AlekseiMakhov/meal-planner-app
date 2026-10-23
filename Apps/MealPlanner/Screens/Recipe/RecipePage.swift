import MealCore
import MealStore
import SwiftUI

/// A recipe as a page, as in Notion; «Править» (⌘E) turns the page into its editor. Changes save themselves
/// a moment after the last one; «Готово» saves at once and shows the page again.
struct RecipePage: View {
    let database: AppDatabase
    let route: RecipeRoute
    let categories: [RecipeCategory]
    let mealTypes: [MealType]
    let onClose: () -> Void

    @Environment(AppModel.self) private var model
    @State private var details: RecipeDetails?
    @State private var draft: RecipeDetails?
    /// The draft as it was last saved, so saving again only happens after a change.
    @State private var savedDraft: RecipeDetails?
    @State private var servings: Int?
    @State private var problem: String?
    @State private var isGone = false
    @State private var startedEditing = false
    @State private var confirmsTrash = false
    @State private var pantry: [Product.ID: PantryItem] = [:]

    var body: some View {
        Group {
            if let draft = Binding($draft) {
                RecipeEditor(
                    database: database, details: draft, categories: categories, mealTypes: mealTypes, problem: problem)
            } else if let details, !isGone {
                RecipeView(
                    details: details,
                    servings: Binding(get: { servings ?? details.recipe.servings }, set: { servings = $0 }),
                    categories: categories, mealTypes: mealTypes, images: database.images, pantry: pantry
                ) { line in
                    toShopping(line, of: details)
                }
            } else if isGone {
                ContentUnavailableView(
                    "Рецепта больше нет", systemImage: "trash", description: Text("Он в корзине или удалён."))
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.canvas))
        .navigationTitle(details?.recipe.title ?? "Рецепт")
        .toolbar { toolbar }
        .task(id: route.id) {
            do {
                for try await value in database.observeRecipe(id: route.id) {
                    details = value
                    isGone = value == nil || value?.recipe.deletedAt != nil
                    if route.startsEditing, !startedEditing, let value {
                        startedEditing = true
                        edit(value)
                    }
                }
            } catch {
                problem = String(describing: error)
            }
        }
        .task(id: productIDs) { await watchPantry() }
        .task(id: draft) {
            guard draft != nil, draft != savedDraft else { return }
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            save()
        }
        .onDisappear { save() }
        .confirmationDialog(
            "Переместить «\(details?.recipe.title ?? "")» в корзину?", isPresented: $confirmsTrash
        ) {
            Button("В корзину", role: .destructive, action: trash)
        } message: {
            Text("Его можно будет восстановить в течение 30 дней.")
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            if draft != nil {
                Button("Готово", action: finishEditing)
                    .keyboardShortcut("e", modifiers: .command)
            } else if let details, !isGone {
                Button(
                    details.recipe.isFavorite ? "Убрать из избранного" : "В избранное",
                    systemImage: details.recipe.isFavorite ? "star.fill" : "star"
                ) {
                    run { try database.setFavorite(!details.recipe.isFavorite, recipeID: details.recipe.id) }
                }
                Button("Править", systemImage: "pencil") { edit(details) }
                    .keyboardShortcut("e", modifiers: .command)
                ShareButton {
                    RecipeShare.items(
                        for: details, servings: servings ?? details.recipe.servings, images: database.images)
                }
                Menu("Ещё", systemImage: "ellipsis.circle") {
                    Button("Дозаполнить с Claude", systemImage: "sparkles") {
                        model.askClaude(ClaudeRequest.fillRecipe("«\(details.recipe.title)» (id \(details.recipe.id))"))
                    }
                    Divider()
                    Button("Дублировать") { run { _ = try database.duplicateRecipe(id: details.recipe.id) } }
                    Divider()
                    Button("В корзину…", role: .destructive) { confirmsTrash = true }
                }
            }
        }
    }

    /// What there is at home of the recipe's products, kept current while the page is open.
    private var productIDs: Set<Product.ID> {
        Set(details?.ingredients.map(\.productID) ?? [])
    }

    private func watchPantry() async {
        do {
            for try await items in database.observePantryItems(for: productIDs) { pantry = items }
        } catch {
            problem = String(describing: error)
        }
    }

    /// One line, or with nil everything missing, onto the shopping list for the servings on screen.
    private func toShopping(_ line: RecipeIngredient?, of details: RecipeDetails) -> Int {
        let servings = servings ?? details.recipe.servings
        do {
            guard let line else {
                return try database.addShortages(ofRecipe: details.recipe.id, servings: servings).count
            }
            guard let product = details.products[line.productID] else { return 0 }
            let scaled = line.scaled(to: servings, of: details.recipe.servings)
            let reason = ShoppingReason(recipeID: details.recipe.id, title: details.recipe.title)
            let measured = scaled.isMeasured && !product.isStaple
            let addition =
                scaled.shortage(of: product, at: pantry[product.id], reason: reason)
                ?? ShoppingAddition(
                    product: product.id, amount: measured ? scaled.amountToHave : nil,
                    unit: measured ? scaled.effectiveUnit : nil, reason: reason)
            return try database.addToShopping([addition]).count
        } catch {
            problem = String(describing: error)
            return 0
        }
    }

    private func edit(_ details: RecipeDetails) {
        draft = details
        savedDraft = details
        problem = nil
    }

    private func save() {
        guard let draft, draft != savedDraft else { return }
        do {
            try database.save(draft)
            savedDraft = draft
            problem = nil
        } catch {
            problem = String(describing: error)
        }
    }

    /// Saves and shows the page; stays in the editor when the recipe cannot be saved, so nothing is lost.
    private func finishEditing() {
        save()
        if problem == nil {
            draft = nil
            savedDraft = nil
            servings = nil
        }
    }

    private func trash() {
        guard let id = details?.recipe.id else { return }
        run { try database.moveRecipeToTrash(id: id) }
        if problem == nil { onClose() }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            problem = String(describing: error)
        }
    }
}
