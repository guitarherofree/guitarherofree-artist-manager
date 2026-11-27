import Foundation

struct ScheduleConflict: Identifiable, Equatable {
    var id: String
    var date: Date
    var title: String
    var detail: String
    var eventIDs: [UUID]
    var taskIDs: [UUID]
}

/// Something with a date that should show up on the agenda.
struct AgendaItem: Identifiable, Equatable {
    enum Source: Equatable { case event(UUID), task(UUID), release(UUID), campaign(UUID), followUp(UUID) }
    var id: String
    var date: Date
    var isAllDay: Bool
    var title: String
    var subtitle: String
    var symbol: String
    var source: Source
}

enum CalendarService {
    static func conflicts(in workspace: Workspace, from start: Date = Date().adding(days: -1), days: Int = 120) -> [ScheduleConflict] {
        let end = start.adding(days: days)
        let availability = workspace.profile.availability
        let events = workspace.events.filter { $0.interval.end > start && $0.interval.start < end }
            .sorted { $0.start < $1.start }
        var conflicts: [ScheduleConflict] = []

        // Overlapping commitments (personal events count, all-day release markers don't).
        let blocking = events.filter { $0.kind != .release && $0.kind != .deadline }
        for i in blocking.indices {
            for j in blocking.indices where j > i {
                let a = blocking[i], b = blocking[j]
                guard a.interval.intersects(b.interval) else { continue }
                // Touching end-to-start isn't an overlap.
                if a.interval.end == b.interval.start || b.interval.end == a.interval.start { continue }
                // Two all-day items only conflict if one of them is a show or travel.
                if a.isAllDay && b.isAllDay && ![EventKind.show, .travel].contains(a.kind) && ![EventKind.show, .travel].contains(b.kind) { continue }
                conflicts.append(ScheduleConflict(
                    id: "overlap-\(a.id)-\(b.id)", date: max(a.start, b.start),
                    title: "“\(a.title)” overlaps “\(b.title)”",
                    detail: "Both are scheduled at the same time. Move one or confirm you can do both.",
                    eventIDs: [a.id, b.id], taskIDs: []))
            }
        }

        // Work scheduled on blackout days or days the artist doesn't work.
        for event in events where event.kind != .personal && event.kind != .release {
            if let range = availability.blackoutDates.first(where: { $0.contains(event.start) }) {
                conflicts.append(ScheduleConflict(
                    id: "blackout-\(event.id)", date: event.start,
                    title: "“\(event.title)” is on a day you blocked off",
                    detail: range.reason.isBlank ? "You marked this date as unavailable." : "You marked this date as unavailable: \(range.reason).",
                    eventIDs: [event.id], taskIDs: []))
            } else if [EventKind.meeting, .press, .studio].contains(event.kind),
                      !availability.workDays.isEmpty, !availability.workDays.contains(event.start.weekday) {
                conflicts.append(ScheduleConflict(
                    id: "dayoff-\(event.id)", date: event.start,
                    title: "“\(event.title)” is on a day you don't usually work",
                    detail: "Check this still suits you, or update your availability in Profile.",
                    eventIDs: [event.id], taskIDs: []))
            }
        }

        // Task deadlines on blackout days, and releases with an event the same day as a show.
        for task in workspace.tasks where task.isOpen {
            guard let due = task.due, due >= start, due < end else { continue }
            if let range = availability.blackoutDates.first(where: { $0.contains(due) }) {
                conflicts.append(ScheduleConflict(
                    id: "task-blackout-\(task.id)", date: due,
                    title: "“\(task.title)” is due on a day you blocked off",
                    detail: range.reason.isBlank ? "Move the deadline or finish it earlier." : "Blocked: \(range.reason). Move the deadline or finish it earlier.",
                    eventIDs: [], taskIDs: [task.id]))
            }
        }
        return conflicts.sorted { $0.date < $1.date }
    }

    /// Hours of open tasks due in the next 7 days compared with weekly availability.
    static func workload(in workspace: Workspace, now: Date = Date()) -> (hoursDue: Double, hoursAvailable: Double) {
        let horizon = now.startOfDay.adding(days: 7)
        let due = workspace.tasks.filter { task in
            guard task.isOpen, let date = task.due else { return false }
            return date < horizon
        }
        return (due.reduce(0) { $0 + max($1.estimatedHours, 0) }, workspace.profile.availability.hoursPerWeek)
    }

    static func agenda(in workspace: Workspace, from start: Date, to end: Date) -> [AgendaItem] {
        var items: [AgendaItem] = []
        for event in workspace.events where event.interval.end > start && event.interval.start < end {
            items.append(AgendaItem(id: "event-\(event.id)", date: event.start, isAllDay: event.isAllDay, title: event.title,
                                    subtitle: [event.kind.label, event.location].filter { !$0.isBlank }.joined(separator: " · "),
                                    symbol: event.kind.symbol, source: .event(event.id)))
        }
        for task in workspace.tasks where task.isOpen {
            guard let due = task.due, due >= start.startOfDay, due < end else { continue }
            items.append(AgendaItem(id: "task-\(task.id)", date: due, isAllDay: true, title: task.title,
                                    subtitle: "Task due · \(task.area.label)", symbol: "checkmark.circle", source: .task(task.id)))
        }
        for release in workspace.releases where release.stage.isActive {
            guard let date = release.releaseDate, date >= start.startOfDay, date < end else { continue }
            let hasEvent = workspace.events.contains { $0.sourceKey == ReleaseTimeline.releaseDayKey(release.id) }
            if !hasEvent {
                items.append(AgendaItem(id: "release-\(release.id)", date: date, isAllDay: true, title: "Release day: \(release.title)",
                                        subtitle: release.type.label, symbol: "opticaldisc", source: .release(release.id)))
            }
        }
        for campaign in workspace.campaigns where campaign.status != .sent && campaign.status != .cancelled {
            guard let date = campaign.scheduledFor, date >= start.startOfDay, date < end else { continue }
            items.append(AgendaItem(id: "campaign-\(campaign.id)", date: date, isAllDay: false, title: "Email: \(campaign.name.isBlank ? campaign.subject : campaign.name)",
                                    subtitle: "Planned send · \(campaign.status.label)", symbol: "envelope", source: .campaign(campaign.id)))
        }
        for contact in workspace.contacts {
            guard let date = contact.nextFollowUp, date >= start.startOfDay, date < end else { continue }
            items.append(AgendaItem(id: "followup-\(contact.id)", date: date, isAllDay: true, title: "Follow up with \(contact.displayName)",
                                    subtitle: contact.followUpReason.isBlank ? contact.role.label : contact.followUpReason,
                                    symbol: "arrowshape.turn.up.right", source: .followUp(contact.id)))
        }
        return items.sorted { lhs, rhs in
            if lhs.date.startOfDay != rhs.date.startOfDay { return lhs.date < rhs.date }
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            return lhs.date < rhs.date
        }
    }
}

// MARK: - iCalendar (.ics)

enum ICalendar {
    private static let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    static func unescape(_ text: String) -> String {
        var result = ""
        var iterator = text.makeIterator()
        while let c = iterator.next() {
            if c == "\\", let next = iterator.next() {
                switch next {
                case "n", "N": result.append("\n")
                default: result.append(next)
                }
            } else {
                result.append(c)
            }
        }
        return result
    }

    /// Folds lines longer than 75 characters as RFC 5545 requires.
    private static func fold(_ line: String) -> String {
        guard line.count > 75 else { return line }
        var parts: [String] = []
        var current = ""
        for ch in line {
            if current.count >= 74 {
                parts.append(current)
                current = " "
            }
            current.append(ch)
        }
        parts.append(current)
        return parts.joined(separator: "\r\n")
    }

    static let uidSuffix = "@artistmanager"

    /// Imported events keep their original UID so other calendar apps update rather than duplicate them.
    static func exportUID(for event: CalendarEvent) -> String {
        if let key = event.sourceKey, key.hasPrefix("ics:"), key.count > 4 { return String(key.dropFirst(4)) }
        return "\(event.id.uuidString)\(uidSuffix)"
    }

    static func export(_ events: [CalendarEvent], calendarName: String) -> String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Manager//EN", "CALSCALE:GREGORIAN",
                     "X-WR-CALNAME:\(escape(calendarName))"]
        let stamp = utcFormatter.string(from: Date())
        for event in events {
            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(exportUID(for: event))")
            lines.append("DTSTAMP:\(stamp)")
            if event.isAllDay {
                lines.append("DTSTART;VALUE=DATE:\(dateFormatter.string(from: event.start))")
                let endDay = max(event.end.startOfDay, event.start.startOfDay).adding(days: 1)
                lines.append("DTEND;VALUE=DATE:\(dateFormatter.string(from: endDay))")
            } else {
                lines.append("DTSTART:\(utcFormatter.string(from: event.start))")
                lines.append("DTEND:\(utcFormatter.string(from: max(event.end, event.start)))")
            }
            lines.append("SUMMARY:\(escape(event.title))")
            if !event.location.isBlank { lines.append("LOCATION:\(escape(event.location))") }
            let description = [event.kind.label, event.notes].filter { !$0.isBlank }.joined(separator: "\n")
            if !description.isBlank { lines.append("DESCRIPTION:\(escape(description))") }
            lines.append("CATEGORIES:\(escape(event.kind.label))")
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    struct ParsedEvent: Equatable {
        var uid = ""
        var title = ""
        var start: Date?
        var end: Date?
        var isAllDay = false
        var location = ""
        var notes = ""
    }

    static func parse(_ text: String) -> [ParsedEvent] {
        // Unfold continuation lines (start with a space or tab).
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for raw in normalized.components(separatedBy: "\n") {
            if (raw.hasPrefix(" ") || raw.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1] += String(raw.dropFirst())
            } else {
                lines.append(raw)
            }
        }
        var events: [ParsedEvent] = []
        var current: ParsedEvent?
        for line in lines {
            if line == "BEGIN:VEVENT" { current = ParsedEvent(); continue }
            if line == "END:VEVENT" {
                if let event = current, event.start != nil { events.append(event) }
                current = nil
                continue
            }
            guard current != nil, let colon = line.firstIndex(of: ":") else { continue }
            let nameAndParams = String(line[..<colon])
            let value = String(line[line.index(after: colon)...])
            let pieces = nameAndParams.split(separator: ";").map(String.init)
            let name = pieces.first?.uppercased() ?? ""
            let params = Dictionary(pieces.dropFirst().compactMap { piece -> (String, String)? in
                let kv = piece.split(separator: "=", maxSplits: 1).map(String.init)
                return kv.count == 2 ? (kv[0].uppercased(), kv[1]) : nil
            }, uniquingKeysWith: { first, _ in first })
            switch name {
            case "UID": current?.uid = value
            case "SUMMARY": current?.title = unescape(value)
            case "LOCATION": current?.location = unescape(value)
            case "DESCRIPTION": current?.notes = unescape(value)
            case "DTSTART":
                let parsed = parseDate(value, params: params)
                current?.start = parsed.date
                current?.isAllDay = parsed.allDay
            case "DTEND":
                current?.end = parseDate(value, params: params).date
            default: break
            }
        }
        return events
    }

    static func parseDate(_ value: String, params: [String: String]) -> (date: Date?, allDay: Bool) {
        let v = value.trimmed
        if params["VALUE"]?.uppercased() == "DATE" || (v.count == 8 && v.allSatisfy(\.isNumber)) {
            return (dateFormatter.date(from: v), true)
        }
        if v.hasSuffix("Z") { return (utcFormatter.date(from: v), false) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        if let tzid = params["TZID"], let zone = TimeZone(identifier: tzid.trimmingCharacters(in: CharacterSet(charactersIn: "\""))) {
            f.timeZone = zone
        } else {
            f.timeZone = TimeZone.current
        }
        return (f.date(from: v), false)
    }

    /// Converts parsed events to calendar events, skipping any already imported (same UID).
    static func calendarEvents(from parsed: [ParsedEvent], existing: [CalendarEvent]) -> [CalendarEvent] {
        // An event exported from Manager and imported back matches its original by UID.
        var existingKeys = Set(existing.compactMap(\.sourceKey))
        for event in existing { existingKeys.insert("ics:" + exportUID(for: event)) }
        var result: [CalendarEvent] = []
        for p in parsed {
            guard let start = p.start else { continue }
            let key = p.uid.isBlank ? nil : "ics:\(p.uid)"
            if let key, existingKeys.contains(key) { continue }
            if let key { existingKeys.insert(key) }
            var end = p.end ?? (p.isAllDay ? start : start.adding(hours: 1))
            if p.isAllDay, let pEnd = p.end {
                // iCalendar all-day DTEND is exclusive.
                end = max(start, pEnd.adding(days: -1))
            }
            result.append(CalendarEvent(title: p.title.isBlank ? "Untitled event" : p.title, kind: .other, start: start,
                                        end: end, isAllDay: p.isAllDay, location: p.location, notes: p.notes,
                                        createdBy: .importer, sourceKey: key))
        }
        return result
    }
}
