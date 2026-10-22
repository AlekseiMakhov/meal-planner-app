import Foundation
import MealCore
import MealMCP

// meal-planner-mcp [--directory <folder>]
// Inside MealPlanner.app it works with the app's own data (a Debug build has a folder of its own).
// Outside it, with the installed app's data, or the folder given.

let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
let arguments = CommandLine.arguments

func value(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

let location: MealDataLocation
if let directory = value(after: "--directory") {
    location = MealDataLocation(directory: URL(filePath: directory, directoryHint: .isDirectory))
} else if let executable = Bundle.main.executableURL, let app = MealDataLocation.enclosingApp(of: executable) {
    location = app
} else if let installed = MealDataLocation.installedApp(bundleID: AppIdentity.bundleID) {
    location = installed
} else {
    FileHandle.standardError.write(Data("meal-planner-mcp: no data folder\n".utf8))
    exit(1)
}
try await MealMCPServer.run(version: version, location: location)
