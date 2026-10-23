import MealCore
import MealStore
import SwiftUI

/// Deleted recipes: they can come back for 30 days, then go for good.
struct TrashSheet: View {
    let database: AppDatabase

    @Environment(\.dismiss) private var dismiss
    @State private var recipes: [Recipe] = []
    @State private var confirmsEmptying = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Корзина")
                .font(.title2.bold())
            Text("Рецепты удаляются отсюда насовсем через 30 дней.")
                .foregroundStyle(Color(.textSecondary))
            List(recipes) { recipe in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recipe.title)
                        if let deleted = recipe.deletedAt {
                            Text(
                                "Удалён \(deleted.formatted(.relative(presentation: .named).locale(Formatting.locale)))"
                            )
                            .font(.caption)
                            .foregroundStyle(Color(.textSecondary))
                        }
                    }
                    Spacer()
                    Button("Восстановить") { run { try database.restoreRecipe(id: recipe.id) } }
                    Button("Удалить навсегда", role: .destructive) { run { try database.deleteRecipe(id: recipe.id) } }
                }
            }
            .animation(Motion.layout, value: recipes.map(\.id))
            .overlay {
                if recipes.isEmpty {
                    ContentUnavailableView("Корзина пуста", systemImage: "trash")
                }
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
            HStack {
                Button("Очистить корзину", role: .destructive) { confirmsEmptying = true }
                    .disabled(recipes.isEmpty)
                Spacer()
                Button("Готово") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 440)
        .task {
            do {
                for try await recipes in database.observeTrash() { self.recipes = recipes }
            } catch {
                problem = String(describing: error)
            }
        }
        .confirmationDialog("Удалить все рецепты из корзины?", isPresented: $confirmsEmptying) {
            Button("Удалить навсегда", role: .destructive) { run { _ = try database.emptyTrash(olderThan: 0) } }
        } message: {
            Text("Вернуть их будет нельзя.")
        }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
            problem = nil
        } catch {
            problem = String(describing: error)
        }
    }
}
