import MealCore
import MealStore
import SwiftUI

/// The recipes beside the week, to drag into its cells: search, the meal they suit, what can be cooked now, and
/// what has not been cooked for long.
struct PlannerLibrary: View {
    let database: AppDatabase
    let mealTypes: [MealType]
    let images: ImageStore

    @State private var list: PagedList<RecipeQuery, RecipeCard>
    @State private var searchText = ""

    init(database: AppDatabase, mealTypes: [MealType]) {
        self.database = database
        self.mealTypes = mealTypes
        images = database.images
        _list = State(
            initialValue: PagedList(query: RecipeQuery()) { query, limit in
                database.observeRecipeCards(query, limit: limit)
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Рецепты")
                .font(.headline)
            TextField("Поиск", text: $searchText)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 6) {
                Menu(mealTitle) {
                    Button("Любой приём пищи") { list.query.mealTypeIDs = [] }
                    Divider()
                    ForEach(mealTypes) { meal in
                        Button(meal.name) { list.query.mealTypeIDs = [meal.id] }
                    }
                }
                .fixedSize()
                Toggle(
                    "Всё есть",
                    isOn: Binding(
                        get: { list.query.maxMissing == 0 }, set: { list.query.maxMissing = $0 ? 0 : nil })
                )
                .toggleStyle(.button)
                Spacer()
                Menu {
                    Picker("Порядок", selection: sortKey) {
                        Text("Название").tag(RecipeQuery.SortKey.title)
                        Text("Давно не готовили").tag(RecipeQuery.SortKey.lastCooked)
                        Text("Наличие продуктов").tag(RecipeQuery.SortKey.availability)
                        Text("Калорийность порции").tag(RecipeQuery.SortKey.kcalPerServing)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Порядок", systemImage: "arrow.up.arrow.down")
                        .labelStyle(.iconOnly)
                }
                .fixedSize()
            }
            .controlSize(.small)
            List(list.rows) { card in
                LibraryRow(card: card, images: images)
                    .draggable(PlanDragItem.recipe(card.id)) {
                        Text(card.title)
                            .padding(8)
                            .background(Color(.card), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .onAppear { list.rowAppeared(card.id) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            Text("Перетащите рецепт в день недели.")
                .font(.caption)
                .foregroundStyle(Color(.textSecondary))
        }
        .padding(12)
        .task { list.start() }
        .task(id: searchText) {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            list.query.text = searchText
            if !searchText.isEmpty, list.query.sort.first?.key == .title {
                list.query.sort = [SortTerm(.relevance)]
            }
        }
        .onDisappear { list.stop() }
    }

    private var mealTitle: String {
        guard let id = list.query.mealTypeIDs.first, let meal = mealTypes.first(where: { $0.id == id }) else {
            return "Любой приём пищи"
        }
        return meal.name
    }

    private var sortKey: Binding<RecipeQuery.SortKey> {
        Binding {
            list.query.sort.first?.key ?? .title
        } set: { key in
            list.query.sort = [SortTerm(key)]
        }
    }
}

/// A recipe in the list beside the week: photo, title, a serving's calories and what is missing at home.
private struct LibraryRow: View {
    let card: RecipeCard
    let images: ImageStore

    @State private var image: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            Color(.surfaceRaised)
                .frame(width: 36, height: 36)
                .overlay {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "fork.knife")
                            .foregroundStyle(Color(.textSecondary).opacity(0.5))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let kcal = card.perServing?.kcal {
                        Text("\(card.isNutritionComplete ? "" : "≈ ")\(Formatting.number(kcal, digits: 0)) ккал")
                            .foregroundStyle(Color(.textSecondary))
                    }
                    MissingLabel(count: card.missingCount)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .task(id: card.photo) {
            guard let photo = card.photo else {
                image = nil
                return
            }
            image = await Thumbnails.shared.image(at: images.url(for: photo), pixels: 96)
        }
    }
}
