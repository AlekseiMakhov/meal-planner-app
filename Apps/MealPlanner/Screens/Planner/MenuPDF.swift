import AppKit
import MealCore
import MealStore
import SwiftUI

/// «PDF меню»: the week day by day, then each of its recipes as the share card shows it — pages a phone wide, so
/// the file reads well in «Файлы» on an iPhone, offline.
enum MenuPDF {
    /// iCloud Drive's «Meal Planner» folder; nil without iCloud Drive.
    static var iCloudFolder: URL? {
        guard FileManager.default.fileExists(atPath: AppModel.iCloudDrive.path(percentEncoded: false)) else {
            return nil
        }
        return AppModel.iCloudDrive.appending(path: "Meal Planner", directoryHint: .isDirectory)
    }

    static func fileName(_ plan: WeekPlan) -> String {
        "Меню \(Formatting.week(plan.start)).pdf"
    }

    /// Writes the PDF; its pages: the week, then the recipes in the order they first come in it.
    @MainActor
    static func write(_ plan: WeekPlan, images: ImageStore, to file: URL) throws {
        var pages: [AnyView] = [AnyView(MenuOverviewPage(plan: plan))]
        var seen: Set<Recipe.ID> = []
        for entry in plan.entries {
            guard let id = entry.recipeID, let details = plan.recipes[id], seen.insert(id).inserted else { continue }
            let photo = details.recipe.photo.flatMap { NSImage(contentsOf: images.url(for: $0)) }
            pages.append(
                AnyView(
                    RecipeShareCard(
                        details: details, servings: entry.servings, photo: photo, code: RecipeShare.qrCode(for: details)
                    )
                    .frame(width: RecipeShare.width)))
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let context = CGContext(file as CFURL, mediaBox: nil, nil) else {
            throw StoreError("PDF не получилось создать.")
        }
        for page in pages {
            ImageRenderer(content: page).render { size, render in
                var box = CGRect(origin: .zero, size: size)
                context.beginPage(mediaBox: &box)
                render(context)
                context.endPage()
            }
        }
        context.closePDF()
    }
}

/// The first page: each day with its meals and dishes, and what the day adds up to per person.
private struct MenuOverviewPage: View {
    let plan: WeekPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Меню на неделю")
                    .font(.system(size: 26, weight: .bold))
                Text("Неделя \(plan.start.weekNumber) · \(Formatting.week(plan.start))")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(.textSecondary))
            }
            ForEach(plan.days, id: \.self) { day in
                let entries = plan.entries.filter { $0.day == day }
                if !entries.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(Formatting.weekdays[day.weekday - 1]), \(Formatting.day(day))")
                                .font(.system(size: 17, weight: .semibold))
                            Spacer()
                            let nutrition = plan.nutrition(on: day)
                            if nutrition.counted > 0 {
                                Text(
                                    "\(nutrition.uncounted > 0 ? "≈ " : "")\(Formatting.number(nutrition.perPerson.kcal, digits: 0)) ккал"
                                )
                                .font(.system(size: 13))
                                .foregroundStyle(Color(.textSecondary))
                            }
                        }
                        ForEach(plan.mealTypes) { meal in
                            let dishes = entries.filter { $0.mealTypeID == meal.id }
                            if !dishes.isEmpty {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(meal.name)
                                        .foregroundStyle(Color(.textSecondary))
                                        .frame(width: 78, alignment: .leading)
                                    Text(dishes.map(title).joined(separator: "; "))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.system(size: 14))
                            }
                        }
                    }
                }
            }
            if let average = plan.averageDay {
                Text("В среднем за день на человека: \(Formatting.number(average.perPerson.kcal, digits: 0)) ккал")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(.textSecondary))
            }
            Text("Meal Planner & Recipes")
                .font(.system(size: 11))
                .foregroundStyle(Color(.textSecondary))
        }
        .foregroundStyle(Color(.textPrimary))
        .padding(22)
        .frame(width: RecipeShare.width, alignment: .leading)
        .background(Color(.canvas))
        .environment(\.colorScheme, .dark)
    }

    private func title(_ entry: PlanEntry) -> String {
        guard let recipe = entry.recipeID.flatMap({ plan.recipes[$0] }) else { return entry.text ?? "" }
        return "\(recipe.recipe.title) (\(Formatting.count(entry.servings, "порция", "порции", "порций")))"
    }
}
