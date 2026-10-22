import SwiftUI

/// A section's screen. Each one arrives with its stage of the plan; until then it says which.
struct SectionScreen: View {
    let section: AppModel.Section

    var body: some View {
        ContentUnavailableView {
            Label(section.title, systemImage: section.symbol)
        } description: {
            Text(upcoming)
                .foregroundStyle(Color(.textSecondary))
        }
        .foregroundStyle(Color(.textPrimary))
    }

    private var upcoming: String {
        switch section {
        case .recipes: "Галерея по категориям, страница рецепта и редактор появятся на этапе 2."
        case .planner: "Сетка недели с перетаскиванием карточек появится на этапе 5."
        case .pantry: "Запасы дома появятся на этапе 4."
        case .shopping: "Список покупок появится на этапе 4, синхронизация с «Напоминаниями» — на этапе 6."
        case .products: "База продуктов с КБЖУ появится на этапе 1."
        }
    }
}
