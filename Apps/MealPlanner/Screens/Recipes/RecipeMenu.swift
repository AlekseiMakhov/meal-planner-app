import MealCore
import MealStore
import SwiftUI

/// What a recipe's menu in the gallery and the table does; the screen owns the database and the dialogs.
struct RecipeActions {
    let open: (Recipe.ID) -> Void
    let setCategory: (RecipeCategory.ID, Bool, [Recipe.ID]) -> Void
    /// «Новая категория…»: the recipes go into the category as soon as it is named.
    let newCategory: ([Recipe.ID]) -> Void
    let setFavorite: (Bool, [Recipe.ID]) -> Void
    let duplicate: (Recipe.ID) -> Void
    let trash: ([Recipe.ID]) -> Void
}

/// The context menu of a recipe, or of several chosen in the table: open, categories, favourite, a copy, the
/// trash.
struct RecipeMenu: View {
    let recipes: [RecipeCard]
    let categories: [RecipeCategory]
    let actions: RecipeActions

    var body: some View {
        let ids = recipes.map(\.id)
        if !recipes.isEmpty {
            if recipes.count == 1 {
                Button("Открыть") { actions.open(ids[0]) }
                Divider()
            }
            Menu("Категории") {
                CategoryToggles(categories: categories) { id in
                    recipes.allSatisfy { $0.categoryIDs.contains(id) }
                } set: { id, isOn in
                    actions.setCategory(id, isOn, ids)
                } new: {
                    actions.newCategory(ids)
                }
            }
            let isFavorite = recipes.allSatisfy(\.isFavorite)
            Button(isFavorite ? "Убрать из избранного" : "В избранное") { actions.setFavorite(!isFavorite, ids) }
            if recipes.count == 1 {
                Button("Дублировать") { actions.duplicate(ids[0]) }
            }
            Divider()
            Button("В корзину", role: .destructive) { actions.trash(ids) }
        }
    }
}

/// Each category, ticked when the recipe — or every recipe chosen — is in it, then «Новая категория…».
struct CategoryToggles: View {
    let categories: [RecipeCategory]
    let isChosen: (RecipeCategory.ID) -> Bool
    let set: (RecipeCategory.ID, Bool) -> Void
    let new: () -> Void

    var body: some View {
        ForEach(categories) { category in
            Toggle(
                category.name, isOn: Binding(get: { isChosen(category.id) }, set: { set(category.id, $0) }))
        }
        if !categories.isEmpty {
            Divider()
        }
        Button("Новая категория…", action: new)
    }
}

/// A recipe under the pointer while it is dragged onto the week or a category.
struct RecipeDragPreview: View {
    let title: String

    var body: some View {
        Text(title)
            .padding(8)
            .background(Color(.card), in: RoundedRectangle(cornerRadius: 6))
    }
}

extension View {
    /// «Новая категория» for recipes: asks for a name, then creates the category with the recipes already in it.
    func newCategoryAlert(
        for recipes: Binding<[Recipe.ID]?>, database: AppDatabase, problem: Binding<String?>
    ) -> some View {
        modifier(NewCategoryAlert(recipes: recipes, database: database, problem: problem))
    }
}

private struct NewCategoryAlert: ViewModifier {
    /// The recipes waiting for the new category; nil while the alert is closed.
    @Binding var recipes: [Recipe.ID]?
    let database: AppDatabase
    @Binding var problem: String?

    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert("Новая категория", isPresented: isPresent($recipes), presenting: recipes) { recipes in
                TextField("Название", text: $name)
                Button("Создать") { create(with: recipes) }
                Button("Отмена", role: .cancel) {}
            } message: { recipes in
                Text(recipes.count == 1 ? "Рецепт сразу попадёт в неё." : "Рецепты сразу попадут в неё.")
            }
            .onChange(of: recipes) {
                if recipes != nil { name = "" }
            }
    }

    private func create(with recipes: [Recipe.ID]) {
        do {
            let category = try database.newCategory(named: name)
            try database.setCategory(category.id, isOn: true, recipeIDs: recipes)
        } catch {
            problem = String(describing: error)
        }
    }
}
