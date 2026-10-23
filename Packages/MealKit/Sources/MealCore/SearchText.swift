/// How names are compared and searched: case and «ё» do not matter, and any form of a Russian word finds
/// the others.
public enum SearchText {
    /// Lowercase, «ё» as «е», words joined by single spaces with punctuation dropped. The search index
    /// splits words the same way.
    public static func normalized(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }

    /// The words of a query as search terms, each to be matched as a prefix. Russian words are cut to their
    /// stem, so «молока» finds «молоко» and «сливочного» finds «сливочное».
    public static func terms(_ query: String) -> [String] {
        normalized(query).split(separator: " ").map { word in
            let stem = RussianStemmer.stem(String(word))
            return stem.count >= 2 ? stem : String(word)
        }
    }
}
