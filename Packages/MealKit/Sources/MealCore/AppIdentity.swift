/// Names the app, its MCP server and the store share: bundle ids and the data folder. A Debug build has
/// an identity of its own, so it never touches the installed app's data.
public enum AppIdentity {
    /// The name people see: in the Dock, the menu bar and window titles.
    public static let displayName = "Meal Planner & Recipes"

    /// The installed (Release) app.
    public static let bundleID = "inco.mealplanner.app"

    public static let debugBundleID = bundleID + ".debug"

    public static func isDebug(bundleID: String) -> Bool {
        bundleID.hasSuffix(".debug")
    }

    /// The app's folder in Application Support.
    public static func dataFolderName(debug: Bool) -> String {
        debug ? "inco.mealplanner.debug" : "inco.mealplanner"
    }
}
