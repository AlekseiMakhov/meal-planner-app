import Foundation
import MCP

/// A tool call's arguments, read with checks that tell Claude how to fix a wrong call.
struct Arguments {
    let values: [String: Value]

    init(_ values: [String: Value]) {
        self.values = values
    }

    /// Whether the call gives the key a value; null counts as not given.
    func has(_ key: String) -> Bool {
        if let value = values[key], !value.isNull { return true }
        return false
    }

    /// Trimmed text; an empty string stays empty, so a field can be cleared.
    func string(_ key: String) throws(ToolError) -> String? {
        guard let value = values[key], !value.isNull else { return nil }
        guard let text = value.stringValue else { throw ToolError("«\(key)» — строка.") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trimmed text, nil when empty: for fields where an empty string means «none».
    func nonEmpty(_ key: String) throws(ToolError) -> String? {
        guard let text = try string(key), !text.isEmpty else { return nil }
        return text
    }

    func required(_ key: String) throws(ToolError) -> String {
        guard let text = try string(key), !text.isEmpty else { throw ToolError("Нужно «\(key)».") }
        return text
    }

    func int(_ key: String) throws(ToolError) -> Int? {
        guard let value = values[key], !value.isNull else { return nil }
        if let int = value.intValue { return int }
        if let double = value.doubleValue, double.rounded() == double, abs(double) < 1e12 { return Int(double) }
        if let text = value.stringValue, let int = Int(text.trimmingCharacters(in: .whitespaces)) { return int }
        throw ToolError("«\(key)» — целое число.")
    }

    func double(_ key: String) throws(ToolError) -> Double? {
        guard let value = values[key], !value.isNull else { return nil }
        if let double = value.doubleValue { return double }
        if let int = value.intValue { return Double(int) }
        if let text = value.stringValue,
            let double = Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        {
            return double
        }
        throw ToolError("«\(key)» — число.")
    }

    func bool(_ key: String) throws(ToolError) -> Bool? {
        guard let value = values[key], !value.isNull else { return nil }
        guard let bool = value.boolValue else { throw ToolError("«\(key)» — true или false.") }
        return bool
    }

    func array(_ key: String) throws(ToolError) -> [Value]? {
        guard let value = values[key], !value.isNull else { return nil }
        guard let array = value.arrayValue else { throw ToolError("«\(key)» — массив.") }
        return array
    }

    func strings(_ key: String) throws(ToolError) -> [String]? {
        guard let array = try array(key) else { return nil }
        return try array.map { value throws(ToolError) in
            guard let text = value.stringValue else { throw ToolError("«\(key)» — массив строк.") }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
    }

    func object(_ key: String) throws(ToolError) -> [String: Value]? {
        guard let value = values[key], !value.isNull else { return nil }
        guard let object = value.objectValue else { throw ToolError("«\(key)» — объект.") }
        return object
    }

    /// Where a page of results starts: the `next_cursor` of the previous page.
    func offset() throws(ToolError) -> Int {
        guard let cursor = try string("cursor"), !cursor.isEmpty else { return 0 }
        guard let offset = Int(cursor), offset >= 0 else {
            throw ToolError("«cursor» — значение next_cursor из прошлого ответа.")
        }
        return offset
    }

    /// How many results a page has: 30 unless asked, at most 100.
    func limit() throws(ToolError) -> Int {
        min(max(try int("limit") ?? 30, 1), 100)
    }
}
