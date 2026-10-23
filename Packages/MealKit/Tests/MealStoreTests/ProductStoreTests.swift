import Foundation
import GRDB
import MealCore
import Testing

@testable import MealStore

/// A small product base of its own: the products a test names, with what it says about them.
struct Fixture {
    let database: AppDatabase
    private(set) var aisles: [String: Int64] = [:]

    init() throws {
        database = try AppDatabase.inMemory()
        try database.writer.write { db in
            for (position, name) in ["Овощи", "Молочное", "Специи"].enumerated() {
                var record = AisleRecord(name: name, position: position)
                try record.insert(db)
                aisles[name] = record.id
            }
        }
    }

    @discardableResult
    func add(
        _ name: String, aliases: [String] = [], aisle: String? = nil, kcal: Double? = nil, protein: Double? = nil,
        fat: Double? = nil, carbs: Double? = nil, staple: Bool = false, source: NutritionSource? = nil,
        review: Bool = false, created: Date = .now
    ) throws -> Product {
        var product = try database.newProduct(named: name)
        product.aliases = aliases
        product.aisleID = aisle.flatMap { aisles[$0] }
        product.kcal = kcal
        product.protein = protein
        product.fat = fat
        product.carbs = carbs
        product.isStaple = staple
        product.nutritionSource = source
        product.needsReview = review
        product = try database.save(product)
        if created != product.createdAt {
            let id = product.id
            try database.writer.write { db in
                try db.execute(sql: "UPDATE product SET createdAt = ? WHERE id = ?", arguments: [created, id])
            }
        }
        return product
    }

    func names(_ query: ProductQuery, limit: Int = 100) throws -> [String] {
        try database.products(query, limit: limit).rows.map(\.name)
    }
}

struct ProductStoreTests {
    @Test func newProductsGetANameThatIsFree() throws {
        let fixture = try Fixture()
        #expect(try fixture.database.newProduct().name == "Новый продукт")
        #expect(try fixture.database.newProduct().name == "Новый продукт 2")
        #expect(try fixture.database.newProduct(named: "Сахар").name == "Сахар")
    }

    @Test func savingTidiesAndRefusesATakenName() throws {
        let fixture = try Fixture()
        try fixture.add("Свёкла")
        var beet = try fixture.add("  Морковь ", aliases: ["морковка", " Морковка", ""])
        #expect(beet.name == "Морковь")
        #expect(beet.aliases == ["морковка"])

        beet.name = "СВЕКЛА"
        #expect(throws: StoreError("Продукт «Свёкла» уже есть.")) { try fixture.database.save(beet) }
        beet.name = ""
        #expect(throws: StoreError("Нужно название.")) { try fixture.database.save(beet) }
        beet.name = "Морковь"
        beet.kcal = 2000
        #expect(throws: StoreError.self) { try fixture.database.save(beet) }
    }

    @Test func savingKeepsWhenItWasCreated() throws {
        let fixture = try Fixture()
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        var product = try fixture.add("Гречка", created: created)
        product.kcal = 343
        let saved = try fixture.database.save(product)
        #expect(saved.createdAt == created)
        #expect(saved.updatedAt > created)
    }

    @Test func productIsFoundByNameOrAliasIgnoringCaseAndYo() throws {
        let fixture = try Fixture()
        try fixture.add("Свёкла", aliases: ["буряк"])
        try fixture.add("Яйцо куриное", aliases: ["яйца", "яиц"])
        #expect(try fixture.database.product(named: "СВЕКЛА")?.name == "Свёкла")
        #expect(try fixture.database.product(named: "буряк")?.name == "Свёкла")
        #expect(try fixture.database.product(named: "яиц")?.name == "Яйцо куриное")
        #expect(try fixture.database.product(named: "яйцо") == nil)
        #expect(try fixture.database.product(named: " ") == nil)
    }

    @Test func aNameMeansTheExactProductThenTheOneOfTheSameWords() throws {
        let fixture = try Fixture()
        for name in ["Сахар", "Сахар коричневый", "Сахарная пудра", "Сыр гауда", "Сыр чеддер"] {
            try fixture.add(name)
        }
        func match(_ name: String) throws -> String? {
            guard case .found(let product) = try fixture.database.matchProduct(named: name) else { return nil }
            return product.name
        }
        #expect(try match("Сахар") == "Сахар")
        #expect(try match("сахара") == "Сахар")
        #expect(try match("пудры сахарной") == "Сахарная пудра")
        guard case .ambiguous(let cheeses) = try fixture.database.matchProduct(named: "сыра") else {
            Issue.record("several cheeses should fit")
            return
        }
        #expect(Set(cheeses.map(\.name)) == ["Сыр гауда", "Сыр чеддер"])
        #expect(try fixture.database.matchProduct(named: "кофе") == ProductMatch.none)
    }

    @Test func deletedProductIsGone() throws {
        let fixture = try Fixture()
        let salt = try fixture.add("Соль")
        try fixture.database.deleteProduct(id: salt.id)
        #expect(try fixture.database.product(id: salt.id) == nil)
        #expect(try fixture.names(ProductQuery(text: "соль")).isEmpty)
    }

    @Test func mergingKeepsOneProductWithEverythingBothKnew() throws {
        let fixture = try Fixture()
        var kept = try fixture.add("Яйцо куриное", aliases: ["яйца"], aisle: "Молочное")
        kept.gramsPerPiece = 50
        kept.namedUnits = [.pack: 600]
        kept = try fixture.database.save(kept)
        var duplicate = try fixture.add(
            "Яйца С1", aliases: ["яйцо с1", "яйца"], kcal: 157, protein: 12.7, fat: 11.5, carbs: 0.7, source: .label)
        duplicate.density = 1.03
        duplicate.namedUnits = [.pack: 360, .can: 1]
        duplicate.isStaple = true
        duplicate = try fixture.database.save(duplicate)

        let merged = try fixture.database.mergeProduct(duplicate.id, into: kept.id)
        #expect(merged.id == kept.id)
        #expect(merged.name == "Яйцо куриное")
        #expect(merged.aliases == ["яйца", "Яйца С1", "яйцо с1"])
        #expect(merged.nutrition == duplicate.nutrition)
        #expect(merged.nutritionSource == .label)
        #expect(merged.gramsPerPiece == 50)
        #expect(merged.density == 1.03)
        #expect(merged.namedUnits == [.pack: 600, .can: 1])
        #expect(merged.isStaple)
        #expect(merged.aisleID == fixture.aisles["Молочное"])
        #expect(try fixture.database.product(id: duplicate.id) == nil)
        #expect(try fixture.names(ProductQuery(text: "с1")) == ["Яйцо куриное"])
    }

    @Test func mergingKeepsTheNutritionOfTheOneThatStays() throws {
        let fixture = try Fixture()
        let kept = try fixture.add("Молоко", kcal: 61, protein: 3.15, fat: 3.25, carbs: 4.8, source: .usda)
        let duplicate = try fixture.add("Молочко", kcal: 50, protein: 3, fat: 2, carbs: 5, source: .manual)
        let merged = try fixture.database.mergeProduct(duplicate.id, into: kept.id)
        #expect(merged.kcal == 61)
        #expect(merged.nutritionSource == .usda)
    }

    @Test func aProductCannotMergeWithItself() throws {
        let fixture = try Fixture()
        let salt = try fixture.add("Соль")
        #expect(throws: StoreError.self) { try fixture.database.mergeProduct(salt.id, into: salt.id) }
    }
}
