import Foundation
import GRDB
import MealCore

extension AppDatabase {
    // MARK: - Reading the menu

    public func weekPlan(starting start: Day) throws -> WeekPlan {
        try reader.read { db in try Self.fetchWeekPlan(db, start) }
    }

    /// The week kept current: its dishes, their recipes and what there is of their products at home.
    public func observeWeekPlan(starting start: Day) -> AsyncValueObservation<WeekPlan> {
        ValueObservation.tracking { db in try Self.fetchWeekPlan(db, start) }
            .removeDuplicates().values(in: reader)
    }

    static func fetchWeekPlan(_ db: Database, _ start: Day) throws -> WeekPlan {
        let end = start.adding(days: 6)
        let entries = try SQLRequest<PlanEntryRecord>(
            literal: """
                SELECT plan_entry.* FROM plan_entry JOIN meal_type ON meal_type.id = plan_entry.mealTypeId
                WHERE plan_entry.day BETWEEN \(start.description) AND \(end.description)
                ORDER BY plan_entry.day, meal_type.position, meal_type.id, plan_entry.position, plan_entry.id
                """
        ).fetchAll(db).map(\.entry)
        var recipes: [Recipe.ID: RecipeDetails] = [:]
        for id in Set(entries.compactMap(\.recipeID)) {
            recipes[id] = try RecipeDerived.details(db, id: id)
        }
        let products = Set(recipes.values.flatMap { $0.ingredients.map(\.productID) })
        return WeekPlan(
            start: start,
            mealTypes: try MealTypeRecord.order(Column("position"), Column("id")).fetchAll(db).map(\.mealType),
            entries: entries, recipes: recipes, pantry: try fetchPantryItems(db, products))
    }

    public func planEntry(id: PlanEntry.ID) throws -> PlanEntry? {
        try reader.read { db in try PlanEntryRecord.fetchOne(db, key: id)?.entry }
    }

    // MARK: - Changing the menu

    /// Puts a dish at the end of a day's meal: a recipe — for its own servings unless asked — or text.
    @discardableResult
    public func planMeal(
        on day: Day, meal mealTypeID: MealType.ID, recipe recipeID: Recipe.ID? = nil, text: String? = nil,
        servings: Int? = nil
    ) throws -> PlanEntry {
        let text = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard recipeID != nil || !(text ?? "").isEmpty else { throw StoreError("Нужен рецепт или текст.") }
        if let servings, !(1...100).contains(servings) { throw StoreError("Порций — от 1 до 100.") }
        return try writer.write { db in
            guard try MealTypeRecord.exists(db, key: mealTypeID) else { throw StoreError("Такого приёма пищи нет.") }
            var defaultServings = Recipe.defaultServings
            if let recipeID {
                guard let recipe = try RecipeRecord.fetchOne(db, key: recipeID) else {
                    throw StoreError("Рецепта больше нет.")
                }
                defaultServings = recipe.servings
            }
            var record = PlanEntryRecord(
                PlanEntry(
                    id: 0, day: day, mealTypeID: mealTypeID, recipeID: recipeID, text: recipeID == nil ? text : nil,
                    servings: servings ?? defaultServings, position: try Self.nextPosition(day, mealTypeID, db)),
                id: nil)
            try record.insert(db)
            return record.entry
        }
    }

    /// Moves a dish to a day and meal, before `other` or to the end.
    public func movePlanEntry(
        _ id: PlanEntry.ID, to day: Day, meal mealTypeID: MealType.ID, before other: PlanEntry.ID? = nil
    ) throws {
        try writer.write { db in
            guard var record = try PlanEntryRecord.fetchOne(db, key: id) else { throw StoreError("Блюда больше нет.") }
            guard try MealTypeRecord.exists(db, key: mealTypeID) else { throw StoreError("Такого приёма пищи нет.") }
            record.day = day.description
            record.mealTypeId = mealTypeID
            try record.update(db)
            try Self.place(id, before: other, day, mealTypeID, db)
        }
    }

    /// A copy of a dish on another day or meal: what ⌥ does while dragging, and «Повторить».
    @discardableResult
    public func copyPlanEntry(_ id: PlanEntry.ID, to day: Day, meal mealTypeID: MealType.ID) throws -> PlanEntry {
        try writer.write { db in
            guard let original = try PlanEntryRecord.fetchOne(db, key: id)?.entry else {
                throw StoreError("Блюда больше нет.")
            }
            var copy = original
            copy.day = day
            copy.mealTypeID = mealTypeID
            copy.cookedAt = nil
            copy.used = [:]
            copy.position = try Self.nextPosition(day, mealTypeID, db)
            var record = PlanEntryRecord(copy, id: nil)
            try record.insert(db)
            return record.entry
        }
    }

    public func setPlanServings(_ servings: Int, entry id: PlanEntry.ID) throws {
        guard (1...100).contains(servings) else { throw StoreError("Порций — от 1 до 100.") }
        try writer.write { db in
            try db.execute(sql: "UPDATE plan_entry SET servings = ? WHERE id = ?", arguments: [servings, id])
        }
    }

    public func setPlanText(_ text: String, entry id: PlanEntry.ID) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw StoreError("Нужен текст.") }
        try writer.write { db in
            try db.execute(
                sql: "UPDATE plan_entry SET text = ? WHERE id = ? AND recipeId IS NULL", arguments: [text, id])
        }
    }

    /// Takes dishes off the menu; what a cooked one took from the pantry stays taken.
    public func removePlanEntries(_ ids: Set<PlanEntry.ID>) throws {
        try writer.write { db in
            let recipes = try SQLRequest<Int64>(
                literal: "SELECT DISTINCT recipeId FROM plan_entry WHERE recipeId IS NOT NULL AND id IN \(Array(ids))"
            ).fetchAll(db)
            _ = try PlanEntryRecord.deleteAll(db, keys: ids)
            try RecipeDerived.refresh(db, recipeIDs: recipes)
        }
    }

    /// The dishes of one week on the same weekdays and meals of another, as they were planned, not as cooked.
    @discardableResult
    public func copyWeek(from source: Day, to target: Day) throws -> Int {
        let source = source.weekStart
        let target = target.weekStart
        return try writer.write { db in
            let entries = try Self.fetchWeekPlan(db, source).entries
            for entry in entries {
                let offset = Calendar.current.dateComponents([.day], from: source.date(), to: entry.day.date()).day ?? 0
                let day = target.adding(days: offset)
                var copy = entry
                copy.day = day
                copy.cookedAt = nil
                copy.used = [:]
                copy.position = try Self.nextPosition(day, entry.mealTypeID, db)
                var record = PlanEntryRecord(copy, id: nil)
                try record.insert(db)
            }
            return entries.count
        }
    }

    // MARK: - Cooking

    /// What «Приготовлено» would take from the pantry for the dish: the dialog shows it to correct.
    public func cookingUse(of id: PlanEntry.ID) throws -> [CookingUse] {
        try reader.read { db in
            guard let entry = try PlanEntryRecord.fetchOne(db, key: id)?.entry, let recipeID = entry.recipeID,
                let details = try RecipeDerived.details(db, id: recipeID)
            else { return [] }
            let pantry = try Self.fetchPantryItems(db, Set(details.ingredients.map(\.productID)))
            return details.cookingUse(servings: entry.servings, pantry: pantry)
        }
    }

    /// Marks the dish cooked and takes `amounts` — in the products' base units — out of the pantry.
    public func markCooked(_ id: PlanEntry.ID, using amounts: [Product.ID: Double]) throws {
        try writer.write { db in
            guard var record = try PlanEntryRecord.fetchOne(db, key: id) else { throw StoreError("Блюда больше нет.") }
            guard record.cookedAt == nil else { throw StoreError("Блюдо уже отмечено приготовленным.") }
            let used = amounts.filter { $0.value > 0 }
            try Self.takeFromPantry(used, db)
            record.cookedAt = .now
            record.used = Dictionary(uniqueKeysWithValues: used.map { (String($0.key), $0.value) })
            try record.update(db)
            if let recipeID = record.recipeId {
                try RecipeDerived.refresh(db, recipeIDs: [recipeID])
            }
        }
    }

    /// Takes «Приготовлено» back: the dish is planned again and what it took returns to the pantry.
    public func undoCooked(_ id: PlanEntry.ID) throws {
        try writer.write { db in
            guard var record = try PlanEntryRecord.fetchOne(db, key: id), record.cookedAt != nil else { return }
            let used = record.entry.used
            for (productID, amount) in used {
                guard var item = try PantryItemRecord.fetchOne(db, key: productID)?.item else { continue }
                item.quantity = item.quantity.map { $0 + amount }
                item.updatedAt = .now
                try PantryItemRecord(item).update(db)
            }
            try RecipeDerived.refresh(db, recipeIDs: RecipeDerived.recipes(using: Array(used.keys), db))
            record.cookedAt = nil
            record.used = [:]
            try record.update(db)
            if let recipeID = record.recipeId {
                try RecipeDerived.refresh(db, recipeIDs: [recipeID])
            }
        }
    }

    /// «Покупки на неделю»: what the pantry, spread over the week's dishes from `today` on, does not cover, put on
    /// the list with each dish and its day as the reason.
    @discardableResult
    public func addMenuShortages(week start: Day, from today: Day = .today()) throws -> [ShoppingItem.ID] {
        try writer.write { db in
            let plan = try Self.fetchWeekPlan(db, start.weekStart)
            return try Self.addToShopping(plan.supply(from: today).shortages, db)
        }
    }

    // MARK: - Meals

    /// A meal of one's own after the others: «Второй завтрак».
    @discardableResult
    public func newMealType(named name: String) throws -> MealType {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw StoreError("Нужно название.") }
        return try writer.write { db in
            try Self.checkMealName(name, except: nil, db)
            let position = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position) + 1, 0) FROM meal_type") ?? 0
            try db.execute(
                sql: "INSERT INTO meal_type (name, color, position) VALUES (?, ?, ?)",
                arguments: [name, TagColor.purple.rawValue, position])
            return MealType(id: db.lastInsertedRowID, name: name, color: .purple, position: position)
        }
    }

    /// Renames or recolours a meal; its place stays.
    @discardableResult
    public func save(_ mealType: MealType) throws -> MealType {
        let name = mealType.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw StoreError("Нужно название.") }
        return try writer.write { db in
            try Self.checkMealName(name, except: mealType.id, db)
            try db.execute(
                sql: "UPDATE meal_type SET name = ?, color = ? WHERE id = ?",
                arguments: [name, mealType.color.rawValue, mealType.id])
            guard let saved = try MealTypeRecord.fetchOne(db, key: mealType.id)?.mealType else {
                throw StoreError("Такого приёма пищи больше нет.")
            }
            return saved
        }
    }

    /// Deletes a meal with the dishes planned for it; recipes no longer suit it.
    public func deleteMealType(id: MealType.ID) throws {
        try writer.write { db in
            guard try MealTypeRecord.fetchCount(db) > 1 else { throw StoreError("Хотя бы один приём пищи нужен.") }
            _ = try MealTypeRecord.deleteOne(db, key: id)
        }
    }

    public func reorderMealTypes(_ ids: [MealType.ID]) throws {
        try writer.write { db in
            for (position, id) in ids.enumerated() {
                try db.execute(sql: "UPDATE meal_type SET position = ? WHERE id = ?", arguments: [position, id])
            }
        }
    }

    // MARK: - Helpers

    private static func checkMealName(_ name: String, except id: MealType.ID?, _ db: Database) throws {
        let taken = try MealTypeRecord.fetchAll(db).first {
            $0.id != id && SearchText.normalized($0.name) == SearchText.normalized(name)
        }
        if let taken {
            throw StoreError("Приём пищи «\(taken.name)» уже есть.")
        }
    }

    private static func nextPosition(_ day: Day, _ mealTypeID: MealType.ID, _ db: Database) throws -> Int {
        try Int.fetchOne(
            db, sql: "SELECT COALESCE(MAX(position) + 1, 0) FROM plan_entry WHERE day = ? AND mealTypeId = ?",
            arguments: [day.description, mealTypeID]) ?? 0
    }

    /// Puts the dish before `other` in its cell, or last, and numbers the cell again.
    private static func place(
        _ id: PlanEntry.ID, before other: PlanEntry.ID?, _ day: Day, _ mealTypeID: MealType.ID, _ db: Database
    ) throws {
        var ids = try Int64.fetchAll(
            db, sql: "SELECT id FROM plan_entry WHERE day = ? AND mealTypeId = ? ORDER BY position, id",
            arguments: [day.description, mealTypeID]
        ).filter { $0 != id }
        let index = other.flatMap { ids.firstIndex(of: $0) } ?? ids.count
        ids.insert(id, at: index)
        for (position, entry) in ids.enumerated() {
            try db.execute(sql: "UPDATE plan_entry SET position = ? WHERE id = ?", arguments: [position, entry])
        }
    }
}
