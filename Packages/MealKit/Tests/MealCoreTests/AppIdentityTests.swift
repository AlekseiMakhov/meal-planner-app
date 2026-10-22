import MealCore
import Testing

struct AppIdentityTests {
    @Test func debugBuildIsToldApartByItsBundleID() {
        #expect(!AppIdentity.isDebug(bundleID: AppIdentity.bundleID))
        #expect(AppIdentity.isDebug(bundleID: AppIdentity.debugBundleID))
        #expect(AppIdentity.debugBundleID == "inco.mealplanner.app.debug")
    }

    @Test func debugBuildKeepsItsDataApart() {
        #expect(AppIdentity.dataFolderName(debug: false) == "inco.mealplanner")
        #expect(AppIdentity.dataFolderName(debug: true) == "inco.mealplanner.debug")
    }
}
