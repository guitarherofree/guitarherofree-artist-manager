import Foundation

// MARK: - Contacts and media lists (CSV)

struct ContactImportPreview {
    var totalRows = 0
    var added: [Contact] = []
    var updated: [Contact] = []
    var skipped: [String] = []
    var recognizedColumns: [String] = []

    var hasChanges: Bool { !added.isEmpty || !updated.isEmpty }
}

enum ContactCSV {
    static let headers = ["name", "organization", "role", "email", "phone", "website", "location", "tags",
                          "team_member", "responsibilities", "next_follow_up", "follow_up_reason", "notes"]

    static let nameKeys = ["name", "full_name", "contact", "contact_name"]
    static let firstNameKeys = ["first_name", "firstname", "first"]
    static let lastNameKeys = ["last_name", "lastname", "last", "surname"]
    static let organizationKeys = ["organization", "organisation", "company", "outlet", "publication", "playlist", "venue", "station"]
    static let roleKeys = ["role", "type", "category", "title"]
    static let emailKeys = SubscriberImporter.emailKeys
    static let phoneKeys = ["phone", "phone_number", "mobile", "tel"]
    static let websiteKeys = ["website", "url", "link", "site"]
    static let locationKeys = ["location", "city", "market", "region"]
    static let tagKeys = ["tags", "tag", "genres", "lists"]
    static let notesKeys = ["notes", "note", "comments"]

    static var knownKeys: Set<String> {
        Set(headers + nameKeys + firstNameKeys + lastNameKeys + organizationKeys + roleKeys + emailKeys + phoneKeys
            + websiteKeys + locationKeys + tagKeys + notesKeys)
    }

    static func export(_ contacts: [Contact]) -> String {
        let rows = contacts.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }.map { c -> [String] in
            [c.name, c.organization, c.role.label, c.email, c.phone, c.website, c.location, c.tags.commaJoined,
             c.isTeamMember ? "yes" : "no", c.responsibilities, DateParsing.iso(c.nextFollowUp), c.followUpReason, c.notes]
        }
        return CSV.write(headers: headers, rows: rows)
    }

    /// Matches a role column against the app's role names and common synonyms.
    static func role(from raw: String) -> ContactRole? {
        let value = raw.trimmed.lowercased()
        guard !value.isEmpty else { return nil }
        if let exact = ContactRole.allCases.first(where: { $0.rawValue.lowercased() == value || $0.label.lowercased() == value }) {
            return exact
        }
        let synonyms: [(String, ContactRole)] = [
            ("journalist", .journalist), ("writer", .journalist), ("editor", .journalist), ("blog", .journalist), ("press", .journalist),
            ("curator", .playlistCurator), ("playlist", .playlistCurator),
            ("radio", .radio), ("dj", .radio), ("station", .radio),
            ("booking", .bookingAgent), ("agent", .bookingAgent),
            ("promoter", .promoter), ("talent buyer", .promoter), ("buyer", .promoter),
            ("venue", .venue), ("club", .venue),
            ("lawyer", .attorney), ("attorney", .attorney), ("legal", .attorney),
            ("accountant", .accountant), ("cpa", .accountant), ("bookkeeper", .accountant),
            ("publicist", .publicist), ("pr", .publicist),
            ("label", .label), ("a&r", .label),
            ("publisher", .publisher), ("publishing", .publisher),
            ("distributor", .distributor),
            ("music supervisor", .musicSupervisor), ("supervisor", .musicSupervisor),
            ("sync", .syncAgent),
            ("brand", .brand), ("sponsor", .brand),
            ("producer", .producer), ("engineer", .engineer), ("mix", .engineer), ("master", .engineer),
            ("photographer", .photographer), ("videographer", .videographer), ("director", .videographer),
            ("designer", .designer), ("manager", .manager), ("musician", .musician), ("band", .musician)
        ]
        return synonyms.first(where: { value.contains($0.0) })?.1
    }

    static func preview(csv text: String, existing: [Contact], defaultRole: ContactRole, tagsToAdd: [String],
                        markAsTeam: Bool = false) -> ContactImportPreview {
        let table = CSV.parseTable(text)
        var candidates: [(label: String, contact: Contact)] = []
        var skipped: [String] = []
        for (index, row) in table.rows.enumerated() {
            var name = CSV.value(row, nameKeys)
            if name.isBlank {
                name = [CSV.value(row, firstNameKeys), CSV.value(row, lastNameKeys)].filter { !$0.isBlank }.joined(separator: " ")
            }
            var incoming = Contact()
            incoming.name = name
            incoming.organization = CSV.value(row, organizationKeys)
            incoming.email = CSV.value(row, emailKeys)
            if incoming.name.isBlank && incoming.organization.isBlank && incoming.email.isBlank {
                skipped.append("Row \(index + 2): no name, organization or email")
                continue
            }
            incoming.role = role(from: CSV.value(row, roleKeys)) ?? defaultRole
            incoming.phone = CSV.value(row, phoneKeys)
            incoming.website = CSV.value(row, websiteKeys)
            incoming.location = CSV.value(row, locationKeys)
            incoming.tags = CSV.value(row, tagKeys).commaSeparatedValues
            incoming.isTeamMember = ["yes", "true", "1", "y"].contains(CSV.value(row, ["team_member", "team"]).lowercased())
            incoming.responsibilities = CSV.value(row, ["responsibilities"])
            incoming.nextFollowUp = DateParsing.parse(CSV.value(row, ["next_follow_up", "follow_up"]))
            incoming.followUpReason = CSV.value(row, ["follow_up_reason"])
            incoming.notes = CSV.value(row, notesKeys)
            candidates.append(("Row \(index + 2)", incoming))
        }
        var preview = ContactImport.merge(candidates, existing: existing, tagsToAdd: tagsToAdd, markAsTeam: markAsTeam)
        preview.totalRows = table.rows.count
        preview.skipped = skipped + preview.skipped
        preview.recognizedColumns = table.headers.filter { knownKeys.contains($0) }
        return preview
    }

    static func apply(_ preview: ContactImportPreview, to contacts: inout [Contact]) {
        ContactImport.apply(preview, to: &contacts)
    }

}

// MARK: - Merging imported contacts (CSV, vCard, the Contacts app)

enum ContactImport {
    static func nameKey(_ name: String, _ organization: String) -> String {
        "\(name.trimmed.lowercased())|\(organization.trimmed.lowercased())"
    }

    /// Matches each candidate to an existing contact by email, then by name and organization.
    /// Matches are only filled in, never overwritten; everything else is added.
    static func merge(_ candidates: [(label: String, contact: Contact)], existing: [Contact], tagsToAdd: [String],
                      markAsTeam: Bool, defaultRole: ContactRole? = nil) -> ContactImportPreview {
        var preview = ContactImportPreview()
        preview.totalRows = candidates.count
        var byEmail: [String: Contact] = [:]
        var byName: [String: Contact] = [:]
        for c in existing {
            if !c.email.isBlank { byEmail[EmailAddress.normalize(c.email)] = c }
            byName[nameKey(c.name, c.organization)] = c
        }
        var updatedByID: [UUID: Int] = [:]
        var seen = Set<String>()

        for (label, candidate) in candidates {
            var incoming = candidate
            let rawEmail = incoming.email
            incoming.email = rawEmail.isBlank ? "" : EmailAddress.normalize(rawEmail)
            if incoming.name.isBlank && incoming.organization.isBlank && incoming.email.isBlank {
                preview.skipped.append("\(label): no name, organization or email")
                continue
            }
            if !incoming.email.isBlank && !EmailAddress.isValid(incoming.email) {
                preview.skipped.append("\(label): “\(rawEmail)” isn't a valid email address")
                continue
            }
            let key = incoming.email.isBlank ? nameKey(incoming.name, incoming.organization) : incoming.email
            if seen.contains(key) {
                preview.skipped.append("\(label): duplicate of an earlier entry")
                continue
            }
            seen.insert(key)
            if let defaultRole, incoming.role == .other { incoming.role = defaultRole }
            for tag in tagsToAdd where !incoming.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                incoming.tags.append(tag)
            }
            if markAsTeam { incoming.isTeamMember = true }

            let match = (incoming.email.isBlank ? nil : byEmail[incoming.email]) ?? byName[nameKey(incoming.name, incoming.organization)]
            if let found = match {
                var current = updatedByID[found.id].map { preview.updated[$0] } ?? found
                let before = current
                if current.name.isBlank { current.name = incoming.name }
                if current.organization.isBlank { current.organization = incoming.organization }
                if current.email.isBlank { current.email = incoming.email }
                if current.phone.isBlank { current.phone = incoming.phone }
                if current.website.isBlank { current.website = incoming.website }
                if current.location.isBlank { current.location = incoming.location }
                if current.responsibilities.isBlank { current.responsibilities = incoming.responsibilities }
                if current.notes.isBlank { current.notes = incoming.notes }
                if current.nextFollowUp == nil { current.nextFollowUp = incoming.nextFollowUp }
                if current.followUpReason.isBlank { current.followUpReason = incoming.followUpReason }
                if incoming.isTeamMember { current.isTeamMember = true }
                for tag in incoming.tags where !current.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                    current.tags.append(tag)
                }
                if current != before {
                    if let i = updatedByID[found.id] { preview.updated[i] = current } else {
                        updatedByID[found.id] = preview.updated.count
                        preview.updated.append(current)
                    }
                }
            } else {
                incoming.id = UUID()
                incoming.createdAt = Date()
                preview.added.append(incoming)
            }
        }
        return preview
    }

    static func apply(_ preview: ContactImportPreview, to contacts: inout [Contact]) {
        for updated in preview.updated {
            if let i = contacts.firstIndex(where: { $0.id == updated.id }) { contacts[i] = updated }
        }
        contacts.append(contentsOf: preview.added)
    }
}

/// Reads vCard (.vcf) files, as exported by Apple Contacts, Google Contacts, Outlook and most phones.
enum VCard {
    struct Property {
        var name: String
        var params: [String: String]
        var types: Set<String>
        var value: String
    }

    static func cards(_ text: String) -> [[Property]] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for raw in normalized.components(separatedBy: "\n") {
            if (raw.hasPrefix(" ") || raw.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1] += String(raw.dropFirst())
            } else if let last = lines.last, last.uppercased().contains("QUOTED-PRINTABLE"), last.hasSuffix("=") {
                lines[lines.count - 1] = String(last.dropLast()) + raw
            } else {
                lines.append(raw)
            }
        }
        var cards: [[Property]] = []
        var current: [Property]?
        for line in lines {
            let upper = line.trimmed.uppercased()
            if upper == "BEGIN:VCARD" { current = []; continue }
            if upper == "END:VCARD" {
                if let card = current { cards.append(card) }
                current = nil
                continue
            }
            guard current != nil, let property = parseLine(line) else { continue }
            current?.append(property)
        }
        return cards
    }

    private static func parseLine(_ line: String) -> Property? {
        var inQuotes = false
        var colon: String.Index?
        for i in line.indices {
            let c = line[i]
            if c == "\"" { inQuotes.toggle() }
            if c == ":" && !inQuotes { colon = i; break }
        }
        guard let colon else { return nil }
        let head = String(line[..<colon])
        var value = String(line[line.index(after: colon)...])
        var pieces = head.split(separator: ";").map(String.init)
        guard !pieces.isEmpty else { return nil }
        var name = pieces.removeFirst().uppercased()
        if let dot = name.lastIndex(of: ".") { name = String(name[name.index(after: dot)...]) } // "item1.EMAIL"
        var params: [String: String] = [:]
        var types = Set<String>()
        for piece in pieces {
            let kv = piece.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 {
                let key = kv[0].uppercased()
                let val = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                params[key] = val
                if key == "TYPE" { for t in val.split(separator: ",") { types.insert(t.uppercased()) } }
            } else {
                types.insert(piece.uppercased()) // vCard 2.1: "TEL;WORK;VOICE:"
            }
        }
        if params["ENCODING"]?.uppercased() == "QUOTED-PRINTABLE" { value = decodeQuotedPrintable(value) }
        if types.contains("PREF") || params["PREF"] != nil { types.insert("PREF") }
        return Property(name: name, params: params, types: types, value: value)
    }

    static func decodeQuotedPrintable(_ text: String) -> String {
        var bytes: [UInt8] = []
        let utf8 = Array(text.utf8)
        var i = 0
        while i < utf8.count {
            if utf8[i] == UInt8(ascii: "="), i + 2 < utf8.count,
               let byte = UInt8(String(decoding: utf8[(i + 1)...(i + 2)], as: UTF8.self), radix: 16) {
                bytes.append(byte)
                i += 3
            } else {
                bytes.append(utf8[i])
                i += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Splits on separators that aren't escaped with a backslash, then unescapes each part.
    static func components(_ value: String, separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var escaping = false
        for c in value {
            if escaping {
                switch c {
                case "n", "N": current.append("\n")
                default: current.append(c)
                }
                escaping = false
            } else if c == "\\" {
                escaping = true
            } else if c == separator {
                parts.append(current)
                current = ""
            } else {
                current.append(c)
            }
        }
        parts.append(current)
        return parts.map { $0.trimmed }
    }

    static func unescape(_ value: String) -> String {
        components(value, separator: "\u{0}").joined()
    }

    /// The contacts in a vCard file, ready to merge. Title or role maps to a contact role where it can.
    static func contacts(from text: String, defaultRole: ContactRole) -> [Contact] {
        cards(text).compactMap { props in
            func all(_ name: String) -> [Property] { props.filter { $0.name == name } }
            func best(_ name: String) -> Property? { all(name).first { $0.types.contains("PREF") } ?? all(name).first }
            var c = Contact()
            c.name = best("FN").map { unescape($0.value) } ?? ""
            if c.name.isBlank, let n = best("N") {
                let parts = components(n.value, separator: ";")
                let given = parts.count > 1 ? parts[1] : ""
                let family = parts.first ?? ""
                c.name = [given, family].filter { !$0.isBlank }.joined(separator: " ")
            }
            if let org = best("ORG") { c.organization = components(org.value, separator: ";").first ?? "" }
            if c.name == c.organization { c.name = "" } // company-only cards repeat the company as FN
            c.email = best("EMAIL").map { unescape($0.value) } ?? ""
            c.phone = best("TEL").map { unescape($0.value) } ?? ""
            c.website = best("URL").map { unescape($0.value) } ?? ""
            if let adr = best("ADR") {
                let parts = components(adr.value, separator: ";")
                func part(_ i: Int) -> String { i < parts.count ? parts[i] : "" }
                c.location = [part(3), part(4)].filter { !$0.isBlank }.joined(separator: ", ")
                if c.location.isBlank { c.location = part(6) }
            }
            let title = [best("TITLE"), best("ROLE")].compactMap { $0 }.map { unescape($0.value) }.first { !$0.isBlank } ?? ""
            c.role = ContactCSV.role(from: title) ?? defaultRole
            var notes: [String] = []
            if !title.isBlank { notes.append("Title: \(title)") }
            if let note = best("NOTE") { notes.append(unescape(note.value)) }
            c.notes = notes.joined(separator: "\n")
            if let categories = best("CATEGORIES") {
                c.tags = components(categories.value, separator: ",").filter { !$0.isBlank }
            }
            return (c.name.isBlank && c.organization.isBlank && c.email.isBlank) ? nil : c
        }
    }

    static func preview(vcf text: String, existing: [Contact], defaultRole: ContactRole, tagsToAdd: [String],
                        markAsTeam: Bool = false) -> ContactImportPreview {
        let found = contacts(from: text, defaultRole: defaultRole)
        var preview = ContactImport.merge(found.map { (label: $0.displayName, contact: $0) }, existing: existing,
                                          tagsToAdd: tagsToAdd, markAsTeam: markAsTeam)
        preview.totalRows = cards(text).count
        return preview
    }
}

// MARK: - Release metadata (for distributors and rights registrations)

enum ReleaseExport {
    static func duration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// One row per track with the fields distributors ask for.
    static func metadataCSV(_ release: Release, artistName: String) -> String {
        let headers = ["artist", "release_title", "release_type", "release_date", "upc", "label", "distributor", "primary_genre",
                       "track_number", "track_title", "version", "isrc", "iswc", "duration", "explicit",
                       "featured_artists", "producers", "songwriters"]
        let base = [artistName, release.title, release.type.label, release.releaseDate.map(dayString) ?? "", release.upc,
                    release.label, release.distributor, release.primaryGenre]
        let rows = release.tracks.enumerated().map { index, track -> [String] in
            let writers = track.writers.map { w in
                "\(w.name) (\(w.role)) \(w.share.formatted(.number.precision(.fractionLength(0...2))))%"
            }.joined(separator: "; ")
            return base + [String(index + 1), track.title, track.version, track.isrc, track.iswc, duration(track.durationSeconds),
                           track.explicit ? "yes" : "no", track.featuredArtists, track.producers, writers]
        }
        return CSV.write(headers: headers, rows: rows)
    }

    /// One row per songwriter per track, for PRO and mechanical registrations.
    static func splitsCSV(_ release: Release) -> String {
        let headers = ["track_title", "isrc", "iswc", "songwriter", "role", "share_percent", "pro", "ipi"]
        var rows: [[String]] = []
        for track in release.tracks {
            for w in track.writers {
                rows.append([track.title, track.isrc, track.iswc, w.name, w.role,
                             w.share.formatted(.number.precision(.fractionLength(0...2))), w.pro, w.ipi])
            }
        }
        return CSV.write(headers: headers, rows: rows)
    }

    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// MARK: - Email campaign hand-off to an email provider

enum CampaignExport {
    /// Footer lines the artist's provider should keep: who it's from, the mailing address, and the unsubscribe link.
    static func footer(_ profile: ArtistProfile) -> String {
        var lines = ["You're getting this because you signed up for updates from \(profile.displayName)."]
        if !profile.communication.mailingAddress.isBlank { lines.append(profile.communication.mailingAddress) }
        lines.append("[Unsubscribe link — use your email provider's unsubscribe merge tag here]")
        return lines.joined(separator: "\n")
    }

    static func plainText(_ campaign: EmailCampaign, profile: ArtistProfile) -> String {
        var parts = ["Subject: \(campaign.subject)"]
        if !campaign.preheader.isBlank { parts.append("Preview text: \(campaign.preheader)") }
        parts.append("")
        parts.append(campaign.body)
        parts.append("")
        parts.append("—")
        parts.append(footer(profile))
        return parts.joined(separator: "\n") + "\n"
    }

    static func html(_ campaign: EmailCampaign, profile: ArtistProfile) -> String {
        let body = PressKitRenderer.paragraphs(campaign.body)
        let footerHTML = PressKitRenderer.paragraphs(footer(profile).replacingOccurrences(of: "\n", with: "\n\n"))
        let preheader = campaign.preheader.isBlank ? "" :
            "<div style=\"display:none;max-height:0;overflow:hidden\">\(PressKitRenderer.html(campaign.preheader))</div>"
        return """
        <!DOCTYPE html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(PressKitRenderer.html(campaign.subject))</title></head>
        <body style="margin:0;padding:0;background:#ffffff;color:#1d1d1f;font:16px/1.6 -apple-system,Helvetica,Arial,sans-serif">
        \(preheader)
        <div style="max-width:600px;margin:0 auto;padding:32px 20px">
        \(body)
        <hr style="border:none;border-top:1px solid #d2d2d7;margin:32px 0">
        <div style="color:#6e6e73;font-size:13px">\(footerHTML)</div>
        </div></body></html>
        """
    }
}

// MARK: - Conversation and statement preparation

enum ConversationPrep {
    /// A prep outline for a conversation with a contact, pulled from what Manager knows about them.
    static func outline(for contact: Contact, purpose: String, workspace ws: Workspace, now: Date = Date()) -> String {
        var out: [String] = []
        out.append("Conversation with \(contact.displayName)\(contact.organization.isBlank || contact.name.isBlank ? "" : " (\(contact.organization))")")
        out.append("Purpose: \(purpose.isBlank ? "[What do you need from this conversation?]" : purpose)")

        var context = ["Role: \(contact.role.label)\(contact.isTeamMember ? " — on your team" : "")"]
        if !contact.responsibilities.isBlank { context.append("Handles: \(contact.responsibilities)") }
        if let last = contact.lastContacted {
            context.append("Last contact: \(last.formatted(date: .abbreviated, time: .omitted)) (\(max(Date.daysBetween(last, now), 0)) days ago)")
        } else {
            context.append("No conversations logged yet.")
        }
        for interaction in contact.interactions.sorted(by: { $0.date > $1.date }).prefix(3) {
            context.append("\(interaction.date.formatted(date: .abbreviated, time: .omitted)) · \(interaction.channel.label): \(interaction.summary)")
        }
        let outreach = ws.outreach.filter { $0.contactID == contact.id }.sorted { $0.createdAt > $1.createdAt }
        for item in outreach.prefix(3) {
            context.append("\(item.kind.label): “\(item.subject)” — \(item.status.label)")
        }
        let openTasks = ws.tasks.filter { $0.contactID == contact.id && $0.isOpen }
        for task in openTasks.prefix(3) {
            context.append("Open task: \(task.title)\(task.due.map { " (due \($0.formatted(date: .abbreviated, time: .omitted)))" } ?? "")")
        }
        if !contact.notes.isBlank { context.append("Your notes: \(contact.notes)") }
        out.append("CONTEXT\n" + context.map { "• \($0)" }.joined(separator: "\n"))

        out.append("""
        BEFORE YOU START
        • The one outcome you want: [ ]
        • What you can offer or agree to: [ ]
        • Your limits — what you won't agree to today: [ ]
        • Facts or numbers to have in front of you: [ ]
        """)
        out.append("""
        DURING
        • Open with the purpose, then listen first.
        • Ask open questions: “What would make this work for you?”
        • If it gets tense, restate what you heard before answering, and it's fine to ask for time: “Let me think about that and get back to you by [day].”
        • Don't agree to money, dates or terms on the spot if you need to check them. Manager will ask for your approval before any commitment is recorded.
        """)
        out.append("""
        AFTER
        • Log the conversation on this contact.
        • Set a follow-up date for anything left open.
        • Send a short written recap of what was agreed.
        """)
        return out.joined(separator: "\n\n")
    }

    /// A framework for responding to a public relations issue. Drafting only — publishing always needs approval.
    static func statementOutline(topic: String, profile: ArtistProfile) -> String {
        let name = profile.displayName
        let team = profile.isUnitedStates ? "your publicist or attorney" : "your publicist or legal adviser"
        return """
        Public statement prep — \(topic.isBlank ? "[the issue]" : topic)

        1. FACTS FIRST
        • What happened, in one or two sentences, with only what you know for certain: [ ]
        • What you don't know yet: [ ]
        • Who is affected: [ ]

        2. DECIDE WHETHER TO SPEAK
        • Is this being discussed beyond a few posts? Will silence be read as an answer?
        • Does anything here have legal or contractual implications? If so, talk to \(team) before posting.

        3. HOLDING STATEMENT (if you need time)
        “We're aware of [the issue]. We take it seriously and are looking into it. We'll share more by [day].” — \(name)

        4. FULL STATEMENT OUTLINE
        • Acknowledge the issue plainly, without minimizing it.
        • Take responsibility for your part, if you have one.
        • Say what you're doing about it, and by when.
        • Keep it short. Don't speculate, blame others, or argue with individual comments.

        5. AFTER
        • Agree who answers press questions, and point everyone else to the statement.
        • Note it in your press log and set a follow-up check.

        Nothing is published from Manager. Post it yourself once you've approved the wording.
        """
    }
}
