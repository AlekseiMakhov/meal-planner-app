import MealCore
import MealStore
import SwiftUI

/// A recipe to read, laid out like the Notion page it replaces: cover, title, nutrition, ingredients for the
/// chosen number of servings with what there is at home, steps, notes and links.
struct RecipeView: View {
    let details: RecipeDetails
    @Binding var servings: Int
    let categories: [RecipeCategory]
    let mealTypes: [MealType]
    let images: ImageStore
    /// What there is at home of the recipe's products.
    let pantry: [Product.ID: PantryItem]
    /// Puts a line, or with nil everything missing, on the shopping list; returns how many lines went there.
    let toShopping: (RecipeIngredient?) -> Int
    /// Puts the recipe into a category or takes it out, without the editor.
    let setCategory: (RecipeCategory.ID, Bool) -> Void
    let newCategory: () -> Void

    @State private var showsVideo = false
    @State private var added: String?

    private var recipe: Recipe {
        details.recipe
    }

    private var player: VideoEmbed.Player? {
        recipe.videoURL.flatMap(VideoEmbed.player)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                cover
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(recipe.title)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color(.textPrimary))
                            .textSelection(.enabled)
                        tags
                    }
                    properties
                    ingredients
                    steps
                    notes
                    links
                }
                // Another number of servings rolls the amounts and the nutrition over to the new values.
                .animation(Motion.layout, value: servings)
                .padding(.horizontal, 40)
                .padding(.vertical, 28)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Cover

    @ViewBuilder private var cover: some View {
        if let player, showsVideo || recipe.photo == nil {
            VideoPlayerView(player: player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
                .background(.black)
        } else if let photo = recipe.photo {
            CoverImage(url: images.url(for: photo), height: 300)
                .overlay(alignment: .bottomTrailing) {
                    if player != nil {
                        Button("Смотреть видео", systemImage: "play.fill") {
                            withAnimation(Motion.swap) { showsVideo = true }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(16)
                    }
                }
        }
    }

    // MARK: - Header

    /// The categories and meals; «+» puts the recipe into a category right on the page.
    private var tags: some View {
        let chosen = categories.filter { details.categoryIDs.contains($0.id) }
        let meals = mealTypes.filter { details.mealTypeIDs.contains($0.id) }
        return HStack(spacing: 6) {
            ForEach(chosen) { TagView(name: $0.name, color: $0.color) }
            ForEach(meals) { TagView(name: $0.name, color: $0.color) }
            Menu {
                CategoryToggles(categories: categories) {
                    details.categoryIDs.contains($0)
                } set: { id, isOn in
                    setCategory(id, isOn)
                } new: {
                    newCategory()
                }
            } label: {
                if chosen.isEmpty {
                    Label("Добавить в категорию", systemImage: "plus")
                } else {
                    Image(systemName: "plus")
                }
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(Color(.textSecondary))
            .help("Добавить рецепт в категорию или убрать из неё")
        }
    }

    private var properties: some View {
        let nutrition = details.nutrition
        let scale = recipe.servings > 0 ? Double(servings) / Double(recipe.servings) : 1
        let approximate = nutrition.isComplete ? "" : "≈ "
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 36) {
                property(
                    "Калорийность",
                    nutrition.per100g.map { "\(approximate)\(Formatting.number($0.kcal, digits: 0)) ккал/100 г" })
                property(
                    "Порция", nutrition.perServing.map { "\(approximate)\(Formatting.number($0.kcal, digits: 0)) ккал" }
                )
                property(
                    "Б · Ж · У на порцию",
                    nutrition.perServing.map {
                        "\(Formatting.number($0.protein)) · \(Formatting.number($0.fat)) · \(Formatting.number($0.carbs)) г"
                    })
                if let total = recipe.totalMinutes {
                    property("Время", Formatting.minutes(total))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Порции")
                        .foregroundStyle(Color(.textSecondary))
                    Stepper(value: $servings, in: 1...50) {
                        Text("\(servings)")
                            .monospacedDigit()
                            .font(.title3)
                    }
                    .help(
                        scale == 1
                            ? "Ингредиенты пересчитаются на выбранное число порций"
                            : "Как в рецепте: \(recipe.servings)")
                }
            }
            if !nutrition.isComplete {
                Label(incompleteNote, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(Color(.textSecondary))
            }
            if nutrition.isFromSource {
                Label("КБЖУ на 100 г взято из источника рецепта", systemImage: "link")
                    .font(.callout)
                    .foregroundStyle(Color(.textSecondary))
            }
        }
    }

    private func property(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .foregroundStyle(Color(.textSecondary))
            Text(value ?? "—")
                .font(.title3)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(value == nil ? Color(.textSecondary) : Color(.textPrimary))
        }
    }

    /// «Посчитано по 4 из 5 ингредиентов: нет КБЖУ у «Овсянка», не пересчитать в граммы «1 пучок».»
    private var incompleteNote: String {
        let total = details.nutrition.total
        var reasons: [String] = []
        for ingredient in details.ingredients where ingredient.isMeasured {
            guard let product = details.products[ingredient.productID] else { continue }
            if product.nutrition == nil {
                reasons.append("нет КБЖУ у «\(product.name)»")
            } else if ingredient.grams(of: product) == nil {
                let amount = Formatting.amount(ingredient)
                reasons.append("«\(amount.amount) \(amount.unit)» \(product.name.lowercased()) не пересчитать в граммы")
            }
        }
        let counted = "Посчитано по \(total.counted) из \(total.ingredients) ингредиентов"
        return reasons.isEmpty ? counted + "." : counted + ": " + reasons.joined(separator: "; ") + "."
    }

    // MARK: - Ingredients

    private var ingredients: some View {
        let availability = details.availability(servings: servings, pantry: pantry)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ингредиенты \(Formatting.servings(servings))")
                    .font(.title2.bold())
                Spacer()
                if let added {
                    Text(added)
                        .foregroundStyle(Color(.textSecondary))
                        .noticeTransition()
                }
                if availability.missingCount > 0 {
                    Button("Недостающее в покупки", systemImage: "cart.badge.plus") { add(nil) }
                        .help(
                            "Не хватает \(Formatting.count(availability.missingCount, "ингредиента", "ингредиентов", "ингредиентов"))"
                        )
                } else if !details.ingredients.isEmpty {
                    Label("Всё есть", systemImage: "checkmark.circle")
                        .foregroundStyle(Color(.statusInStock))
                }
            }
            if details.ingredients.isEmpty {
                Text("Ингредиентов пока нет.")
                    .foregroundStyle(Color(.textSecondary))
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    ForEach(groupedIngredients, id: \.offset) { group in
                        if let title = group.title {
                            GridRow {
                                Text(title)
                                    .font(.headline)
                                    .foregroundStyle(Color(.textSecondary))
                                    .gridCellColumns(5)
                                    .padding(.top, 6)
                            }
                        }
                        ForEach(group.lines) { line in
                            ingredientRow(
                                line.scaled(to: servings, of: recipe.servings), availability.lines[line.id],
                                original: line)
                            Divider()
                                .gridCellUnsizedAxes(.horizontal)
                                .opacity(0.5)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color(.card), in: RoundedRectangle(cornerRadius: 12))
    }

    private func ingredientRow(
        _ ingredient: RecipeIngredient, _ availability: Availability?, original: RecipeIngredient
    ) -> some View {
        let product = details.products[ingredient.productID]
        let amount = Formatting.amount(ingredient)
        return GridRow {
            VStack(alignment: .leading, spacing: 2) {
                Text(product?.name ?? "Продукт удалён")
                    .foregroundStyle(Color(.textPrimary))
                let note = [ingredient.note, ingredient.isOptional ? "по желанию" : nil].compactMap { $0 }
                if !note.isEmpty {
                    Text(note.joined(separator: ", "))
                        .font(.callout)
                        .foregroundStyle(Color(.textSecondary))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(amount.amount)
                .monospacedDigit()
                .contentTransition(.numericText())
                .gridColumnAlignment(.trailing)
            Text(amount.unit)
                .foregroundStyle(Color(.textSecondary))
            if let availability, let product {
                AvailabilityBadge(availability: availability, unit: product.baseUnit.unit)
                Button("В покупки", systemImage: "cart.badge.plus") { add(original) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Добавить «\(product.name)» в покупки")
                    .opacity(availability == .enough ? 0 : 1)
                    .disabled(availability == .enough)
            } else {
                Color.clear.frame(width: 0, height: 0)
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .textSelection(.enabled)
    }

    private func add(_ line: RecipeIngredient?) {
        let count = toShopping(line)
        withAnimation(Motion.pop) { added = count == 0 ? "Уже в покупках" : "Добавлено в покупки" }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(Motion.pop) { added = nil }
        }
    }

    private struct IngredientGroup {
        let offset: Int
        let title: String?
        let lines: [RecipeIngredient]
    }

    /// Lines under their headings, in the recipe's order: a new heading starts a new group.
    private var groupedIngredients: [IngredientGroup] {
        var groups: [IngredientGroup] = []
        for ingredient in details.ingredients {
            if let last = groups.last, last.title == ingredient.group {
                groups[groups.count - 1] = IngredientGroup(
                    offset: last.offset, title: last.title, lines: last.lines + [ingredient])
            } else {
                groups.append(IngredientGroup(offset: groups.count, title: ingredient.group, lines: [ingredient]))
            }
        }
        return groups
    }

    // MARK: - Steps, notes, links

    @ViewBuilder private var steps: some View {
        if !details.steps.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Способ приготовления")
                    .font(.title2.bold())
                ForEach(Array(details.steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1).")
                            .monospacedDigit()
                            .foregroundStyle(Color(.textSecondary))
                            .frame(width: 26, alignment: .trailing)
                        Text(step.text)
                            .foregroundStyle(Color(.textPrimary))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.title3)
                }
            }
        }
    }

    @ViewBuilder private var notes: some View {
        let text = recipe.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Заметки")
                    .font(.title2.bold())
                Text(text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var links: some View {
        let source = recipe.sourceURL.flatMap(URL.init(string:)).flatMap {
            $0.scheme?.hasPrefix("http") == true ? $0 : nil
        }
        let video =
            player?.page
            ?? recipe.videoURL.flatMap(URL.init(string:)).flatMap {
                $0.scheme?.hasPrefix("http") == true ? $0 : nil
            }
        if source != nil || video != nil {
            VStack(alignment: .leading, spacing: 12) {
                if let video {
                    LinkPreview(url: video)
                }
                if let source, source != video {
                    LinkPreview(url: source)
                }
            }
        }
    }
}

/// What there is at home for a line: «Есть», «Мало · ещё 20 г», «Нет», «?».
struct AvailabilityBadge: View {
    let availability: Availability
    /// The unit the pantry counts the product in.
    let unit: MeasureUnit

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(availability == .unknown ? Color(.textSecondary) : Color(.textPrimary))
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.16), in: Capsule())
        .help(help)
    }

    private var title: String {
        switch availability {
        case .enough: "Есть"
        case .low(let missing): "Мало · ещё \(Formatting.quantity(missing, unit))"
        case .missing: "Нет"
        case .unknown: "?"
        }
    }

    private var color: Color {
        switch availability {
        case .enough: Color(.statusInStock)
        case .low: Color(.statusLow)
        case .missing: Color(.statusMissing)
        case .unknown: Color(.textSecondary)
        }
    }

    private var help: String {
        switch availability {
        case .enough: "Дома хватает"
        case .low(let missing): "Дома есть, но нужно ещё \(Formatting.quantity(missing, unit))"
        case .missing: "Дома нет"
        case .unknown: "Не сравнить с запасами: у продукта не задан вес этой единицы"
        }
    }
}

/// A photo filling its width at a fixed height, loaded off the main thread.
struct CoverImage: View {
    let url: URL
    let height: CGFloat

    @State private var image: NSImage?

    var body: some View {
        Color(.surfaceRaised)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .clipped()
            .task(id: url) { image = await Thumbnails.shared.image(at: url, pixels: 1600) }
    }
}
