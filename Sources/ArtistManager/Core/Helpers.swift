import Foundation

/// Every record the app stores in a collection conforms to this, so the workspace
/// can diff, log and undo changes generically.
protocol Entity: Codable, Equatable, Identifiable where ID == UUID {}

enum JSONCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func encode<T: Encodable>(_ value: T) -> Data? {
        try? encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var isBlank: Bool { trimmed.isEmpty }

    /// Splits a comma-separated list into trimmed, non-empty values.
    var commaSeparatedValues: [String] {
        split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
    }
}

extension Array where Element == String {
    var commaJoined: String { joined(separator: ", ") }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    func adding(hours: Int) -> Date {
        Calendar.current.date(byAdding: .hour, value: hours, to: self) ?? self
    }

    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    /// Whole calendar days from `start` to `end` (negative if `end` is earlier).
    static func daysBetween(_ start: Date, _ end: Date) -> Int {
        Calendar.current.dateComponents([.day], from: start.startOfDay, to: end.startOfDay).day ?? 0
    }

    /// The next date (today included) that falls on `weekday` (1 = Sunday … 7 = Saturday).
    func nextOccurrence(ofWeekday weekday: Int) -> Date {
        let calendar = Calendar.current
        var date = startOfDay
        for _ in 0..<8 {
            if calendar.component(.weekday, from: date) == weekday { return date }
            date = date.adding(days: 1)
        }
        return date
    }

    var weekday: Int { Calendar.current.component(.weekday, from: self) }
}

enum Money {
    static func format(_ value: Double, currency: String) -> String {
        value.formatted(.currency(code: currency.isBlank ? "USD" : currency))
    }
}
