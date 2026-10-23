import Foundation
import MealCore
import MealStore

/// The folder the server works with: the data of the app it lives in, of the installed app, or a folder
/// given on the command line.
public struct MealDataLocation: Sendable, Equatable {
    public let directory: URL
    /// The recipe library a new data folder starts from: the one in the app the server lives in, if the app
    /// came from an installer image. The server may be the first to open the data, before the app ever ran.
    public let library: URL?

    public init(directory: URL, library: URL? = nil) {
        self.directory = directory
        self.library = library
    }

    /// The data of the app this tool lives in, `MealPlanner.app/Contents/Helpers/meal-planner-mcp`:
    /// a Debug build has a folder of its own.
    public static func enclosingApp(of executable: URL) -> MealDataLocation? {
        let app = executable.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard app.pathExtension == "app", let bundleID = Bundle(url: app)?.bundleIdentifier,
            let location = installedApp(bundleID: bundleID)
        else { return nil }
        let library = app.appending(
            path: "Contents/Resources/\(AppIdentity.libraryFolderName)", directoryHint: .isDirectory)
        let hasLibrary = FileManager.default.fileExists(atPath: library.path(percentEncoded: false))
        return MealDataLocation(directory: location.directory, library: hasLibrary ? library : nil)
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
