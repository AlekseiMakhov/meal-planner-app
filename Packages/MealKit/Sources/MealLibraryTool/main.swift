import Foundation
import MealCore
import MealStore

// `meal-library export <data folder> <library folder>`: the recipe library of a data folder, the way an installer
// image carries it. `make dmg` puts it into the app; a new Mac starts from it.

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 3, arguments[0] == "export" else {
    fail("usage: meal-library export <data folder> <library folder>", code: 64)
}
let data = URL(filePath: arguments[1], directoryHint: .isDirectory)
let library = URL(filePath: arguments[2], directoryHint: .isDirectory)
guard FileManager.default.fileExists(atPath: AppDatabase.file(in: data).path(percentEncoded: false)) else {
    fail("no database in \(data.path(percentEncoded: false))", code: 66)
}

do {
    try AppDatabase.open(in: data).exportLibrary(to: library)
    // The library is opened the way a new Mac opens it, to count what it brings.
    let check = FileManager.default.temporaryDirectory.appending(
        path: "meal library check \(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: check) }
    let database = try AppDatabase.open(in: check, library: library)
    let recipes = try database.recipeCards(RecipeQuery(), limit: 1).total
    let categories = try database.categories().count
    let products = try database.products(ProductQuery(), limit: 1).total
    print("library: \(recipes) recipes, \(categories) categories, \(products) products")
} catch {
    fail("export failed: \(error)", code: 1)
}
