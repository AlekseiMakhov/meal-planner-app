/// The Snowball stemmer for Russian (snowballstem.org/algorithms/russian): removes endings so the forms of
/// a word share a stem — «молоко», «молока» and «молоком» all become «молок». Expects lowercase text with
/// «ё» already written as «е»; anything that is not a Cyrillic word comes back unchanged.
public enum RussianStemmer {
    public static func stem(_ word: String) -> String {
        let letters = Array(word)
        guard letters.count > 2, letters.allSatisfy({ ("а"..."я").contains($0) }) else { return word }
        var stemmer = Stemmer(letters)
        stemmer.run()
        return String(stemmer.letters)
    }

    private static let vowels: Set<Character> = ["а", "е", "и", "о", "у", "ы", "э", "ю", "я"]

    private static let perfectiveGerund1 = ["в", "вши", "вшись"]
    private static let perfectiveGerund2 = ["ив", "ивши", "ившись", "ыв", "ывши", "ывшись"]
    private static let adjective = [
        "ее", "ие", "ые", "ое", "ими", "ыми", "ей", "ий", "ый", "ой", "ем", "им", "ым", "ом", "его", "ого", "ему",
        "ому", "их", "ых", "ую", "юю", "ая", "яя", "ою", "ею",
    ]
    private static let participle1 = ["ем", "нн", "вш", "ющ", "щ"]
    private static let participle2 = ["ивш", "ывш", "ующ"]
    private static let reflexive = ["ся", "сь"]
    private static let verb1 = [
        "ла", "на", "ете", "йте", "ли", "й", "л", "ем", "н", "ло", "но", "ет", "ют", "ны", "ть", "ешь", "нно",
    ]
    private static let verb2 = [
        "ила", "ыла", "ена", "ейте", "уйте", "ите", "или", "ыли", "ей", "уй", "ил", "ыл", "им", "ым", "ен", "ило",
        "ыло", "ено", "ят", "ует", "уют", "ит", "ыт", "ены", "ить", "ыть", "ишь", "ую", "ю",
    ]
    private static let noun = [
        "а", "ев", "ов", "ие", "ье", "е", "иями", "ями", "ами", "еи", "ии", "и", "ией", "ей", "ой", "ий", "й", "иям",
        "ям", "ием", "ем", "ам", "ом", "о", "у", "ах", "иях", "ях", "ы", "ь", "ию", "ью", "ю", "ия", "ья", "я",
    ]
    private static let superlative = ["ейш", "ейше"]
    private static let derivational = ["ост", "ость"]

    private struct Stemmer {
        var letters: [Character]
        /// Where RV starts: after the first vowel. Endings are only looked for there.
        let rv: Int
        /// Where R2 starts; derivational endings must lie wholly inside it.
        let r2: Int

        init(_ letters: [Character]) {
            self.letters = letters
            func after(_ isWanted: (Character) -> Bool, from start: Int) -> Int {
                var index = start
                while index < letters.count, !isWanted(letters[index]) { index += 1 }
                return min(index + 1, letters.count)
            }
            let isVowel = { RussianStemmer.vowels.contains($0) }
            rv = after(isVowel, from: 0)
            let r1 = after({ !isVowel($0) }, from: rv)
            r2 = after({ !isVowel($0) }, from: after(isVowel, from: r1))
        }

        mutating func run() {
            // Step 1: a perfective gerund, or else an optional reflexive followed by an adjectival, verb or
            // noun ending.
            if !removeConditional(RussianStemmer.perfectiveGerund1, RussianStemmer.perfectiveGerund2) {
                _ = remove(longest(RussianStemmer.reflexive))
                if !removeAdjectival(), !removeConditional(RussianStemmer.verb1, RussianStemmer.verb2) {
                    _ = remove(longest(RussianStemmer.noun))
                }
            }
            // Step 2.
            _ = remove(longest(["и"]))
            // Step 3.
            if let ending = longest(RussianStemmer.derivational), letters.count - ending.count >= r2 {
                _ = remove(ending)
            }
            // Step 4.
            if remove(longest(RussianStemmer.superlative)) {
                if hasEnding("нн") { letters.removeLast() }
            } else if hasEnding("нн") {
                letters.removeLast()
            } else {
                _ = remove(longest(["ь"]))
            }
        }

        /// The longest of the endings the word has within RV.
        func longest(_ endings: [String]) -> String? {
            endings.filter(hasEnding).max { $0.count < $1.count }
        }

        func hasEnding(_ ending: String) -> Bool {
            let start = letters.count - ending.count
            return start >= rv && letters[start...].elementsEqual(ending)
        }

        mutating func remove(_ ending: String?) -> Bool {
            guard let ending else { return false }
            letters.removeLast(ending.count)
            return true
        }

        /// Among both groups the longest ending decides; one from the first group only goes after «а» or «я».
        mutating func removeConditional(_ first: [String], _ second: [String]) -> Bool {
            guard let ending = longest(first + second) else { return false }
            if second.contains(ending) || precededByAOrYa(ending) {
                return remove(ending)
            }
            return false
        }

        func precededByAOrYa(_ ending: String) -> Bool {
            let index = letters.count - ending.count - 1
            return index >= rv && (letters[index] == "а" || letters[index] == "я")
        }

        mutating func removeAdjectival() -> Bool {
            guard remove(longest(RussianStemmer.adjective)) else { return false }
            _ = removeConditional(RussianStemmer.participle1, RussianStemmer.participle2)
            return true
        }
    }
}
