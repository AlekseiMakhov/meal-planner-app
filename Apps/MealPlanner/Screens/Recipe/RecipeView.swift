import MealCore
import MealStore
import SwiftUI

/// A recipe to read, laid out like the Notion page it replaces: cover, title, nutrition, ingredients for the
/// chosen number of servings, steps, notes and links.
struct RecipeView: View {
    let details: RecipeDetails
    @Binding var servings: Int
    let categories: [RecipeCategory]
    let mealTypes: [MealType]
    let images: ImageStore

    @State private var showsVideo = false

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
                        Button("Смотреть видео", systemImage: "play.fill") { showsVideo = true }
                            .buttonStyle(.borderedProminent)
                            .padding(16)
                    }
                }
        }
    }

    // MARK: - Header

    @ViewBuilder private var tags: some View {
        let chosen = categories.filter { details.categoryIDs.contains($0.id) }
        let meals = mealTypes.filter { details.mealTypeIDs.contains($0.id) }
        if !chosen.isEmpty || !meals.isEmpty {
            HStack(spacing: 6) {
                ForEach(chosen) { TagView(name: $0.name, color: $0.color) }
                ForEach(meals) { TagView(name: $0.name, color: $0.color) }
            }
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Ингредиенты \(Formatting.servings(servings))")
                .font(.title2.bold())
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
                                    .gridCellColumns(3)
                                    .padding(.top, 6)
                            }
                        }
                        ForEach(group.lines) { line in
                            ingredientRow(line.scaled(to: servings, of: recipe.servings))
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

    private func ingredientRow(_ ingredient: RecipeIngredient) -> some View {
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
                .gridColumnAlignment(.trailing)
            Text(amount.unit)
                .foregroundStyle(Color(.textSecondary))
        }
        .textSelection(.enabled)
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
