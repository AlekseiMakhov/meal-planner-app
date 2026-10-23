import MealCore
import SwiftUI

/// The product list's filters: «Фильтр» adds one, each active filter is a chip.
struct ProductFilterBar: View {
    @Binding var query: ProductQuery
    let aisles: [Aisle]

    /// The calories chip shows while its range is being typed, before it has a value.
    @State private var editingCalories = false

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Menu("Отдел") { aisleToggles }
                Menu("Обычно есть дома") { stapleChoices }
                Menu("КБЖУ") { nutritionChoices }
                Button("Калорийность…") { editingCalories = true }
                Menu("Источник КБЖУ") { sourceToggles }
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
    }

    @ViewBuilder private var chips: some View {
        if !query.aisleIDs.isEmpty {
            FilterChip(title: "Отдел", value: summary(aisles.filter { query.aisleIDs.contains($0.id) }.map(\.name))) {
                query.aisleIDs = []
            } options: {
                aisleToggles
            }
        }
        if let isStaple = query.isStaple {
            FilterChip(title: "Обычно есть дома", value: isStaple ? "только они" : "кроме них") {
                query.isStaple = nil
            } options: {
                stapleChoices
            }
        }
        if let nutrition = query.nutrition {
            FilterChip(title: "КБЖУ", value: nutrition.title) {
                query.nutrition = nil
            } options: {
                nutritionChoices
            }
        }
        if editingCalories || query.kcalMin != nil || query.kcalMax != nil {
            CaloriesChip(min: $query.kcalMin, max: $query.kcalMax, isEditing: $editingCalories)
        }
        if !query.sources.isEmpty {
            FilterChip(
                title: "Источник",
                value: summary(NutritionSource.allCases.filter(query.sources.contains).map(\.title))
            ) {
                query.sources = []
            } options: {
                sourceToggles
            }
        }
    }

    @ViewBuilder private var aisleToggles: some View {
        ForEach(aisles) { aisle in
            Toggle(aisle.name, isOn: membership(of: aisle.id, in: \.aisleIDs))
        }
    }

    @ViewBuilder private var stapleChoices: some View {
        Picker("Обычно есть дома", selection: $query.isStaple) {
            Text("Только они").tag(Bool?.some(true))
            Text("Кроме них").tag(Bool?.some(false))
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    @ViewBuilder private var nutritionChoices: some View {
        Picker("КБЖУ", selection: $query.nutrition) {
            ForEach(ProductQuery.NutritionState.allCases, id: \.self) { state in
                Text(state.title).tag(Optional(state))
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    @ViewBuilder private var sourceToggles: some View {
        ForEach(NutritionSource.allCases, id: \.self) { source in
            Toggle(source.title, isOn: membership(of: source, in: \.sources))
        }
    }

    private func membership<Element: Hashable>(
        of element: Element, in set: WritableKeyPath<ProductQuery, Set<Element>>
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

    /// «Молочное», «Молочное +2».
    private func summary(_ names: [String]) -> String {
        guard let first = names.first else { return "" }
        return names.count == 1 ? first : "\(first) +\(names.count - 1)"
    }
}

extension ProductQuery.NutritionState {
    var title: String {
        switch self {
        case .missing: "не заполнено"
        case .needsReview: "нужно проверить"
        case .complete: "заполнено"
        }
    }
}

/// «Ккал: 100–300»; opens a popover with the range.
private struct CaloriesChip: View {
    @Binding var min: Double?
    @Binding var max: Double?
    @Binding var isEditing: Bool

    var body: some View {
        HStack(spacing: 2) {
            Button {
                isEditing = true
            } label: {
                Text("\(Text("Ккал:").foregroundStyle(Color(.textSecondary))) \(value)")
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .popover(isPresented: $isEditing, arrowEdge: .bottom) {
                Form {
                    TextField("От", value: $min, format: Formatting.decimal, prompt: Text("0"))
                    TextField("До", value: $max, format: Formatting.decimal, prompt: Text("900"))
                }
                .formStyle(.grouped)
                .frame(width: 220)
                .fixedSize(horizontal: false, vertical: true)
            }
            Button("Убрать фильтр «Ккал»", systemImage: "xmark") {
                min = nil
                max = nil
                isEditing = false
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .imageScale(.small)
            .foregroundStyle(Color(.textSecondary))
        }
        .chipBackground()
    }

    private var value: String {
        switch (min, max) {
        case (let min?, let max?): "\(Formatting.number(min, digits: 0))–\(Formatting.number(max, digits: 0))"
        case (let min?, nil): "от \(Formatting.number(min, digits: 0))"
        case (nil, let max?): "до \(Formatting.number(max, digits: 0))"
        case (nil, nil): "любая"
        }
    }
}
