import MealCore
import MealStore
import SwiftUI

/// The recipe page in edit mode: the same blocks, as fields.
struct RecipeEditor: View {
    let database: AppDatabase
    @Binding var details: RecipeDetails
    let categories: [RecipeCategory]
    let mealTypes: [MealType]
    let problem: String?

    @State private var addingCategory = false
    @State private var categoryName = ""
    @State private var categoryProblem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PhotoEditor(images: database.images, photo: $details.recipe.photo)
                TextField("Название", text: $details.recipe.title, axis: .vertical)
                    .font(.system(size: 30, weight: .bold))
                    .textFieldStyle(.plain)
                if let problem {
                    Label(problem, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
                properties
                tags
                IngredientsEditor(database: database, details: $details)
                StepsEditor(steps: $details.steps)
                links
                nutritionOverride
                notes
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .alert("Новая категория", isPresented: $addingCategory) {
            TextField("Название", text: $categoryName)
            Button("Создать", action: addCategory)
            Button("Отмена", role: .cancel) {}
        }
        .alert("Не получилось", isPresented: isPresent($categoryProblem), presenting: categoryProblem) { _ in
            Button("Понятно") {}
        } message: { problem in
            Text(problem)
        }
    }

    // MARK: - Properties

    private var properties: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
            GridRow {
                Text("Порций")
                Stepper(value: $details.recipe.servings, in: 1...50) {
                    Text("\(details.recipe.servings)")
                        .monospacedDigit()
                }
                .fixedSize()
            }
            GridRow {
                Text("Подготовка, мин")
                TextField("—", value: $details.recipe.prepMinutes, format: Formatting.integer)
                    .frame(width: 80)
            }
            GridRow {
                Text("Готовка, мин")
                TextField("—", value: $details.recipe.cookMinutes, format: Formatting.integer)
                    .frame(width: 80)
            }
            GridRow {
                Text("Вес готового блюда, г")
                HStack {
                    TextField("—", value: $details.recipe.yieldGrams, format: Formatting.decimal)
                        .frame(width: 80)
                    Text("без него калорийность на 100 г считается по сырым продуктам")
                        .font(.callout)
                        .foregroundStyle(Color(.textSecondary))
                }
            }
        }
        .foregroundStyle(Color(.textPrimary))
    }

    // MARK: - Categories and meals

    private var tags: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Категории")
                    .foregroundStyle(Color(.textSecondary))
                    .frame(width: 110, alignment: .leading)
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(categories) { category in
                            Button {
                                toggle(category.id)
                            } label: {
                                TagView(
                                    name: category.name, color: category.color,
                                    isOn: details.categoryIDs.contains(category.id))
                            }
                            .buttonStyle(.plain)
                        }
                        Button("Новая…") {
                            categoryName = ""
                            addingCategory = true
                        }
                        .buttonStyle(.link)
                    }
                }
                .scrollIndicators(.never)
            }
            HStack(spacing: 6) {
                Text("Подходит на")
                    .foregroundStyle(Color(.textSecondary))
                    .frame(width: 110, alignment: .leading)
                ForEach(mealTypes) { meal in
                    Button {
                        if details.mealTypeIDs.contains(meal.id) {
                            details.mealTypeIDs.remove(meal.id)
                        } else {
                            details.mealTypeIDs.insert(meal.id)
                        }
                    } label: {
                        TagView(name: meal.name, color: meal.color, isOn: details.mealTypeIDs.contains(meal.id))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func toggle(_ id: RecipeCategory.ID) {
        if let index = details.categoryIDs.firstIndex(of: id) {
            details.categoryIDs.remove(at: index)
        } else {
            details.categoryIDs.append(id)
        }
    }

    private func addCategory() {
        do {
            let category = try database.newCategory(named: categoryName)
            details.categoryIDs.append(category.id)
        } catch {
            categoryProblem = String(describing: error)
        }
    }

    // MARK: - Links, nutrition, notes

    private var links: some View {
        EditorSection("Видео и источник") {
            VStack(alignment: .leading, spacing: 6) {
                TextField(
                    "Видео: ссылка на YouTube, Rutube, VK Видео или код <iframe>",
                    text: Binding(get: { details.recipe.videoURL ?? "" }, set: { details.recipe.videoURL = $0 }))
                if let video = details.recipe.videoURL, !video.isEmpty {
                    if let player = VideoEmbed.player(for: video) {
                        Label(
                            "\(player.provider.title): видео будет на странице рецепта", systemImage: "checkmark.circle"
                        )
                        .foregroundStyle(Color(.textSecondary))
                    } else {
                        Label("Плеер не найден — на странице будет ссылка", systemImage: "link")
                            .foregroundStyle(Color(.textSecondary))
                    }
                }
            }
            TextField(
                "Источник: ссылка на рецепт",
                text: Binding(get: { details.recipe.sourceURL ?? "" }, set: { details.recipe.sourceURL = $0 }))
        }
    }

    private var nutritionOverride: some View {
        EditorSection("КБЖУ") {
            Toggle(
                "Взять КБЖУ на 100 г из источника вместо расчёта по ингредиентам",
                isOn: Binding(
                    get: { details.recipe.nutritionOverride != nil },
                    set: { isOn in
                        details.recipe.nutritionOverride = isOn ? (details.nutrition.per100g ?? .zero) : nil
                    }))
            if details.recipe.nutritionOverride != nil {
                HStack(spacing: 16) {
                    overrideField("Ккал", \.kcal)
                    overrideField("Белки, г", \.protein)
                    overrideField("Жиры, г", \.fat)
                    overrideField("Углеводы, г", \.carbs)
                }
            } else if let perServing = details.nutrition.perServing {
                Text(
                    "По ингредиентам: \(Formatting.number(perServing.kcal, digits: 0)) ккал на порцию, Б \(Formatting.number(perServing.protein)) · Ж \(Formatting.number(perServing.fat)) · У \(Formatting.number(perServing.carbs)) г"
                )
                .foregroundStyle(Color(.textSecondary))
            }
        }
    }

    private func overrideField(_ title: String, _ keyPath: WritableKeyPath<Nutrition, Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.callout)
                .foregroundStyle(Color(.textSecondary))
            TextField(
                title,
                value: Binding(
                    get: { details.recipe.nutritionOverride?[keyPath: keyPath] ?? 0 },
                    set: { details.recipe.nutritionOverride?[keyPath: keyPath] = $0 }),
                format: Formatting.decimal
            )
            .frame(width: 90)
        }
    }

    private var notes: some View {
        EditorSection("Заметки") {
            TextEditor(text: $details.recipe.notes)
                .font(.body)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(.surfaceRaised), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

/// A titled block of the editor.
struct EditorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.bold())
            content()
        }
    }
}

/// The steps as numbered fields; a step drags onto another to move there.
struct StepsEditor: View {
    @Binding var steps: [RecipeStep]

    var body: some View {
        EditorSection("Способ приготовления") {
            ForEach($steps) { $step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\((steps.firstIndex { $0.id == step.id } ?? 0) + 1).")
                        .monospacedDigit()
                        .foregroundStyle(Color(.textSecondary))
                        .frame(width: 26, alignment: .trailing)
                    TextField("Что сделать", text: $step.text, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    Button("Удалить шаг", systemImage: "minus.circle") {
                        steps.removeAll { $0.id == step.id }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
                .draggable(step.id.uuidString)
                .dropDestination(for: String.self) { items, _ in
                    move(items.first, before: step.id)
                }
            }
            Button("Добавить шаг", systemImage: "plus") { steps.append(RecipeStep(text: "")) }
                .buttonStyle(.borderless)
        }
    }

    /// Moves the dragged line to where the target is.
    private func move(_ dragged: String?, before target: RecipeStep.ID) {
        guard let dragged, let id = UUID(uuidString: dragged), id != target,
            let from = steps.firstIndex(where: { $0.id == id }), let to = steps.firstIndex(where: { $0.id == target })
        else { return }
        steps.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
    }
}
