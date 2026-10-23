import MealCore
import MealStore
import SwiftUI

/// A section's screen. Sections arrive with their stages of the plan; until then the screen says when.
struct SectionScreen: View {
    let section: AppModel.Section
    let category: RecipeCategory.ID?
    let database: AppDatabase?

    var body: some View {
        switch (section, database) {
        case (.recipes, let database?):
            RecipesScreen(database: database, categoryID: category)
        case (.products, let database?):
            ProductsScreen(database: database)
        case (.pantry, let database?):
            PantryScreen(database: database)
        case (.shopping, let database?):
            ShoppingScreen(database: database)
        default:
            ContentUnavailableView {
                Label(section.title, systemImage: section.symbol)
            } description: {
                Text(upcoming)
                    .foregroundStyle(Color(.textSecondary))
            }
            .foregroundStyle(Color(.textPrimary))
        }
    }

    private var upcoming: String {
        switch section {
        case .planner: "Сетка недели с перетаскиванием карточек появится на этапе 5."
        case .recipes, .products, .pantry, .shopping: "База данных не открылась, поэтому показать нечего."
        }
    }
}
