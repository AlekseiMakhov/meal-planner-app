import AppKit
import CoreTransferable
import MealCore
import MealStore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist: a dish of the menu while it is dragged.
    static let mealPlanItem = UTType(exportedAs: "inco.mealplanner.plan-item")
}

/// What is dragged: a recipe from a list — onto the week, or onto a category in the sidebar — or a dish already in
/// the menu.
enum PlanDragItem: Codable, Hashable, Transferable {
    case recipe(Recipe.ID)
    case entry(PlanEntry.ID)

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .mealPlanItem)
    }
}

/// What a cell asks the screen to do: the screen owns the database and the dialogs.
struct PlanActions {
    let drop: ([PlanDragItem], Day, MealType.ID, PlanEntry.ID?) -> Void
    let select: (PlanEntry.ID, Bool) -> Void
    let open: (PlanEntry) -> Void
    let setServings: (PlanEntry, Int) -> Void
    let cook: (PlanEntry) -> Void
    let undoCooked: (PlanEntry) -> Void
    let repeatOn: (PlanEntry, Day) -> Void
    let remove: (PlanEntry) -> Void
    let add: (Day, MealType.ID) -> Void
}

/// A day's meal: its dishes in order and the place to drop more.
struct PlanCell: View {
    let day: Day
    let meal: MealType
    let entries: [PlanEntry]
    let plan: WeekPlan
    let shortEntries: Set<PlanEntry.ID>
    let selection: Set<PlanEntry.ID>
    let width: CGFloat
    let images: ImageStore
    let actions: PlanActions

    @State private var isTargeted = false
    @State private var isHovered = false

    /// A narrow day: the dishes go without their photos, so the names keep the room.
    private var isCompact: Bool {
        width < 124
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(entries) { entry in
                PlanCard(
                    entry: entry, recipe: entry.recipeID.flatMap { plan.recipes[$0] },
                    isShort: shortEntries.contains(entry.id), isSelected: selection.contains(entry.id),
                    isCompact: isCompact, images: images
                )
                .onTapGesture(count: 2) { actions.open(entry) }
                .onTapGesture { actions.select(entry.id, NSEvent.modifierFlags.contains(.command)) }
                .draggable(PlanDragItem.entry(entry.id)) {
                    PlanCard(
                        entry: entry, recipe: entry.recipeID.flatMap { plan.recipes[$0] }, isShort: false,
                        isSelected: false, isCompact: isCompact, images: images
                    )
                    .frame(width: width - 12)
                }
                .dropDestination(for: PlanDragItem.self) { items, _ in
                    actions.drop(items, day, meal.id, entry.id)
                    return true
                }
                .contextMenu { menu(for: entry) }
            }
            Button {
                actions.add(day, meal.id)
            } label: {
                Label("Добавить", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity, minHeight: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(.textSecondary))
            .opacity(isHovered || entries.isEmpty ? 1 : 0)
            .help("Добавить блюдо")
        }
        .padding(6)
        .frame(width: width, alignment: .topLeading)
        .frame(minHeight: 70, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? Color.accentColor.opacity(0.18) : Color(.surface))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isTargeted ? Color.accentColor : Color(.hairline))
        )
        .animation(Motion.hover, value: isTargeted)
        .animation(Motion.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .dropDestination(for: PlanDragItem.self) { items, _ in
            actions.drop(items, day, meal.id, nil)
            return true
        } isTargeted: {
            isTargeted = $0
        }
    }

    @ViewBuilder private func menu(for entry: PlanEntry) -> some View {
        if entry.recipeID != nil {
            Button("Открыть рецепт") { actions.open(entry) }
            Menu("Порции") {
                ForEach(1...10, id: \.self) { count in
                    Toggle(
                        "\(count)",
                        isOn: Binding(get: { entry.servings == count }, set: { _ in actions.setServings(entry, count) })
                    )
                }
            }
            if entry.isCooked {
                Button("Отменить «Приготовлено»") { actions.undoCooked(entry) }
            } else {
                Button("Приготовлено…") { actions.cook(entry) }
            }
        }
        Menu("Повторить") {
            ForEach(plan.days, id: \.self) { other in
                Button("\(Formatting.weekdays[other.weekday - 1]) \(other.day)") { actions.repeatOn(entry, other) }
                    .disabled(other == day)
            }
        }
        Divider()
        Button("Убрать из меню", role: .destructive) { actions.remove(entry) }
    }
}

/// A dish: its photo, name, servings, a dot when the pantry no longer covers it, and a tick once cooked. A compact
/// card leaves the photo out.
struct PlanCard: View {
    let entry: PlanEntry
    let recipe: RecipeDetails?
    let isShort: Bool
    let isSelected: Bool
    var isCompact = false
    let images: ImageStore

    @State private var image: NSImage?

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if recipe?.recipe.photo != nil, !isCompact {
                Color(.surfaceRaised)
                    .frame(width: 28, height: 28)
                    .overlay {
                        if let image {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe?.recipe.title ?? entry.text ?? "")
                    .font(.callout.weight(.medium))
                    .italic(entry.recipeID == nil)
                    .foregroundStyle(Color(.textPrimary))
                    .lineLimit(isCompact ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    if entry.recipeID != nil {
                        Text(Formatting.count(entry.servings, "порция", "порции", "порций"))
                    }
                    if isShort, !entry.isCooked {
                        Circle()
                            .fill(Color(.statusMissing))
                            .frame(width: 6, height: 6)
                            .help("Дома не хватает продуктов")
                    }
                    if entry.isCooked {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(.statusInStock))
                            .help("Приготовлено")
                    }
                }
                .font(.caption)
                .foregroundStyle(Color(.textSecondary))
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.card), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .opacity(entry.isCooked ? 0.65 : 1)
        .animation(Motion.hover, value: isSelected)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .task(id: recipe?.recipe.photo) {
            guard let photo = recipe?.recipe.photo else {
                image = nil
                return
            }
            image = await Thumbnails.shared.image(at: images.url(for: photo), pixels: 96)
        }
    }
}

/// «+» in a cell: a recipe to search for, or text — «ужин в гостях».
struct PlanQuickAdd: View {
    let database: AppDatabase
    let meal: MealType
    let add: (Recipe.ID?, String?) -> Void

    @State private var text = ""
    @State private var results: [RecipeCard] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Рецепт или текст", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if let first = results.first, !text.isEmpty {
                        add(first.id, nil)
                    } else if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                        add(nil, text)
                    }
                }
            List(results) { card in
                Button {
                    add(card.id, nil)
                } label: {
                    HStack {
                        Text(card.title)
                            .lineLimit(1)
                        Spacer()
                        MissingLabel(count: card.missingCount)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Записать текстом: «\(text.trimmingCharacters(in: .whitespaces))»") { add(nil, text) }
            }
        }
        .padding(12)
        .frame(width: 340, height: 380)
        .task(id: text) {
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            var query = RecipeQuery(text: text, sort: [SortTerm(text.isEmpty ? .title : .relevance)])
            if text.isEmpty {
                query.mealTypeIDs = [meal.id]
            }
            var found = (try? database.recipeCards(query, limit: 40).rows) ?? []
            if found.isEmpty, text.isEmpty {
                found = (try? database.recipeCards(RecipeQuery(), limit: 40).rows) ?? []
            }
            results = found
        }
    }
}

/// «Приготовлено»: what the dish takes from the pantry, to correct before it is taken.
struct CookedSheet: View {
    let title: String
    let use: [CookingUse]
    let confirm: ([Product.ID: Double]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amounts: [Product.ID: Double?] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Приготовлено: \(title)")
                .font(.title2.bold())
                .padding([.horizontal, .top], 20)
            Text(
                use.isEmpty
                    ? "Из запасов списывать нечего: у продуктов рецепта не ведётся количество."
                    : "Из запасов спишется вот что; количества можно поправить. Отменить можно и потом."
            )
            .foregroundStyle(Color(.textSecondary))
            .padding(.horizontal, 20)
            .padding(.top, 4)
            List(use) { item in
                HStack(spacing: 10) {
                    Text(item.product.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let atHome = item.atHome {
                        Text("дома \(Formatting.quantity(atHome, item.product.baseUnit.unit))")
                            .foregroundStyle(Color(.textSecondary))
                    }
                    TextField(
                        "0", value: Binding(get: { amounts[item.id] ?? item.amount }, set: { amounts[item.id] = $0 }),
                        format: Formatting.decimal
                    )
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                    Text(item.product.baseUnit.unit.symbol)
                        .foregroundStyle(Color(.textSecondary))
                        .frame(width: 30, alignment: .leading)
                }
            }
            .frame(minHeight: 160)
            HStack {
                Spacer()
                Button("Отмена", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(use.isEmpty ? "Отметить" : "Списать") {
                    var taken: [Product.ID: Double] = [:]
                    for item in use {
                        let amount = amounts[item.id] ?? item.amount
                        if let amount, amount > 0 { taken[item.id] = amount }
                    }
                    confirm(taken)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 480, height: use.isEmpty ? 220 : 420)
    }
}
