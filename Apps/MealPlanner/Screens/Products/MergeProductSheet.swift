import MealCore
import MealStore
import SwiftUI

/// Picks the product a duplicate folds into: «Яйца» into «Яйцо куриное».
struct MergeProductSheet: View {
    let database: AppDatabase
    let duplicate: Product
    let onMerged: (Product) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var list: PagedList<ProductQuery, Product>
    @State private var search: String
    @State private var target: Product.ID?
    @State private var problem: String?

    init(database: AppDatabase, duplicate: Product, onMerged: @escaping (Product) -> Void) {
        self.database = database
        self.duplicate = duplicate
        self.onMerged = onMerged
        // Starts from the duplicate's own name: the product it repeats is usually among the first results.
        let words = duplicate.name.split(separator: " ").prefix(1).joined()
        _search = State(initialValue: words)
        _list = State(
            initialValue: PagedList(query: ProductQuery(text: words, sort: [SortTerm(.relevance)])) { query, limit in
                database.observeProducts(query, limit: limit)
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Объединить «\(duplicate.name)» с…")
                .font(.title3.bold())
            Text(
                "«\(duplicate.name)» исчезнет, а его название и синонимы станут синонимами выбранного продукта. КБЖУ, вес штуки и единицы останутся у выбранного; то, чего у него нет, возьмётся из «\(duplicate.name)»."
            )
            .foregroundStyle(Color(.textSecondary))
            .fixedSize(horizontal: false, vertical: true)
            TextField("Поиск", text: $search, prompt: Text("Название или синоним"))
                .textFieldStyle(.roundedBorder)
            List(list.rows.filter { $0.id != duplicate.id }, selection: $target) { product in
                Text(product.name)
                    .onAppear { list.rowAppeared(product.id) }
            }
            .frame(minHeight: 260)
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Отмена", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Объединить", action: merge)
                    .keyboardShortcut(.defaultAction)
                    .disabled(target == nil)
            }
        }
        .padding(20)
        .frame(width: 440)
        .task { list.start() }
        .onDisappear { list.stop() }
        .task(id: search) {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            list.query.text = search
        }
    }

    private func merge() {
        guard let target else { return }
        do {
            let kept = try database.mergeProduct(duplicate.id, into: target)
            onMerged(kept)
            dismiss()
        } catch {
            problem = String(describing: error)
        }
    }
}
