import Foundation
import GRDB
import MealCore
import Testing

@testable import MealStore

/// The list budget on 20 000 products in a database file: the first block under 50 ms, a search keystroke
/// or a new order under 100 ms. Meaningful only in an optimized build: `make perf`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MEAL_PERF"] == "1"))
struct ProductPerformanceTests {
    private static let products = 20_000

    /// The starting base, plus copies of its products under new names until there are 20 000.
    private static func database() throws -> (AppDatabase, URL) {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "meal perf \(UUID().uuidString)", directoryHint: .isDirectory)
        let database = try AppDatabase.open(in: folder)
        let seed = try database.products(ProductQuery(), limit: 1000).rows
        try database.writer.write { db in
            for index in 0..<(products - seed.count) {
                var product = seed[index % seed.count]
                product.name = "\(product.name) \(index)"
                product.seedKey = nil
                product.kcal = product.kcal.map { $0 + Double(index % 7) }
                var record = ProductRecord(product, id: nil)
                try record.insert(db)
            }
        }
        return (database, folder)
    }

    /// The median of five runs, in milliseconds.
    private func milliseconds(_ work: () throws -> Void) rethrows -> Double {
        var runs: [Duration] = []
        for _ in 0..<5 {
            let start = ContinuousClock.now
            try work()
            runs.append(ContinuousClock.now - start)
        }
        let median = runs.sorted()[2]
        return Double(median.components.seconds) * 1000 + Double(median.components.attoseconds) / 1e15
    }

    @Test func listStaysWithinBudget() throws {
        let (database, folder) = try Self.database()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(try database.products(ProductQuery(), limit: 1).total == Self.products)
        let dairy = try #require(try database.aisles().first { $0.name == "Молочное и яйца" })

        let first = try milliseconds { _ = try database.products(ProductQuery(), limit: 100) }
        print("first block: \(first) ms")
        #expect(first < 50)

        for text in ["м", "мо", "мол", "моло", "молок", "сливочного масла", "яйц", "свёкла 12"] {
            let search = try milliseconds { _ = try database.products(ProductQuery(text: text), limit: 100) }
            print("search «\(text)»: \(search) ms")
            #expect(search < 100, "«\(text)»")
        }

        let orders: [[SortTerm<ProductQuery.SortKey>]] = [
            [SortTerm(.kcal, .descending)], [SortTerm(.aisle)], [SortTerm(.protein)],
            [SortTerm(.createdAt, .descending)], [SortTerm(.name, .descending)],
        ]
        for sort in orders {
            let ordered = try milliseconds { _ = try database.products(ProductQuery(sort: sort), limit: 100) }
            print("order \(sort.map(\.key)): \(ordered) ms")
            #expect(ordered < 100)
        }

        let filtered = try milliseconds {
            _ = try database.products(
                ProductQuery(
                    text: "мол", aisleIDs: [dairy.id], nutrition: .complete, kcal: ValueRange(min: 40, max: 400),
                    sort: [SortTerm(.kcal)]),
                limit: 100)
        }
        print("search, filters and order: \(filtered) ms")
        #expect(filtered < 100)
    }
}
