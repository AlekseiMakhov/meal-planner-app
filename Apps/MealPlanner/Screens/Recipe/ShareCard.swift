import AppKit
import CoreImage.CIFilterBuiltins
import MealCore
import MealStore
import SwiftUI

/// «Поделиться» рецептом: a picture sized for a phone's screen and the same recipe as text — AirDrop puts the
/// picture into Photos, Messages and Notes take both.
enum RecipeShare {
    /// The card's width in points; rendered at three pixels to the point, a phone's own resolution.
    static let width: CGFloat = 390

    @MainActor
    static func items(for details: RecipeDetails, servings: Int, images: ImageStore) -> [Any] {
        var items: [Any] = []
        if let card = cardFile(for: details, servings: servings, images: images) {
            items.append(card)
        }
        items.append(text(for: details, servings: servings))
        return items
    }

    /// The card as a PNG file named after the recipe, in a folder of its own among the temporary files.
    @MainActor
    static func cardFile(for details: RecipeDetails, servings: Int, images: ImageStore) -> URL? {
        let photo = details.recipe.photo.flatMap { NSImage(contentsOf: images.url(for: $0)) }
        let renderer = ImageRenderer(
            content: RecipeShareCard(details: details, servings: servings, photo: photo, code: qrCode(for: details))
                .frame(width: width))
        renderer.scale = 3
        guard let image = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "Meal Planner share", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = details.recipe.title.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined()
        let file = folder.appending(path: (name.isEmpty ? "Рецепт" : name) + ".png")
        do {
            try data.write(to: file, options: .atomic)
            return file
        } catch {
            return nil
        }
    }

    /// The recipe as text to copy: title, nutrition, ingredients for `servings`, steps and links.
    static func text(for details: RecipeDetails, servings: Int) -> String {
        let recipe = details.recipe
        var lines = [recipe.title]
        if let summary = nutritionLine(details) {
            lines.append(summary)
        }
        lines.append(
            [Formatting.servings(servings).capitalizedFirst, recipe.totalMinutes.map(Formatting.minutes)]
                .compactMap { $0 }.joined(separator: " · "))
        if !details.ingredients.isEmpty {
            lines += ["", "Ингредиенты:"]
            var group: String?
            for line in details.ingredients {
                if line.group != group, let title = line.group {
                    lines.append(title + ":")
                }
                group = line.group
                lines.append("— " + ingredientText(line.scaled(to: servings, of: recipe.servings), details))
            }
        }
        if !details.steps.isEmpty {
            lines += ["", "Приготовление:"]
            lines += details.steps.enumerated().map { "\($0.offset + 1). \($0.element.text)" }
        }
        let notes = recipe.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            lines += ["", notes]
        }
        let links = [
            (recipe.videoURL.flatMap(VideoEmbed.player)?.page.absoluteString).map { "Видео: " + $0 },
            recipe.sourceURL.map { "Источник: " + $0 },
        ].compactMap { $0 }
        if !links.isEmpty {
            lines += [""] + links
        }
        return lines.joined(separator: "\n")
    }

    /// «140 ккал/100 г · порция 280 ккал (Б 20 · Ж 18 · У 6)».
    static func nutritionLine(_ details: RecipeDetails) -> String? {
        let nutrition = details.nutrition
        let approximate = nutrition.isComplete ? "" : "≈ "
        var parts: [String] = []
        if let per100 = nutrition.per100g {
            parts.append("\(approximate)\(Formatting.number(per100.kcal, digits: 0)) ккал/100 г")
        }
        if let serving = nutrition.perServing {
            parts.append(
                "порция \(approximate)\(Formatting.number(serving.kcal, digits: 0)) ккал (Б \(Formatting.number(serving.protein, digits: 0)) · Ж \(Formatting.number(serving.fat, digits: 0)) · У \(Formatting.number(serving.carbs, digits: 0)))"
            )
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// «Яйцо куриное — 3 шт. (мелко нарезать)», «Соль — по вкусу».
    static func ingredientText(_ line: RecipeIngredient, _ details: RecipeDetails) -> String {
        let name = details.products[line.productID]?.name ?? "Продукт"
        let amount = Formatting.amount(line)
        let quantity = [amount.amount, amount.unit].filter { !$0.isEmpty }.joined(separator: " ")
        var text = quantity.isEmpty ? name : "\(name) — \(quantity)"
        let note = [line.note, line.isOptional ? "по желанию" : nil].compactMap { $0 }.joined(separator: ", ")
        if !note.isEmpty {
            text += " (\(note))"
        }
        return text
    }

    /// A QR code for the video, or else the source: the phone's camera opens it.
    static func qrCode(for details: RecipeDetails) -> (image: NSImage, caption: String)? {
        let video = details.recipe.videoURL.flatMap(VideoEmbed.player)?.page
        let source = details.recipe.sourceURL.flatMap(URL.init(string:)).flatMap {
            $0.scheme?.hasPrefix("http") == true ? $0 : nil
        }
        guard let url = video ?? source else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
            let image = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return (NSImage(cgImage: image, size: NSSize(width: 120, height: 120)), video != nil ? "Видео" : "Источник")
    }
}

extension String {
    /// «на 2 порции» → «На 2 порции».
    fileprivate var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

/// The picture «Поделиться» sends: the recipe as one tall card for a phone.
struct RecipeShareCard: View {
    let details: RecipeDetails
    let servings: Int
    let photo: NSImage?
    let code: (image: NSImage, caption: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let photo {
                Image(nsImage: photo)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: RecipeShare.width, height: 260)
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 16) {
                Text(details.recipe.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    if let nutrition = RecipeShare.nutritionLine(details) {
                        Text(nutrition)
                    }
                    Text(
                        [
                            Formatting.servings(servings).capitalizedFirst,
                            details.recipe.totalMinutes.map(Formatting.minutes),
                        ]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                }
                .font(.system(size: 13))
                .foregroundStyle(Color(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
                if !details.ingredients.isEmpty {
                    section("Ингредиенты") {
                        ForEach(details.ingredients) { line in
                            Text(
                                "•  "
                                    + RecipeShare.ingredientText(
                                        line.scaled(to: servings, of: details.recipe.servings), details)
                            )
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if !details.steps.isEmpty {
                    section("Приготовление") {
                        ForEach(Array(details.steps.enumerated()), id: \.element.id) { index, step in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(index + 1).")
                                    .foregroundStyle(Color(.textSecondary))
                                    .monospacedDigit()
                                Text(step.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                HStack(alignment: .bottom) {
                    Text("Meal Planner & Recipes")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(.textSecondary))
                    Spacer()
                    if let code {
                        VStack(spacing: 4) {
                            Image(nsImage: code.image)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 96, height: 96)
                                .padding(6)
                                .background(.white, in: RoundedRectangle(cornerRadius: 6))
                            Text(code.caption)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(.textSecondary))
                        }
                    }
                }
            }
            .padding(22)
        }
        .frame(width: RecipeShare.width, alignment: .leading)
        .background(Color(.canvas))
        .environment(\.colorScheme, .dark)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(.textPrimary))
            content()
                .font(.system(size: 14))
                .foregroundStyle(Color(.textPrimary))
        }
    }
}

/// A toolbar button that opens the system's «Поделиться» menu next to itself with what `items` gives.
struct ShareButton: NSViewRepresentable {
    let items: @MainActor () -> [Any]

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            image: NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Поделиться")
                ?? NSImage(),
            target: context.coordinator, action: #selector(Coordinator.share(_:)))
        button.bezelStyle = .toolbar
        button.toolTip = "Поделиться: картинка и текст"
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.items = items
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items)
    }

    @MainActor
    final class Coordinator: NSObject {
        var items: @MainActor () -> [Any]

        init(items: @escaping @MainActor () -> [Any]) {
            self.items = items
        }

        @objc func share(_ sender: NSButton) {
            NSSharingServicePicker(items: items()).show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}
