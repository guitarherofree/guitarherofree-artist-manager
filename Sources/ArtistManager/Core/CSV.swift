import Foundation

/// RFC 4180 CSV reading and writing (quoted fields, escaped quotes, CRLF or LF, UTF-8 BOM).
enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text)
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\r\n", "\n", "\r":
                    row.append(field)
                    field = ""
                    rows.append(row)
                    row = []
                default:
                    field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        // Drop fully blank lines.
        return rows.filter { !($0.count == 1 && $0[0].isBlank) }
    }

    /// Parses a file with a header row into dictionaries keyed by normalized header name.
    static func parseTable(_ text: String) -> (headers: [String], rows: [[String: String]]) {
        let raw = parse(text)
        guard let header = raw.first else { return ([], []) }
        let headers = header.map { normalizeHeader($0) }
        let rows = raw.dropFirst().map { values -> [String: String] in
            var dict: [String: String] = [:]
            for (index, key) in headers.enumerated() where index < values.count {
                if dict[key] == nil || dict[key]!.isBlank { dict[key] = values[index] }
            }
            return dict
        }
        return (headers, Array(rows))
    }

    static func normalizeHeader(_ header: String) -> String {
        let lowered = header.trimmed.lowercased()
        let mapped = lowered.map { ch -> Character in
            (ch.isLetter || ch.isNumber) ? ch : "_"
        }
        var result = String(mapped)
        while result.contains("__") { result = result.replacingOccurrences(of: "__", with: "_") }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    static func escape(_ value: String) -> String {
        // Guard against spreadsheet formula injection when files are opened in Excel/Numbers.
        var v = value
        if let first = v.first, "=+-@".contains(first), !v.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "." }) {
            v = "'" + v
        }
        if v.contains(",") || v.contains("\"") || v.contains("\n") || v.contains("\r") {
            return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return v
    }

    static func write(headers: [String], rows: [[String]]) -> String {
        var lines = [headers.map(escape).joined(separator: ",")]
        for row in rows { lines.append(row.map(escape).joined(separator: ",")) }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// First non-empty value among several possible column names.
    static func value(_ row: [String: String], _ keys: [String]) -> String {
        for key in keys {
            if let v = row[key], !v.isBlank { return v.trimmed }
        }
        return ""
    }
}

enum DateParsing {
    private static let isoFull = ISO8601DateFormatter()
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let patterns = [
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
        "MM/dd/yyyy HH:mm:ss", "MM/dd/yyyy HH:mm", "MM/dd/yyyy", "M/d/yyyy", "M/d/yy", "dd.MM.yyyy",
        "MMMM d, yyyy", "MMM d, yyyy", "MMM. d, yyyy", "d MMMM yyyy", "d MMM yyyy", "EEEE, MMMM d, yyyy"
    ]
    private static let formatters: [DateFormatter] = patterns.map { pattern in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        return f
    }

    /// Best-effort parsing of the date formats email providers and spreadsheets export.
    static func parse(_ raw: String) -> Date? {
        let value = raw.trimmed
        guard !value.isEmpty else { return nil }
        if let d = isoFull.date(from: value) { return d }
        if let d = isoFractional.date(from: value) { return d }
        for formatter in formatters {
            if let d = formatter.date(from: value) { return d }
        }
        if let seconds = Double(value), seconds > 946_684_800 { // Unix timestamps after 2000
            return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
        }
        return nil
    }

    static func iso(_ date: Date?) -> String {
        guard let date else { return "" }
        return isoFull.string(from: date)
    }
}
