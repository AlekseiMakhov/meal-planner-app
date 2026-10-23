import MealCore
import MealStore
import SwiftUI

/// «Ккал на порцию: 100–300»; opens a popover with the range. Shown while the range is being typed too.
struct RangeChip: View {
    let title: String
    @Binding var range: ValueRange
    @Binding var isEditing: Bool

    var body: some View {
        HStack(spacing: 2) {
            Button {
                isEditing = true
            } label: {
                Text("\(Text("\(title):").foregroundStyle(Color(.textSecondary))) \(value)")
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .popover(isPresented: $isEditing, arrowEdge: .bottom) {
                Form {
                    TextField("От", value: $range.min, format: Formatting.decimal, prompt: Text("любое"))
                    TextField("До", value: $range.max, format: Formatting.decimal, prompt: Text("любое"))
                }
                .formStyle(.grouped)
                .frame(width: 220)
                .fixedSize(horizontal: false, vertical: true)
            }
            Button("Убрать фильтр «\(title)»", systemImage: "xmark") {
                range = ValueRange()
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
        switch (range.min, range.max) {
        case (let min?, let max?): "\(Formatting.number(min, digits: 0))–\(Formatting.number(max, digits: 0))"
        case (let min?, nil): "от \(Formatting.number(min, digits: 0))"
        case (nil, let max?): "до \(Formatting.number(max, digits: 0))"
        case (nil, nil): "любое"
        }
    }
}

/// A searchable list of products to pick one from: for the recipe filters and for replacing an ingredient.
struct ProductPicker: View {
    let database: AppDatabase
    let prompt: String
    /// What the search starts with: the name typed into a quick-add line.
    var initialText = ""
    let onPick: (Product) -> Void

    @State private var text = ""
    @State private var results: [Product] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
            List(results) { product in
                Button(product.name) { onPick(product) }
                    .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .padding(12)
        .frame(width: 300, height: 340)
        .onAppear { text = initialText }
        .task(id: text) {
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            let sort = text.isEmpty ? [SortTerm<ProductQuery.SortKey>(.name)] : [SortTerm(.relevance)]
            results = (try? database.products(ProductQuery(text: text, sort: sort), limit: 40).rows) ?? []
        }
    }
}
