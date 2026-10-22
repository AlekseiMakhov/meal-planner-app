import Foundation
import MealCore
import MealStore

/// The folder the server works with: the data of the app it lives in, of the installed app, or a folder
/// given on the command line.
public struct MealDataLocation: Sendable, Equatable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The data of the app this tool lives in, `MealPlanner.app/Contents/Helpers/meal-planner-mcp`:
    /// a Debug build has a folder of its own.
    public static func enclosingApp(of executable: URL) -> MealDataLocation? {
        let app = executable.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard app.pathExtension == "app", let bundleID = Bundle(url: app)?.bundleIdentifier else { return nil }
        return installedApp(bundleID: bundleID)
    }

    /// The data of the app with this bundle id, whether or not the tool lives inside it.
    public static func installedApp(bundleID: String) -> MealDataLocation? {
        guard let directory = try? AppDatabase.defaultDirectory(debug: AppIdentity.isDebug(bundleID: bundleID))
        else { return nil }
        return MealDataLocation(directory: directory)
    }

    var databaseFile: URL {
        AppDatabase.file(in: directory)
    }
}
