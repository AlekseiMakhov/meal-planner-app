import MealCore
import MealStore
import SwiftUI

/// The ingredient lines as fields, and a line to add more: «40 г феты» finds «Фета» and fills the amount.
struct IngredientsEditor: View {
    let database: AppDatabase
    @Binding var details: RecipeDetails

    @State private var replacing: RecipeIngredient.ID?

    var body: some View {
        EditorSection("Ингредиенты \(Formatting.servings(details.recipe.servings))") {
            ForEach($details.ingredients) { $ingredient in
                row($ingredient)
                    .draggable(ingredient.id.uuidString)
                    .dropDestination(for: String.self) { items, _ in move(items.first, before: ingredient.id) }
                    .popover(
                        isPresented: Binding(
                            get: { replacing == ingredient.id }, set: { if !$0 { replacing = nil } }),
                        arrowEdge: .bottom
                    ) {
                        ProductPicker(database: database, prompt: "Другой продукт…") { product in
                            details.products[product.id] = product
                            ingredient.productID = product.id
                            replacing = nil
                        }
                    }
            }
            IngredientInput(database: database) { ingredient, product in
                details.products[product.id] = product
                withAnimation(Motion.layout) { details.ingredients.append(ingredient) }
            }
        }
    }

    private func row(_ ingredient: Binding<RecipeIngredient>) -> some View {
        let line = ingredient.wrappedValue
        return HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(Color(.textSecondary))
                .help("Перетащите, чтобы переставить")
            Button(details.products[line.productID]?.name ?? "Продукт удалён") { replacing = line.id }
                .buttonStyle(.plain)
                .frame(minWidth: 150, alignment: .leading)
                .help("Выбрать другой продукт")
            TextField("Кол-во", value: ingredient.amount, format: Formatting.decimal)
                .frame(width: 64)
            TextField("до", value: ingredient.amountMax, format: Formatting.decimal)
                .frame(width: 48)
                .help("Верхняя граница: «2–3 зубчика»")
            Picker("Единица", selection: ingredient.unit) {
                Text("—").tag(MeasureUnit?.none)
                ForEach(MeasureUnit.allCases, id: \.self) { unit in
                    Text(unit.symbol).tag(Optional(unit))
                }
            }
            .labelsHidden()
            .frame(width: 104)
            TextField(
                "Примечание",
                text: Binding(get: { line.note ?? "" }, set: { ingredient.wrappedValue.note = $0.isEmpty ? nil : $0 }))
            Toggle("по желанию", isOn: ingredient.isOptional)
                .toggleStyle(.checkbox)
                .fixedSize()
            Button("Убрать ингредиент", systemImage: "minus.circle") {
                withAnimation(Motion.layout) { details.ingredients.removeAll { $0.id == line.id } }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
    }

    /// Moves the dragged line to where the target is.
    private func move(_ dragged: String?, before target: RecipeIngredient.ID) {
        guard let dragged, let id = UUID(uuidString: dragged), id != target,
            let from = details.ingredients.firstIndex(where: { $0.id == id }),
            let to = details.ingredients.firstIndex(where: { $0.id == target })
        else { return }
        withAnimation(Motion.layout) {
            details.ingredients.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
        }
    }
}

/// One line to type an ingredient as a recipe writes it. Suggestions come from the product base; ↑ and ↓
/// pick one, Return takes it, and when none fits, the last row creates a product.
struct IngredientInput: View {
    let database: AppDatabase
    let onAdd: (RecipeIngredient, Product) -> Void

    @State private var text = ""
    @State private var suggestions: [Product] = []
    /// The name the suggestions are for: Return can come before they catch up with the typing.
    @State private var suggested: String?
    @State private var highlighted = 0
    @State private var creating: NewProductName?

    private var parsed: ParsedIngredient? {
        IngredientParser.parse(text).first
    }

    /// The product name to offer for a new product: as typed, with a capital letter.
    private var newName: String {
        guard let name = parsed?.name else { return "" }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Добавить ингредиент: «40 г феты», «2–3 зубчика чеснока», «соль по вкусу»", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)
                .onKeyPress(.downArrow) {
                    highlighted = min(highlighted + 1, suggestions.count)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    highlighted = max(highlighted - 1, 0)
                    return .handled
                }
                .onKeyPress(.escape) {
                    text = ""
                    return .handled
                }
            if let parsed, !text.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, product in
                        option(
                            "\(product.name)\(amountPreview(parsed))", systemImage: "carrot",
                            isHighlighted: index == highlighted
                        ) {
                            add(product)
                        }
                    }
                    option(
                        "Создать продукт «\(newName)»", systemImage: "plus.circle",
                        isHighlighted: highlighted == suggestions.count
                    ) {
                        creating = NewProductName(name: newName)
                    }
                }
                .padding(4)
                .background(Color(.surfaceRaised), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.hairline)))
            }
        }
        .task(id: parsed?.name) {
            guard let name = parsed?.name else {
                suggestions = []
                suggested = nil
                return
            }
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            suggestions = (try? suggestionsFor(name)) ?? []
            suggested = name
            highlighted = 0
        }
        .sheet(item: $creating) { new in
            NewProductSheet(database: database, suggestedName: new.name) { product in add(product) }
        }
    }

    /// The product with exactly this name or alias first, then the closest matches.
    private func suggestionsFor(_ name: String) throws -> [Product] {
        let exact = try database.product(named: name)
        let found = try database.products(ProductQuery(text: name, sort: [SortTerm(.relevance)]), limit: 6).rows
        return Array(([exact].compactMap { $0 } + found.filter { $0.id != exact?.id }).prefix(6))
    }

    private func option(
        _ title: String, systemImage: String, isHighlighted: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    isHighlighted ? Color.accentColor.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// « — 40 г» after a suggestion: what the line will add.
    private func amountPreview(_ parsed: ParsedIngredient) -> String {
        let amount = Formatting.amount(
            RecipeIngredient(productID: 0, amount: parsed.amount, amountMax: parsed.amountMax, unit: parsed.unit))
        let text = [amount.amount, amount.unit].filter { !$0.isEmpty }.joined(separator: " ")
        return text.isEmpty ? "" : " — \(text)"
    }

    private func commit() {
        guard let name = parsed?.name else { return }
        if suggested != name {
            suggestions = (try? suggestionsFor(name)) ?? []
            suggested = name
            highlighted = 0
        }
        if highlighted < suggestions.count {
            add(suggestions[highlighted])
        } else {
            creating = NewProductName(name: newName)
        }
    }

    private func add(_ product: Product) {
        guard let parsed else { return }
        onAdd(
            RecipeIngredient(
                productID: product.id, amount: parsed.amount, amountMax: parsed.amountMax, unit: parsed.unit,
                note: parsed.note, isOptional: parsed.isOptional),
            product)
        text = ""
        suggestions = []
        suggested = nil
        highlighted = 0
    }
}

struct NewProductName: Identifiable {
    let id = UUID()
    let name: String
}

/// A product made from an ingredient line: the name as typed, to correct — «феты» should become «Фета».
struct NewProductSheet: View {
    let database: AppDatabase
    let onCreated: (Product) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var aisleID: Int64?
    @State private var aisles: [Aisle] = []
    @State private var problem: String?

    init(database: AppDatabase, suggestedName: String, onCreated: @escaping (Product) -> Void) {
        self.database = database
        self.onCreated = onCreated
        _name = State(initialValue: suggestedName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Новый продукт")
                .font(.title3.bold())
            Form {
                TextField("Название", text: $name)
                Picker("Отдел", selection: $aisleID) {
                    Text("Без отдела").tag(Int64?.none)
                    ForEach(aisles) { aisle in
                        Text(aisle.name).tag(Optional(aisle.id))
                    }
                }
            }
            .formStyle(.grouped)
            Text("Проверьте название: в рецепте оно бывает в другом падеже. КБЖУ можно заполнить потом в «Продуктах».")
                .font(.callout)
                .foregroundStyle(Color(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Отмена", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Создать", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .task { aisles = (try? database.aisles()) ?? [] }
    }

    /// Takes the product already called so, if there is one; otherwise creates it.
    private func create() {
        do {
            if let existing = try database.product(named: name) {
                onCreated(existing)
            } else {
                onCreated(try database.newProduct(named: name.trimmingCharacters(in: .whitespaces), aisleID: aisleID))
            }
            dismiss()
        } catch {
            problem = String(describing: error)
        }
    }
}
