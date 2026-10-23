import MealCore
import SwiftUI

/// A line to type what to add, read as ingredient lines are: «яйца 10», «молоко 1 л», «соль». Return adds it.
struct QuickAddField: View {
    let prompt: String
    let onSubmit: (String) -> Void

    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .foregroundStyle(Color(.textSecondary))
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .onSubmit {
                    let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !line.isEmpty else { return }
                    onSubmit(line)
                    text = ""
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

/// An amount in a product's unit, typed or stepped: grams by 50, millilitres by 100, pieces by one. Empty means
/// «some, uncounted».
struct QuantityField: View {
    let value: Double?
    let unit: MeasureUnit
    let commit: (Double?) -> Void

    @State private var text: Double?

    private var step: Double {
        switch unit {
        case .gram: 50
        case .milliliter: 100
        default: 1
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField("сколько", value: $text, format: Formatting.decimal)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 64)
            Text(unit.symbol)
                .foregroundStyle(Color(.textSecondary))
                .frame(width: 30, alignment: .leading)
            Stepper("Изменить количество") {
                commit((value ?? 0) + step)
            } onDecrement: {
                commit(max((value ?? 0) - step, 0))
            }
            .labelsHidden()
        }
        .onAppear { text = value }
        .onChange(of: value) { text = value }
        .onChange(of: text) {
            if text != value { commit(text.map { max($0, 0) }) }
        }
    }
}

/// A coloured dot for what there is at home.
struct PantryDot: View {
    let status: PantryStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .help(status.title)
    }

    private var color: Color {
        switch status {
        case .inStock: Color(.statusInStock)
        case .low: Color(.statusLow)
        case .out: Color(.statusMissing)
        }
    }
}

/// Rows of a list sorted by aisle, under their aisles' names, in the order they came.
struct AisleSection<Row: Identifiable>: Identifiable {
    let id: Int64?
    let title: String
    var rows: [Row]

    static func group(_ rows: [Row], aisle: (Row) -> Int64?, names: [Int64: String], other: String = "Без отдела")
        -> [AisleSection]
    {
        var sections: [AisleSection] = []
        for row in rows {
            let id = aisle(row)
            if sections.last?.id == id, !sections.isEmpty {
                sections[sections.count - 1].rows.append(row)
            } else {
                sections.append(AisleSection(id: id, title: id.flatMap { names[$0] } ?? other, rows: [row]))
            }
        }
        return sections
    }
}
