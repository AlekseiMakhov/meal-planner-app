import MealCore
import MealStore
import SwiftUI

/// The recipes' filters: category, meal, products in and out, nutrition per serving, time and the rest.
struct RecipeFilterBar: View {
    let database: AppDatabase
    @Binding var query: RecipeQuery
    let categories: [RecipeCategory]
    let mealTypes: [MealType]

    /// A range being typed shows as its chip before it has a value.
    @State private var editing: RangeField?
    /// The products a filter is being picked for.
    @State private var picking: ProductFilter?
    @State private var productNames: [Product.ID: String] = [:]

    enum RangeField: CaseIterable {
        case kcal, protein, fat, carbs

        var title: String {
            switch self {
            case .kcal: "Ккал на порцию"
            case .protein: "Белки на порцию, г"
            case .fat: "Жиры на порцию, г"
            case .carbs: "Углеводы на порцию, г"
            }
        }

        var keyPath: WritableKeyPath<RecipeQuery, ValueRange> {
            switch self {
            case .kcal: \.kcalPerServing
            case .protein: \.protein
            case .fat: \.fat
            case .carbs: \.carbs
            }
        }
    }

    enum ProductFilter: Identifiable {
        case with, without

        var id: Self {
            self
        }

        var keyPath: WritableKeyPath<RecipeQuery, Set<Product.ID>> {
            self == .with ? \.withProducts : \.withoutProducts
        }

        var title: String {
            self == .with ? "С продуктом" : "Без продукта"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Menu("Категория") { categoryToggles }
                Menu("Приём пищи") { mealToggles }
                Button("С продуктом…") { picking = .with }
                Button("Без продукта…") { picking = .without }
                Menu("КБЖУ на порцию") {
                    ForEach(RangeField.allCases, id: \.self) { field in
                        Button(field.title + "…") { editing = field }
                    }
                }
                Menu("Время") { timeChoices }
                Menu("Наличие") { availabilityChoices }
                Divider()
                Toggle("Избранное", isOn: flag(\.isFavorite))
                Toggle("С фото", isOn: flag(\.hasPhoto))
                Toggle("С видео", isOn: flag(\.hasVideo))
                Toggle("КБЖУ посчитано не полностью", isOn: flag(\.nutritionIncomplete))
            } label: {
                Label("Фильтр", systemImage: "line.3.horizontal.decrease")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .chipBackground()

            ScrollView(.horizontal) {
                HStack(spacing: 8) { chips }
            }
            .scrollIndicators(.never)

            if query.filterCount > 0 {
                Button("Сбросить") { query = query.withoutFilters }
                    .buttonStyle(.link)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(Motion.pop, value: query)
        .animation(Motion.pop, value: editing)
        .popover(item: $picking, arrowEdge: .bottom) { filter in
            ProductPicker(
                database: database, prompt: filter == .with ? "Рецепты с продуктом…" : "Рецепты без продукта…"
            ) {
                product in
                productNames[product.id] = product.name
                query[keyPath: filter.keyPath].insert(product.id)
                picking = nil
            }
        }
        .task(id: query.withProducts.union(query.withoutProducts)) {
            for id in query.withProducts.union(query.withoutProducts) where productNames[id] == nil {
                productNames[id] = (try? database.product(id: id))?.name
            }
        }
    }

    @ViewBuilder private var chips: some View {
        if !query.categoryIDs.isEmpty {
            FilterChip(
                title: "Категория", value: summary(categories.filter { query.categoryIDs.contains($0.id) }.map(\.name))
            ) {
                query.categoryIDs = []
            } options: {
                categoryToggles
            }
        }
        if !query.mealTypeIDs.isEmpty {
            FilterChip(
                title: "Приём пищи", value: summary(mealTypes.filter { query.mealTypeIDs.contains($0.id) }.map(\.name))
            ) {
                query.mealTypeIDs = []
            } options: {
                mealToggles
            }
        }
        ForEach([ProductFilter.with, .without]) { filter in
            let ids = query[keyPath: filter.keyPath]
            if !ids.isEmpty {
                FilterChip(title: filter.title, value: summary(ids.sorted().map { productNames[$0] ?? "…" })) {
                    query[keyPath: filter.keyPath] = []
                } options: {
                    ForEach(ids.sorted(), id: \.self) { id in
                        Toggle(productNames[id] ?? "…", isOn: membership(of: id, in: filter.keyPath))
                    }
                    Divider()
                    Button("Добавить продукт…") { picking = filter }
                }
            }
        }
        ForEach(RangeField.allCases, id: \.self) { field in
            if editing == field || !query[keyPath: field.keyPath].isEmpty {
                RangeChip(
                    title: field.title, range: $query[dynamicMember: field.keyPath],
                    isEditing: Binding(get: { editing == field }, set: { editing = $0 ? field : nil }))
            }
        }
        if let minutes = query.maxMinutes {
            FilterChip(title: "Время", value: "до \(Formatting.minutes(minutes))") {
                query.maxMinutes = nil
            } options: {
                timeChoices
            }
        }
        if let maxMissing = query.maxMissing {
            FilterChip(title: "Наличие", value: Self.availabilityTitle(maxMissing).lowercased()) {
                query.maxMissing = nil
            } options: {
                availabilityChoices
            }
        }
        flagChip("Избранное", \.isFavorite, yes: "да", no: "нет")
        flagChip("Фото", \.hasPhoto, yes: "есть", no: "нет")
        flagChip("Видео", \.hasVideo, yes: "есть", no: "нет")
        flagChip("КБЖУ", \.nutritionIncomplete, yes: "посчитано не полностью", no: "посчитано полностью")
    }

    @ViewBuilder private var categoryToggles: some View {
        ForEach(categories) { category in
            Toggle(category.name, isOn: membership(of: category.id, in: \.categoryIDs))
        }
    }

    @ViewBuilder private var mealToggles: some View {
        ForEach(mealTypes) { meal in
            Toggle(meal.name, isOn: membership(of: meal.id, in: \.mealTypeIDs))
        }
    }

    @ViewBuilder private var timeChoices: some View {
        Picker("Время", selection: $query.maxMinutes) {
            ForEach([15, 30, 45, 60, 90, 120], id: \.self) { minutes in
                Text("До \(Formatting.minutes(minutes))").tag(Int?.some(minutes))
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    @ViewBuilder private var availabilityChoices: some View {
        Picker("Наличие", selection: $query.maxMissing) {
            ForEach([0, 1, 2, 3], id: \.self) { count in
                Text(Self.availabilityTitle(count)).tag(Int?.some(count))
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    static func availabilityTitle(_ maxMissing: Int) -> String {
        maxMissing == 0 ? "Можно приготовить сейчас" : "Не хватает не больше \(maxMissing)"
    }

    @ViewBuilder private func flagChip(
        _ title: String, _ keyPath: WritableKeyPath<RecipeQuery, Bool?>, yes: String, no: String
    ) -> some View {
        if let value = query[keyPath: keyPath] {
            FilterChip(title: title, value: value ? yes : no) {
                query[keyPath: keyPath] = nil
            } options: {
                Picker(title, selection: $query[dynamicMember: keyPath]) {
                    Text(yes.prefix(1).uppercased() + yes.dropFirst()).tag(Bool?.some(true))
                    Text(no.prefix(1).uppercased() + no.dropFirst()).tag(Bool?.some(false))
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
    }

    /// On means «only these»: «Избранное» shows favourites; the chip can turn it into «not favourites».
    private func flag(_ keyPath: WritableKeyPath<RecipeQuery, Bool?>) -> Binding<Bool> {
        Binding {
            query[keyPath: keyPath] == true
        } set: {
            query[keyPath: keyPath] = $0 ? true : nil
        }
    }

    private func membership<Element: Hashable>(
        of element: Element, in set: WritableKeyPath<RecipeQuery, Set<Element>>
    ) -> Binding<Bool> {
        Binding {
            query[keyPath: set].contains(element)
        } set: { isOn in
            if isOn {
                query[keyPath: set].insert(element)
            } else {
                query[keyPath: set].remove(element)
            }
        }
    }
}
