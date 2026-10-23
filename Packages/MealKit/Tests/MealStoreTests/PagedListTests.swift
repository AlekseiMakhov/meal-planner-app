import Foundation
import MealCore
import Testing

@testable import MealStore

@MainActor
struct PagedListTests {
    /// Waits for the list to satisfy the condition, giving up after a few seconds.
    private func until(
        _ list: PagedList<ProductQuery, Product>, _ condition: (PagedList<ProductQuery, Product>) -> Bool
    ) async throws {
        let deadline = Date.now.addingTimeInterval(5)
        while !condition(list) {
            guard Date.now < deadline else {
                Issue.record("timed out with \(list.rows.count) of \(list.total) rows")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func list(_ fixture: Fixture, _ query: ProductQuery = ProductQuery()) -> PagedList<ProductQuery, Product> {
        let database = fixture.database
        return PagedList(query: query, pageSize: 100, prefetch: 20) { query, limit in
            database.observeProducts(query, limit: limit)
        }
    }

    @Test func loadsTheNextBlockNearTheEnd() async throws {
        let fixture = try Fixture()
        for index in 0..<250 {
            try fixture.add(String(format: "Продукт %03d", index))
        }
        let list = list(fixture)
        list.start()
        try await until(list) { $0.rows.count == 100 }
        #expect(list.total == 250)
        #expect(!list.isComplete)

        list.rowAppeared(list.rows[50].id)
        try await Task.sleep(for: .milliseconds(50))
        #expect(list.rows.count == 100, "a row far from the end loads nothing")

        list.rowAppeared(list.rows[85].id)
        try await until(list) { $0.rows.count == 200 }
        list.rowAppeared(list.rows[199].id)
        try await until(list) { $0.rows.count == 250 }
        #expect(list.isComplete)
        #expect(list.rows.map(\.name) == (0..<250).map { String(format: "Продукт %03d", $0) })
        list.stop()
    }

    @Test func blocksStayInOrderWhileProductsAreAdded() async throws {
        let fixture = try Fixture()
        for index in 0..<150 {
            try fixture.add(String(format: "Продукт %03d", index * 2))
        }
        let list = list(fixture)
        list.start()
        try await until(list) { $0.rows.count == 100 }

        // Another writer adds products while the list grows.
        let database = fixture.database
        let writer = Task.detached {
            for index in 0..<50 {
                var product = try database.newProduct(named: String(format: "Продукт %03d", index * 2 + 1))
                product.kcal = 1
                try database.save(product)
            }
        }
        list.rowAppeared(list.rows[99].id)
        try await writer.value
        try await until(list) { $0.total == 200 && $0.rows.count == 200 }
        let names = list.rows.map(\.name)
        #expect(names == names.sorted())
        #expect(Set(list.rows.map(\.id)).count == 200)
        list.stop()
    }

    @Test func onlyChangesInPlaceCountAsChanges() async throws {
        let fixture = try Fixture()
        for index in 0..<150 {
            try fixture.add(String(format: "Продукт %03d", index), kcal: Double(index))
        }
        let list = list(fixture)
        list.start()
        try await until(list) { $0.rows.count == 100 }
        list.rowAppeared(list.rows[99].id)
        try await until(list) { $0.rows.count == 150 }
        list.query.kcal.min = 10
        try await until(list) { $0.total == 140 }
        #expect(list.changes == 0, "first rows, the next block and a new query are not changes")

        var product = list.rows[0]
        product.name = "Продукт 010, свежий"
        try fixture.database.save(product)
        try await until(list) { $0.changes == 1 }
        #expect(list.rows.first?.name == "Продукт 010, свежий")
        list.stop()
    }

    @Test func aNewQueryStartsOverFromTheFirstBlock() async throws {
        let fixture = try Fixture()
        for index in 0..<150 {
            try fixture.add(String(format: "Продукт %03d", index), kcal: Double(index))
        }
        let list = list(fixture)
        list.start()
        try await until(list) { $0.rows.count == 100 }
        list.rowAppeared(list.rows[99].id)
        try await until(list) { $0.rows.count == 150 }
        let generation = list.generation

        list.query.kcal.min = 10
        try await until(list) { $0.total == 140 }
        #expect(list.rows.count == 100)
        #expect(list.limit == 100)
        #expect(list.generation == generation + 1)

        list.query.kcal.min = 10
        #expect(list.generation == generation + 1, "the same query changes nothing")
        list.stop()
    }
}
