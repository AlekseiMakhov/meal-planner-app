import Foundation

/// An ingredient as a recipe writes it, taken apart: «3 ст. л. молока» is 3 tablespoons of «молока».
public struct ParsedIngredient: Hashable, Sendable {
    /// The product as written, in whatever case the line has it: «молока», «Сливочное масло».
    public var name: String
    /// Nil when the line gives no amount: «соль по вкусу», «масло для жарки».
    public var amount: Double?
    /// The upper end of a range: 3 in «2–3 зубчика».
    public var amountMax: Double?
    /// Nil only together with the amount; a bare number counts pieces.
    public var unit: MeasureUnit?
    /// What else the line says: «мелко нарезать», «для жарки», «крупный».
    public var note: String?
    /// «по желанию».
    public var isOptional: Bool

    public init(
        name: String, amount: Double? = nil, amountMax: Double? = nil, unit: MeasureUnit? = nil, note: String? = nil,
        isOptional: Bool = false
    ) {
        self.name = name
        self.amount = amount
        self.amountMax = amountMax
        self.unit = unit
        self.note = note
        self.isOptional = isOptional
    }
}

/// Reads ingredient lines the way Russian recipes write them: «Молоко — 3 ст. л.», «200 г сливочного масла
/// (растопить)», «2–3 зубчика чеснока», «½ стакана сахара», «Соль, перец — по вкусу».
public enum IngredientParser {
    /// Usually one ingredient; a line without an amount that lists several, such as «Соль, перец — по
    /// вкусу», gives one for each. Empty when the line names nothing.
    public static func parse(_ line: String) -> [ParsedIngredient] {
        var text = " " + line.trimmingCharacters(in: .whitespacesAndNewlines) + " "
        var notes: [String] = []
        var isOptional = false
        var toTaste = false

        text = replace(listMarker, in: text, with: " ")
        for inner in matches(parenthesis, in: text) {
            if contains(optionalPattern, inner) { isOptional = true }
            if contains(toTastePattern, inner) {
                toTaste = true
                continue
            }
            notes.append(inner)
        }
        text = replace(parenthesis, in: text, with: " ")
        text = normalizeNumbers(text)
        if contains(toTastePattern, text) {
            toTaste = true
            text = replace(toTastePattern, in: text, with: " ")
        }
        if contains(optionalPattern, text) {
            isOptional = true
            notes.append("по желанию")
            text = replace(optionalPattern, in: text, with: " ")
        }
        for purpose in matches(purposePattern, in: text, group: 0) {
            notes.append(purpose.trimmingCharacters(in: .whitespaces))
        }
        text = replace(purposePattern, in: text, with: " ")

        var amount: Amount? = findAmount(in: text)
        var name: String
        if let found = amount {
            let range = found.range
            let before = tidy(String(text[..<range.lowerBound]))
            let after = tidy(String(text[range.upperBound...]))
            if before.isEmpty {
                name = after
            } else if found.isHalfPiece {
                // «Сок половины лимона»: the half belongs to what follows it.
                name = tidy(before + " " + after)
            } else {
                name = before
                if !after.isEmpty { notes.append(after) }
            }
        } else {
            // «Мускатный орех — на кончике ножа»: the name, then a note.
            name = tidy(text)
            if let dash = firstMatch(dashSeparator, in: name) {
                let after = tidy(String(name[dash.upperBound...]))
                name = tidy(String(name[..<dash.lowerBound]))
                if !after.isEmpty { notes.append(after) }
            }
        }

        // «Помидоры, крупные»: what follows the first comma is a note — unless the line lists several
        // ingredients to taste.
        var names = [name]
        if amount == nil, toTaste || isOptional {
            names = name.split(whereSeparator: { $0 == "," })
                .flatMap { $0.components(separatedBy: " и ") }
                .map { tidy($0) }
                .filter { !$0.isEmpty }
        } else if let comma = name.firstIndex(of: ",") {
            let rest = tidy(String(name[name.index(after: comma)...]))
            if !rest.isEmpty { notes.insert(rest, at: 0) }
            name = tidy(String(name[..<comma]))
            names = [name]
        }

        if toTaste, amount == nil {
            amount = Amount(value: nil, max: nil, unit: .toTaste, range: text.startIndex..<text.startIndex)
        }
        return names.compactMap { name -> ParsedIngredient? in
            var name = name
            var lineNotes = notes
            if let size = firstMatch(sizeWord, in: name) {
                let rest = tidy(name.replacingCharacters(in: size, with: " "))
                if !rest.isEmpty {
                    lineNotes.insert(tidy(String(name[size])), at: 0)
                    name = rest
                }
            }
            name = restoringDecimalCommas(name)
            guard !name.isEmpty, name.contains(where: \.isLetter) else { return nil }
            let note = lineNotes.map(restoringDecimalCommas).filter { !$0.isEmpty }.joined(separator: ", ")
            return ParsedIngredient(
                name: name, amount: amount?.value, amountMax: amount?.max, unit: amount?.unit,
                note: note.isEmpty ? nil : note, isOptional: isOptional)
        }
    }

    // MARK: - Amounts

    private struct Amount {
        var value: Double?
        var max: Double?
        var unit: MeasureUnit
        var range: Range<String.Index>
        var isHalfPiece = false
    }

    /// The first amount in the line: digits, then number words, then «пол-», then a unit on its own.
    private static func findAmount(in text: String) -> Amount? {
        if let match = firstRegexMatch(digitsAmount, in: text) {
            let value = number(group(match, "num", in: text))
            let max = group(match, "max", in: text).flatMap(number)
            let unit = group(match, "unit", in: text).flatMap(unitFor) ?? .piece
            return Amount(value: value, max: max, unit: unit, range: range(match, in: text))
        }
        if let match = firstRegexMatch(wordAmount, in: text), let word = group(match, "word", in: text) {
            let unit = group(match, "unit", in: text).flatMap(unitFor) ?? .piece
            return Amount(value: numberWords[word.lowercased()], unit: unit, range: range(match, in: text))
        }
        if let match = firstRegexMatch(halfUnit, in: text), let unit = group(match, "unit", in: text).flatMap(unitFor) {
            return Amount(value: 0.5, unit: unit, range: range(match, in: text))
        }
        if let match = firstRegexMatch(halfPiece, in: text) {
            return Amount(value: 0.5, unit: .piece, range: range(match, in: text), isHalfPiece: true)
        }
        // «Петрушка — пучок», then «Стакан молока»: one of the unit. Only units that cannot start a product's
        // name count at the start of the line — «Листья салата» is not a leaf of «салата».
        for pattern in [unitAfterSeparator, unitAtStart] {
            if let match = firstRegexMatch(pattern, in: text),
                let unit = group(match, "unit", in: text).flatMap(unitFor),
                let unitRange = Range(match.range(withName: "unit"), in: text)
            {
                return Amount(value: 1, unit: unit, range: unitRange)
            }
        }
        return nil
    }

    private static func number(_ text: String?) -> Double? {
        guard let text else { return nil }
        let parts = text.split(separator: " ")
        var total = 0.0
        for part in parts {
            if let slash = part.firstIndex(of: "/") {
                guard let top = Double(part[..<slash]), let bottom = Double(part[part.index(after: slash)...]),
                    bottom != 0
                else { return nil }
                total += top / bottom
            } else {
                guard let value = Double(part) else { return nil }
                total += value
            }
        }
        return total
    }

    private static let numberWords: [String: Double] = [
        "один": 1, "одна": 1, "одно": 1, "одну": 1, "два": 2, "две": 2, "три": 3, "четыре": 4, "пять": 5,
        "шесть": 6, "семь": 7, "восемь": 8, "девять": 9, "десять": 10, "полтора": 1.5, "полторы": 1.5,
    ]

    /// Unit words in every form recipes write them, the longest alternatives first.
    private static let unitWords: [(MeasureUnit, String)] = [
        (
            .tablespoon,
            #"ст\.?\s*л\.?|ст\.?\s*ло(?:жк[аиуе]|жек|жки)|столов(?:ая|ые|ых|ой|ую)\s+ло(?:жк[аиуе]|жек|жкой|жки)|tbsp"#
        ),
        (
            .teaspoon,
            #"ч\.?\s*л\.?|ч\.?\s*ло(?:жк[аиуе]|жек|жки)|чайн(?:ая|ые|ых|ой|ую)\s+ло(?:жк[аиуе]|жек|жкой|жки)|tsp"#
        ),
        (.cup, #"стакан(?:а|ов|ы|чик|чика)?|ст\.(?!\s*л)"#),
        (.kilogram, #"кг\.?|килограмм(?:а|ов)?|кило"#),
        (.gram, #"гр\.?|грамм(?:а|ов)?|г\.?"#),
        (.milliliter, #"мл\.?|миллилитр(?:а|ов)?"#),
        (.liter, #"литр(?:а|ов)?|л\.?"#),
        (.piece, #"шт\.?|штук(?:а|и|у)?|штучк[аи]"#),
        (.clove, #"зубч(?:ик|ика|иков|ики|ок)|зубок|зуб\.|зб\."#),
        (.bunch, #"пуч(?:ок|ка|ков|ки|очек|очка)|пуч\."#),
        (.slice, #"ломт(?:ик|ика|иков|ики)|кус(?:ок|ка|ков|ки|очек|очка|очков|очки)"#),
        (.sprig, #"веточ(?:ка|ки|ек|ку)|вет(?:ка|ки|ок|ку)"#),
        (.leaf, #"лист(?:а|ов|ик|ика|иков|ья|ьев)?"#),
        (.head, #"голов(?:ка|ки|ок|ку)|кочан(?:а|ов|чик|чика)?"#),
        (.can, #"бан(?:ка|ки|ок|ку|очка|очки)|бан\."#),
        (.pack, #"упаков(?:ка|ки|ок|ку)|упак\.|уп\.|пач(?:ка|ки|ек|ку)|пакет(?:а|ов|ик|ика|иков)?"#),
        (.handful, #"горст(?:ь|и|ей|очка|очки)|горсточк[аи]"#),
        (.pinch, #"щепот(?:ка|ки|ок|ку|очка|очки)|щеп\."#),
    ]

    private static let unitPatterns: [(MeasureUnit, NSRegularExpression)] = unitWords.map { unit, pattern in
        (unit, regex("^(?:\(pattern))$"))
    }

    /// A unit written out: «г», «ст. л.», «зубчика», «стакан»; nil when the text is no unit.
    public static func unit(_ text: String) -> MeasureUnit? {
        unitFor(text)
    }

    private static func unitFor(_ text: String) -> MeasureUnit? {
        let text = text.trimmingCharacters(in: .whitespaces)
        return unitPatterns.first { contains($0.1, text) }?.0
    }

    private static let units = unitWords.map { "(?:\($0.1))" }.joined(separator: "|")
    private static let numberPattern = #"\d+(?:\.\d+)?(?:\s+\d+/\d+)?|\d+/\d+"#

    // A number is taken whole or not at all: «3,2%» is part of a name, not 3 pieces.
    private static let digitsAmount = regex(
        #"(?<![\p{L}\d./])(?<num>\#(numberPattern))(?![\d./])(?!\s*%)(?:\s*-\s*(?<max>\#(numberPattern))(?![\d./]))?"#
            + #"(?:\s*(?<unit>\#(units))(?![\p{L}]))?"#)
    private static let wordAmount = regex(
        #"(?<![\p{L}])(?<word>"# + numberWords.keys.sorted { $0.count > $1.count }.joined(separator: "|")
            + #")(?![\p{L}])(?:\s*(?<unit>\#(units))(?![\p{L}]))?"#)
    private static let halfUnit = regex(#"(?<![\p{L}])пол(?:-|\s)?(?<unit>\#(units))(?![\p{L}])"#)
    private static let halfPiece = regex(#"(?<![\p{L}])(?:половин(?:а|у|ы|ка|ку|ки)(?![\p{L}])|пол-(?=\p{L}))"#)
    private static let unitAfterSeparator = regex(#"[—:-]\s*(?<unit>\#(units))(?![\p{L}])"#)
    private static let unitAtStart = regex(
        #"^\s*(?<unit>"#
            + unitWords.filter {
                [.cup, .bunch, .pinch, .can, .pack, .handful, .head, .clove, .sprig, .slice].contains($0.0)
            }
            .map { "(?:\($0.1))" }.joined(separator: "|") + #")(?![\p{L}])"#)

    // MARK: - Notes

    private static let listMarker = regex(#"^\s*(?:[-–—•*·]\s+|\d+[.)]\s+(?=\p{L}))"#)
    private static let parenthesis = regex(#"\(([^()]*)\)"#)
    private static let toTastePattern = regex(#"(?<![\p{L}])по\s+вкусу(?![\p{L}])"#)
    private static let optionalPattern = regex(#"(?<![\p{L}])по\s+желанию(?![\p{L}])"#)
    private static let purposePattern = regex(#"(?<![\p{L}])для\s+\p{L}+(?:\s+и\s+\p{L}+)?"#)
    private static let dashSeparator = regex(#"\s[—–-]\s|:\s"#)
    private static let sizeWord = regex(
        #"^(?:крупн|средн|маленьк|небольш|больш)(?:ый|ий|ой|ая|яя|ое|ее|ые|ие|ых|их|ого|его|ую|юю)(?![\p{L}])"#)

    // MARK: - Text

    private static func normalizeNumbers(_ text: String) -> String {
        var text = text
        let fractions: [(String, String)] = [
            ("½", "1/2"), ("¼", "1/4"), ("¾", "3/4"), ("⅓", "1/3"), ("⅔", "2/3"), ("⅛", "1/8"),
        ]
        for (symbol, fraction) in fractions {
            text = replace(regex(#"(\d)\#(symbol)"#), in: text, with: "$1 \(fraction)")
            text = text.replacingOccurrences(of: symbol, with: " \(fraction)")
        }
        text = replace(regex(#"(\d),(\d)"#), in: text, with: "$1.$2")
        text = replace(regex(#"(\d)\s*[-–—]\s*(\d)"#), in: text, with: "$1-$2")
        return text
    }

    /// «82.5%» back to «82,5%»: the parser reads decimal commas as points.
    private static func restoringDecimalCommas(_ text: String) -> String {
        replace(regex(#"(\d)\.(\d)"#), in: text, with: "$1,$2")
    }

    /// Without the separators around it: «— », «: », trailing commas and dots.
    private static func tidy(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:.-–—+").union(.whitespaces))
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are constants; a mistake in one is a programming error.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func contains(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func firstRegexMatch(_ regex: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> Range<String.Index>? {
        firstRegexMatch(regex, in: text).flatMap { Range($0.range, in: text) }
    }

    private static func matches(_ regex: NSRegularExpression, in text: String, group: Int = 1) -> [String] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: group), in: text).map { String(text[$0]) }
        }
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func group(_ match: NSTextCheckingResult, _ name: String, in text: String) -> String? {
        Range(match.range(withName: name), in: text).map { String(text[$0]) }
    }

    private static func range(_ match: NSTextCheckingResult, in text: String) -> Range<String.Index> {
        Range(match.range, in: text)!
    }
}
