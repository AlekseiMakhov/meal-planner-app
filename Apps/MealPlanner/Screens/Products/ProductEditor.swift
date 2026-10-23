import MealCore
import MealStore
import SwiftUI

/// A product's properties in the inspector. Changes save themselves a moment after the last keystroke;
/// what cannot be saved — a taken name, a value out of range — is said under the form.
struct ProductEditor: View {
    let database: AppDatabase
    let productID: Product.ID
    let aisles: [Aisle]
    let onMerge: (Product) -> Void
    let onDelete: (Product) -> Void

    @State private var draft: Product?
    @State private var saved: Product?
    @State private var aliases = ""
    @State private var problem: String?
    @State private var recipeCount = 0
    @FocusState private var nameFocused: Bool

    var body: some View {
        Group {
            if let draft = Binding($draft) {
                form(draft)
            } else {
                ProgressView()
            }
        }
        .task {
            guard let product = try? database.product(id: productID) else { return }
            draft = product
            saved = product
            aliases = product.aliases.joined(separator: ", ")
            recipeCount = (try? database.recipeCount(of: productID)) ?? 0
            nameFocused = product.name.hasPrefix("Новый продукт")
        }
        .task(id: draft) {
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            save()
        }
        .onDisappear { save() }
    }

    private func form(_ product: Binding<Product>) -> some View {
        Form {
            Section("Продукт") {
                TextField("Название", text: product.name)
                    .focused($nameFocused)
                TextField("Синонимы", text: $aliases, prompt: Text("через запятую"), axis: .vertical)
                    .onChange(of: aliases) {
                        product.wrappedValue.aliases = aliases.split(separator: ",").map(String.init)
                    }
                Picker("Отдел", selection: product.aisleID) {
                    Text("Без отдела").tag(Int64?.none)
                    ForEach(aisles) { aisle in
                        Text(aisle.name).tag(Optional(aisle.id))
                    }
                }
                Toggle(isOn: product.isStaple) {
                    Text("Обычно есть дома")
                    Text("Соль, масло, специи: важно, есть ли, а не сколько граммов.")
                }
            }

            Section("КБЖУ на 100 г") {
                nutritionField("Калорийность, ккал", product, \.kcal)
                nutritionField("Белки, г", product, \.protein)
                nutritionField("Жиры, г", product, \.fat)
                nutritionField("Углеводы, г", product, \.carbs)
                if let nutrition = product.wrappedValue.nutrition, product.wrappedValue.nutritionSource != .usda,
                    !nutrition.caloriesMatchMacros
                {
                    Label(
                        "По белкам, жирам и углеводам выходит около \(Formatting.number(nutrition.kcalFromMacros, digits: 0)) ккал. Проверьте значения.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.yellow)
                }
                Picker("Источник", selection: product.nutritionSource) {
                    Text("Не указан").tag(NutritionSource?.none)
                    ForEach(NutritionSource.allCases, id: \.self) { source in
                        Text(source.title).tag(Optional(source))
                    }
                }
                if let note = product.wrappedValue.sourceNote {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(Color(.textSecondary))
                        .textSelection(.enabled)
                }
                Toggle("Нужно проверить", isOn: product.needsReview)
            }

            Section {
                Picker("Хранится в", selection: product.baseUnit) {
                    ForEach(BaseUnit.allCases, id: \.self) { unit in
                        Text(unit.unit.symbol).tag(unit)
                    }
                }
                TextField("Вес 1 шт., г", value: product.gramsPerPiece, format: Formatting.decimal)
                TextField("Плотность, г/мл", value: product.density, format: Formatting.decimal)
                ForEach(product.wrappedValue.namedUnits.keys.sorted(by: unitOrder), id: \.self) { unit in
                    namedUnitRow(unit, product)
                }
                addUnitMenu(product)
            } header: {
                Text("Единицы")
            } footer: {
                if let conversions = conversions(product.wrappedValue) {
                    Text(conversions)
                        .foregroundStyle(Color(.textSecondary))
                }
            }

            if let problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                LabeledContent(
                    "В рецептах",
                    value: recipeCount == 0
                        ? "нет" : Formatting.count(recipeCount, "рецепт", "рецепта", "рецептов"))
                Button("Объединить с другим продуктом…") { onMerge(product.wrappedValue) }
                Button("Удалить продукт…", role: .destructive) { onDelete(product.wrappedValue) }
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }

    /// A value typed by hand makes the nutrition the person's own: the source becomes «Вручную».
    private func nutritionField(
        _ title: String, _ product: Binding<Product>, _ keyPath: WritableKeyPath<Product, Double?>
    ) -> some View {
        TextField(
            title,
            value: Binding {
                product.wrappedValue[keyPath: keyPath]
            } set: { value in
                guard value != product.wrappedValue[keyPath: keyPath] else { return }
                product.wrappedValue[keyPath: keyPath] = value
                product.wrappedValue.nutritionSource = .manual
                product.wrappedValue.sourceNote = nil
            },
            format: Formatting.decimal)
    }

    private func namedUnitRow(_ unit: MeasureUnit, _ product: Binding<Product>) -> some View {
        HStack {
            TextField(
                "1 \(unit.title(for: 1)), г",
                value: Binding {
                    product.wrappedValue.namedUnits[unit] ?? 0
                } set: { grams in
                    product.wrappedValue.namedUnits[unit] = grams
                },
                format: Formatting.decimal)
            Button("Убрать единицу «\(unit.title(for: 1))»", systemImage: "minus.circle") {
                product.wrappedValue.namedUnits[unit] = nil
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
    }

    private func addUnitMenu(_ product: Binding<Product>) -> some View {
        Menu("Добавить единицу") {
            ForEach(MeasureUnit.named.filter { product.wrappedValue.namedUnits[$0] == nil }, id: \.self) { unit in
                Button(unit.title(for: 1)) { product.wrappedValue.namedUnits[unit] = 0 }
            }
        }
        .disabled(MeasureUnit.named.allSatisfy { product.wrappedValue.namedUnits[$0] != nil })
    }

    private func unitOrder(_ lhs: MeasureUnit, _ rhs: MeasureUnit) -> Bool {
        (MeasureUnit.named.firstIndex(of: lhs) ?? 0) < (MeasureUnit.named.firstIndex(of: rhs) ?? 0)
    }

    /// «1 ст. л. ≈ 8 г · 1 стакан ≈ 132 г · 1 шт. = 50 г»: what the numbers above mean in grams.
    private func conversions(_ product: Product) -> String? {
        let units = product.units
        var parts: [String] = []
        for unit in [MeasureUnit.tablespoon, .cup] {
            if let grams = units.grams(1, unit) {
                parts.append("1 \(unit.title(for: 1)) ≈ \(Formatting.number(grams, digits: 0)) г")
            }
        }
        if let grams = units.grams(1, .piece) {
            parts.append("1 шт. = \(Formatting.number(grams)) г")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func save() {
        guard let draft, draft != saved else { return }
        do {
            saved = try database.save(draft)
            problem = nil
        } catch {
            problem = String(describing: error)
        }
    }
}
