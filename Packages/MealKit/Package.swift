// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MealKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MealCore", targets: ["MealCore"]),
        .library(name: "MealStore", targets: ["MealStore"]),
        .library(name: "MealMCP", targets: ["MealMCP"]),
    ],
    dependencies: [
        // Minor-pinned: the Xcode project is generated, so its Package.resolved is not kept in git.
        .package(url: "https://github.com/groue/GRDB.swift.git", .upToNextMinor(from: "7.11.1")),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", .upToNextMinor(from: "0.12.1")),
    ],
    targets: [
        .target(name: "MealCore"),
        .target(name: "MealStore", dependencies: ["MealCore", .product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "MealMCP", dependencies: ["MealCore", "MealStore", .product(name: "MCP", package: "swift-sdk")]),
        .testTarget(name: "MealCoreTests", dependencies: ["MealCore"]),
        .testTarget(name: "MealStoreTests", dependencies: ["MealStore", "MealCore"]),
        .testTarget(
            name: "MealMCPTests",
            dependencies: ["MealMCP", "MealStore", "MealCore", .product(name: "MCP", package: "swift-sdk")]),
    ]
)
