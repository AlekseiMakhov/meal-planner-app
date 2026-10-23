import MealCore
import MealStore
import SwiftUI

/// Recipe cards grouped by category, as in Notion: a group's header folds it away. Groups appear as their
/// cards load, so a long gallery loads block by block like any list.
struct RecipeGallery: View {
    let list: PagedList<RecipeGalleryQuery, GalleryItem>
    let groups: [RecipeGroup]
    let categories: [RecipeCategory]
    @Binding var collapsed: Set<RecipeCategory.ID?>
    let images: ImageStore
    let open: (Recipe.ID) -> Void

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)]

    var body: some View {
        let items = Dictionary(grouping: list.rows, by: \.categoryID)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(visibleGroups, id: \.categoryID) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        header(group)
                        if !collapsed.contains(group.categoryID) {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(items[group.categoryID] ?? []) { item in
                                    Button {
                                        open(item.card.id)
                                    } label: {
                                        RecipeCardView(card: item.card, images: images)
                                    }
                                    .buttonStyle(.plain)
                                    .onAppear { list.rowAppeared(item.id) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    /// The groups up to the last card loaded; the rest show up as the list reaches them.
    private var visibleGroups: [RecipeGroup] {
        guard !list.isComplete, let last = list.rows.last,
            let index = groups.firstIndex(where: { $0.categoryID == last.categoryID })
        else { return list.isLoaded ? groups : [] }
        return Array(groups.prefix(index + 1))
    }

    private func header(_ group: RecipeGroup) -> some View {
        let category = categories.first { $0.id == group.categoryID }
        let isCollapsed = collapsed.contains(group.categoryID)
        return Button {
            if isCollapsed {
                collapsed.remove(group.categoryID)
            } else {
                collapsed.insert(group.categoryID)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .foregroundStyle(Color(.textSecondary))
                    .imageScale(.small)
                TagView(name: category?.name ?? "Без категории", color: category?.color ?? .gray)
                Text("\(group.count)")
                    .foregroundStyle(Color(.textSecondary))
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? "Развернуть" : "Свернуть")
    }
}

/// A recipe as a gallery card: photo, title, calories per 100 g and per serving.
struct RecipeCardView: View {
    let card: RecipeCard
    let images: ImageStore

    @State private var image: NSImage?
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color(.surfaceRaised)
                .frame(height: 140)
                .overlay {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "fork.knife")
                            .font(.title)
                            .foregroundStyle(Color(.textSecondary).opacity(0.5))
                    }
                }
                .clipped()
                .overlay(alignment: .topTrailing) { badges }
            VStack(alignment: .leading, spacing: 6) {
                Text(card.title)
                    .font(.headline)
                    .foregroundStyle(Color(.textPrimary))
                    .lineLimit(2, reservesSpace: true)
                Text(nutrition)
                    .font(.callout)
                    .foregroundStyle(Color(.textSecondary))
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.card))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).strokeBorder(
                isHovered ? Color(.textSecondary).opacity(0.4) : Color(.hairline))
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovered = $0 }
        .task(id: card.photo) {
            guard let photo = card.photo else {
                image = nil
                return
            }
            image = await Thumbnails.shared.image(at: images.url(for: photo), pixels: 640)
        }
    }

    @ViewBuilder private var badges: some View {
        HStack(spacing: 6) {
            if card.hasVideo {
                Image(systemName: "play.fill")
            }
            if card.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .font(.caption)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.black.opacity(card.hasVideo || card.isFavorite ? 0.45 : 0), in: Capsule())
        .padding(8)
    }

    /// «140 ккал/100 г · порция 280 ккал», with «≈» when not every ingredient counted.
    private var nutrition: String {
        let approximate = card.isNutritionComplete ? "" : "≈ "
        let per100 = card.kcalPer100.map { "\(approximate)\(Formatting.number($0, digits: 0)) ккал/100 г" }
        let serving = card.perServing.map { "порция \(approximate)\(Formatting.number($0.kcal, digits: 0)) ккал" }
        let parts = [per100, serving].compactMap { $0 }
        return parts.isEmpty ? "КБЖУ не посчитано" : parts.joined(separator: " · ")
    }
}

/// The recipes as a table of nutrition per serving, sortable by any column.
struct RecipeTable: View {
    let list: PagedList<RecipeQuery, RecipeCard>
    let categories: [RecipeCategory]
    @Binding var sortOrder: [RecipeOrder]
    let open: (Recipe.ID) -> Void

    @State private var selection: Set<Recipe.ID> = []

    var body: some View {
        Table(list.rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Название", sortUsing: RecipeOrder(.title)) { card in
                HStack(spacing: 6) {
                    Text(card.title)
                        .lineLimit(1)
                    if card.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .imageScale(.small)
                    }
                }
                .onAppear { list.rowAppeared(card.id) }
            }
            .width(min: 180, ideal: 260)
            TableColumn("Категории") { card in
                Text(
                    card.categoryIDs.compactMap { id in categories.first { $0.id == id }?.name }.joined(separator: ", ")
                )
                .foregroundStyle(Color(.textSecondary))
                .lineLimit(1)
            }
            .width(min: 90, ideal: 150)
            TableColumn("Ккал/100 г", sortUsing: RecipeOrder(.kcalPer100)) { card in
                NumberCell(value: card.kcalPer100, digits: 0, isApproximate: !card.isNutritionComplete)
            }
            .width(78)
            TableColumn("Ккал/порция", sortUsing: RecipeOrder(.kcalPerServing)) { card in
                NumberCell(value: card.perServing?.kcal, digits: 0, isApproximate: !card.isNutritionComplete)
            }
            .width(86)
            TableColumn("Б", sortUsing: RecipeOrder(.protein)) { card in
                NumberCell(value: card.perServing?.protein)
            }
            .width(44)
            TableColumn("Ж", sortUsing: RecipeOrder(.fat)) { card in
                NumberCell(value: card.perServing?.fat)
            }
            .width(44)
            TableColumn("У", sortUsing: RecipeOrder(.carbs)) { card in
                NumberCell(value: card.perServing?.carbs)
            }
            .width(44)
            TableColumn("Время", sortUsing: RecipeOrder(.totalTime)) { card in
                Text(Formatting.minutes(card.totalMinutes))
                    .foregroundStyle(Color(.textSecondary))
            }
            .width(70)
            TableColumn("Порции") { card in
                Text("\(card.servings)")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(54)
        }
        .contextMenu(forSelectionType: Recipe.ID.self) { _ in
        } primaryAction: { ids in
            if let id = ids.first { open(id) }
        }
    }
}
