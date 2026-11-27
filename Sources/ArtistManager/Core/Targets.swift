import Foundation

// MARK: - Model

/// A publication, label, station, playlist or other organization the artist wants to reach or keep an eye on.
enum TargetKind: String, Codable, CaseIterable, Identifiable {
    case publication, label, radio, podcast, playlist, festival, agency, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .publication: return "Publication / blog"
        case .label: return "Record label"
        case .radio: return "Radio station or show"
        case .podcast: return "Podcast"
        case .playlist: return "Playlist / curator"
        case .festival: return "Festival"
        case .agency: return "Agency (booking, PR, sync)"
        case .other: return "Other"
        }
    }
    var shortLabel: String {
        switch self {
        case .publication: return "Publication"
        case .label: return "Label"
        case .radio: return "Radio"
        case .podcast: return "Podcast"
        case .playlist: return "Playlist"
        case .festival: return "Festival"
        case .agency: return "Agency"
        case .other: return "Other"
        }
    }
    var pluralLabel: String {
        switch self {
        case .publication: return "publications"
        case .label: return "labels"
        case .radio: return "radio"
        case .podcast: return "podcasts"
        case .playlist: return "playlists"
        case .festival: return "festivals"
        case .agency: return "agencies"
        case .other: return "others"
        }
    }
    var symbol: String {
        switch self {
        case .publication: return "newspaper"
        case .label: return "opticaldisc"
        case .radio: return "radio"
        case .podcast: return "headphones"
        case .playlist: return "music.note.list"
        case .festival: return "tent"
        case .agency: return "briefcase"
        case .other: return "star"
        }
    }
    /// Outlets that write about, play or playlist music, so coverage can come from them.
    var isMedia: Bool { [.publication, .radio, .podcast, .playlist].contains(self) }
    /// The contact role someone who works there usually has.
    var contactRole: ContactRole {
        switch self {
        case .publication, .podcast: return .journalist
        case .label: return .label
        case .radio: return .radio
        case .playlist: return .playlistCurator
        case .festival: return .promoter
        case .agency: return .bookingAgent
        case .other: return .other
        }
    }
    /// The pitch Manager drafts to someone there.
    var pitchKind: OutreachKind {
        switch self {
        case .publication, .podcast: return .press
        case .label: return .label
        case .radio: return .radio
        case .playlist: return .playlist
        case .festival: return .booking
        case .agency, .other: return .general
        }
    }
}

enum TargetStatus: String, Codable, CaseIterable, Identifiable {
    case watching, researching, ready, pitched, talking, won, notNow
    var id: String { rawValue }

    func label(for kind: TargetKind) -> String {
        switch self {
        case .watching: return "Keeping an eye on"
        case .researching: return "Researching"
        case .ready: return "Ready to pitch"
        case .pitched: return "Pitched"
        case .talking: return "In conversation"
        case .won:
            switch kind {
            case .publication, .podcast: return "Covered you"
            case .radio: return "Played you"
            case .playlist: return "Added you"
            case .label: return "Working together"
            case .festival: return "Booked"
            case .agency, .other: return "Working together"
            }
        case .notNow: return "Not right now"
        }
    }

    /// How far along the relationship is, for comparing statuses.
    var rank: Int {
        switch self {
        case .watching: return 0
        case .researching: return 1
        case .ready: return 2
        case .pitched: return 3
        case .talking: return 4
        case .won: return 5
        case .notNow: return -1
        }
    }

    var isOpen: Bool { self != .won && self != .notNow }
}

enum TargetTier: String, Codable, CaseIterable, Identifiable {
    case dream, stretch, realistic
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dream: return "Dream"
        case .stretch: return "Stretch"
        case .realistic: return "Good fit now"
        }
    }
    var order: Int {
        switch self {
        case .realistic: return 0
        case .stretch: return 1
        case .dream: return 2
        }
    }
}

enum SubmissionPolicy: String, Codable, CaseIterable, Identifiable {
    case unknown, open, closed, referral
    var id: String { rawValue }
    var label: String {
        switch self {
        case .unknown: return "Not sure yet"
        case .open: return "Takes submissions"
        case .closed: return "Not taking submissions"
        case .referral: return "Referral or invitation only"
        }
    }
}

struct Target: Entity {
    var id = UUID()
    var name = ""
    var kind: TargetKind = .publication
    var status: TargetStatus = .watching
    var tier: TargetTier = .realistic
    var website = ""
    /// Where they take submissions: a form, SubmitHub or Groover page, or a guidelines page.
    var submissionURL = ""
    var submissionEmail = ""
    var submissionPolicy: SubmissionPolicy = .unknown
    /// Their submission rules in the artist's words: format, lead time, what not to send.
    var guidelines = ""
    var genres: [String] = []
    var location = ""
    /// Artists they cover, play or sign that the artist sounds like.
    var similarArtists = ""
    var notes = ""
    var tags: [String] = []
    /// Contacts linked by hand. People whose organization matches are found automatically.
    var contactIDs: [UUID] = []
    /// When to look at them again: a submission window, a new issue, a roster announcement.
    var nextCheck: Date? = nil
    var lastChecked: Date? = nil
    var createdAt: Date? = nil

    var displayName: String { name.isBlank ? "Untitled target" : name }
}

// MARK: - Connecting targets to everything else

/// What has happened with a target, worked out from contacts, pitches and coverage.
struct TargetActivity {
    var contacts: [Contact] = []
    var pitches: [Outreach] = []
    var coverage: [Coverage] = []
    /// A later status the activity points to, offered to the artist rather than applied.
    var suggestedStatus: TargetStatus?
    var lastPitch: Date? { pitches.compactMap { $0.sentAt ?? $0.approvedAt }.max() }
    var reachable: [Contact] { contacts.filter { !$0.email.isBlank } }
}

enum Targets {
    /// Hosts shared by many outlets, which say nothing about which outlet a link belongs to.
    static let sharedHosts: Set<String> = ["youtube.com", "youtu.be", "open.spotify.com", "spotify.com", "music.apple.com",
                                           "podcasts.apple.com", "apple.com", "soundcloud.com", "bandcamp.com", "instagram.com",
                                           "tiktok.com", "facebook.com", "x.com", "twitter.com", "substack.com", "medium.com",
                                           "linktr.ee", "submithub.com", "groover.co", "google.com", "docs.google.com",
                                           "forms.gle", "tumblr.com", "wordpress.com", "blogspot.com", "mixcloud.com"]
    /// Free mail providers: an address there doesn't tie a person to an organization.
    static let personalMailDomains: Set<String> = ["gmail.com", "googlemail.com", "yahoo.com", "hotmail.com", "outlook.com",
                                                   "icloud.com", "me.com", "mac.com", "aol.com", "proton.me", "protonmail.com",
                                                   "live.com", "msn.com", "gmx.com", "fastmail.com", "hey.com"]

    static func squashed(_ text: String) -> String {
        var t = text.lowercased()
        if t.hasPrefix("the ") { t.removeFirst(4) }
        return String(t.filter { $0.isLetter || $0.isNumber })
    }

    /// "https://www.TheLantern.example/reviews" → "thelantern.example". Nil for shared platforms.
    static func host(_ raw: String) -> String? {
        var text = raw.trimmed
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http") { text = "https://" + text }
        guard var host = URL(string: text)?.host?.lowercased(), host.contains(".") else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return sharedHosts.contains(host) ? nil : host
    }

    /// "thelantern.example/reviews?x" → "https://thelantern.example".
    static func siteRoot(_ raw: String) -> String {
        var text = raw.trimmed
        guard !text.isEmpty else { return "" }
        if !text.lowercased().hasPrefix("http") { text = "https://" + text }
        guard let components = URLComponents(string: text), let scheme = components.scheme, let host = components.host else { return raw.trimmed }
        return "\(scheme)://\(host)"
    }

    static func sameName(_ a: String, _ b: String) -> Bool {
        let x = squashed(a), y = squashed(b)
        return !x.isEmpty && x == y
    }

    static func contacts(for t: Target, in contacts: [Contact]) -> [Contact] {
        let site = host(t.website)
        return contacts.filter { c in
            if t.contactIDs.contains(c.id) { return true }
            if sameName(c.organization, t.name) { return true }
            if let site {
                if host(c.website) == site { return true }
                let domain = c.email.split(separator: "@").last.map { String($0).lowercased() } ?? ""
                if !domain.isEmpty, !personalMailDomains.contains(domain), domain == site || domain.hasSuffix("." + site) { return true }
            }
            return false
        }
    }

    static func coverage(for t: Target, in coverage: [Coverage]) -> [Coverage] {
        let site = host(t.website)
        return coverage.filter { c in
            sameName(c.outlet, t.name) || (site != nil && host(c.url) == site)
        }
    }

    static func activity(for t: Target, in ws: Workspace) -> TargetActivity {
        var a = TargetActivity()
        a.contacts = contacts(for: t, in: ws.contacts)
        let ids = Set(a.contacts.map(\.id))
        let happened: Set<OutreachStatus> = [.sent, .replied, .covered, .declined, .noResponse]
        a.pitches = ws.outreach.filter { o in o.contactID.map(ids.contains) == true && happened.contains(o.status) }
            .sorted { ($0.sentAt ?? .distantPast) > ($1.sentAt ?? .distantPast) }
        a.coverage = coverage(for: t, in: ws.coverage).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        a.suggestedStatus = suggestedStatus(for: t, activity: a)
        return a
    }

    private static func suggestedStatus(for t: Target, activity a: TargetActivity) -> TargetStatus? {
        guard t.status != .notNow else { return nil }
        let candidate: TargetStatus?
        if t.kind.isMedia && !a.coverage.isEmpty {
            candidate = .won
        } else if a.pitches.contains(where: { $0.status == .replied || $0.status == .covered }) {
            candidate = .talking
        } else if !a.pitches.isEmpty {
            candidate = .pitched
        } else {
            candidate = nil
        }
        guard let candidate, candidate.rank > t.status.rank else { return nil }
        return candidate
    }

    /// Why a target suits the artist, from their genres, comparable artists and location.
    static func fitReasons(for t: Target, profile: ArtistProfile) -> [String] {
        var reasons: [String] = []
        let theirs = t.genres.map { $0.lowercased() }
        let shared = profile.genres.filter { g in
            let mine = g.lowercased()
            return theirs.contains { $0.contains(mine) || mine.contains($0) }
        }
        if !shared.isEmpty { reasons.append("Covers \(shared.prefix(2).joined(separator: " and ").lowercased())") }
        let similar = t.similarArtists.lowercased()
        let mine = profile.audience.comparableArtists.commaSeparatedValues.filter { $0.count > 1 && similar.contains($0.lowercased()) }
        if !mine.isEmpty { reasons.append("Works with artists like \(mine.prefix(2).joined(separator: " and "))") }
        let city = profile.location.split(separator: ",").first.map { String($0).trimmed } ?? ""
        if city.count > 2 && t.location.localizedCaseInsensitiveContains(city) { reasons.append("Based in \(city)") }
        return reasons
    }

    static func isDue(_ t: Target, today: Date) -> Bool {
        guard let next = t.nextCheck else { return false }
        return next.startOfDay <= today.startOfDay
    }

    /// Whether there's any way to reach them: a person with an email, a submission address or a form.
    static func hasWayIn(_ t: Target, activity a: TargetActivity) -> Bool {
        !a.reachable.isEmpty || !t.submissionEmail.isBlank || !t.submissionURL.isBlank
    }

    // MARK: Suggestions

    static func kind(for role: ContactRole) -> TargetKind? {
        switch role {
        case .journalist: return .publication
        case .label: return .label
        case .radio: return .radio
        case .playlistCurator: return .playlist
        case .promoter: return .festival
        case .bookingAgent, .publicist, .syncAgent: return .agency
        default: return nil
        }
    }

    static func kind(for coverage: CoverageKind) -> TargetKind {
        switch coverage {
        case .podcast: return .podcast
        case .radioPlay: return .radio
        case .playlistAdd: return .playlist
        default: return .publication
        }
    }

    /// Organizations already in contacts or coverage that aren't on the list yet.
    static func suggestions(in ws: Workspace) -> [Target] {
        var seen = Set(ws.targets.map { squashed($0.name) })
        let matchedContacts = Set(ws.targets.flatMap { contacts(for: $0, in: ws.contacts).map(\.id) })
        var result: [Target] = []
        for c in ws.contacts where !c.isTeamMember && !matchedContacts.contains(c.id) {
            guard let kind = kind(for: c.role), !c.organization.isBlank else { continue }
            let key = squashed(c.organization)
            guard !key.isEmpty, seen.insert(key).inserted else {
                if let i = result.firstIndex(where: { squashed($0.name) == key }) { result[i].contactIDs.append(c.id) }
                continue
            }
            var t = Target(name: c.organization, kind: kind)
            t.website = host(c.website) == nil ? "" : siteRoot(c.website)
            t.contactIDs = [c.id]
            t.location = c.location
            result.append(t)
        }
        for c in ws.coverage where !c.outlet.isBlank {
            let key = squashed(c.outlet)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            var t = Target(name: c.outlet, kind: kind(for: c.kind), status: .won)
            if host(c.url) != nil { t.website = siteRoot(c.url) }
            result.append(t)
        }
        return result
    }

    // MARK: Reading a target's website

    static func guessKind(name: String, description: String, url: String) -> TargetKind {
        let text = " \(name) \(description) ".lowercased()
        let u = url.lowercased()
        if u.contains("open.spotify.com/playlist") || text.contains("playlist") { return .playlist }
        if text.contains("podcast") { return .podcast }
        if [" records", " recordings", "record label", "independent label", " label ", "music group", "label.", "label,"].contains(where: text.contains) {
            return .label
        }
        if [" radio", " fm ", "fm.", " fm,", "public radio", "community radio"].contains(where: text.contains) { return .radio }
        if [" festival", " fest "].contains(where: text.contains) { return .festival }
        if [" agency", "management", " pr ", "publicity", "booking"].contains(where: text.contains) { return .agency }
        return .publication
    }

    struct PageFindings: Equatable {
        var submissionLinks: [String] = []
        var emails: [String] = []
    }

    private static let anchorPattern = try! NSRegularExpression(pattern: "<a\\s[^>]*href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a>",
                                                                options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let emailPattern = try! NSRegularExpression(pattern: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", options: [])
    private static let tagPattern = try! NSRegularExpression(pattern: "<[^>]+>", options: [])

    /// Links to submission or contact pages, and email addresses, found on a page. Best ones first.
    static func findings(html: String, baseURL: String) -> PageFindings {
        let page = String(html.prefix(800_000))
        let base = URL(string: baseURL)
        var scored: [(score: Int, url: String)] = []
        var emails: [String] = []
        func addEmail(_ raw: String) {
            let e = raw.trimmed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
            let fileTypes = [".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"]
            guard e.contains("@"), !fileTypes.contains(where: e.hasSuffix), !e.contains("example."), !e.hasPrefix("noreply"),
                  !e.hasPrefix("no-reply"), !emails.contains(e) else { return }
            emails.append(e)
        }
        for m in anchorPattern.matches(in: page, range: NSRange(page.startIndex..., in: page)) {
            guard let hrefRange = Range(m.range(at: 1), in: page), let textRange = Range(m.range(at: 2), in: page) else { continue }
            let href = LinkReader.decodeEntities(String(page[hrefRange])).trimmed
            let rawText = String(page[textRange])
            let text = LinkReader.decodeEntities(tagPattern.stringByReplacingMatches(in: rawText, range: NSRange(rawText.startIndex..., in: rawText), withTemplate: " ")).lowercased()
            if href.lowercased().hasPrefix("mailto:") {
                let address = href.dropFirst(7).split(separator: "?").first.map(String.init) ?? ""
                addEmail(address.removingPercentEncoding ?? address)
                continue
            }
            let lowerHref = href.lowercased()
            var score = 0
            for (word, value) in [("submi", 5), ("demo", 5), ("pitch", 4), ("send us", 4), ("music submissions", 6),
                                  ("guidelines", 3), ("contribut", 2), ("contact", 1)] {
                if text.contains(word) || lowerHref.contains(word.replacingOccurrences(of: " ", with: "-")) { score = max(score, value) }
            }
            if lowerHref.contains("submithub.com") || lowerHref.contains("groover.co") { score = max(score, 5) }
            guard score > 0, !lowerHref.hasPrefix("javascript:"), !lowerHref.hasPrefix("#"),
                  let resolvedURL = URL(string: href, relativeTo: base)?.absoluteURL else { continue }
            let resolved = resolvedURL.absoluteString
            guard resolved.lowercased().hasPrefix("http") else { continue }
            // The outlet's own submissions page comes before a third-party service it also lists.
            if score >= 4, let mine = base?.host, resolvedURL.host == mine { score += 1 }
            if !scored.contains(where: { CoverageLinks.normalize($0.url) == CoverageLinks.normalize(resolved) }) {
                scored.append((score, resolved))
            }
        }
        let text = tagPattern.stringByReplacingMatches(in: page, range: NSRange(page.startIndex..., in: page), withTemplate: " ")
        for m in emailPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let r = Range(m.range, in: text) { addEmail(String(text[r])) }
        }
        let preferred = ["submi", "demo", "music", "press", "editor", "tips", "info", "hello", "contact"]
        func rank(_ e: String) -> Int { preferred.firstIndex { e.hasPrefix($0) || e.contains($0 + "@") } ?? preferred.count }
        emails.sort { rank($0) < rank($1) }
        let links = scored.enumerated().sorted { ($0.element.score, -$0.offset) > ($1.element.score, -$1.offset) }.map(\.element.url)
        return PageFindings(submissionLinks: Array(links.prefix(5)), emails: Array(emails.prefix(5)))
    }

    /// A target filled in from its website. The artist reviews it before saving.
    static func target(from meta: LinkMetadata, findings: PageFindings, now: Date = Date()) -> Target {
        var t = Target()
        t.name = meta.siteName.isBlank ? LinkReader.outletName(fromURL: meta.url) : meta.siteName
        t.website = siteRoot(meta.url)
        t.kind = guessKind(name: t.name, description: meta.description + " " + meta.title, url: meta.url)
        t.notes = Drafting.clip(meta.description, to: 400)
        t.submissionURL = findings.submissionLinks.first ?? ""
        t.submissionEmail = findings.emails.first ?? ""
        t.lastChecked = now
        t.createdAt = now
        return t
    }
}

// MARK: - CSV

struct TargetImportPreview {
    var totalRows = 0
    var added: [Target] = []
    var duplicates: [String] = []
    var skipped: [String] = []
    var hasChanges: Bool { !added.isEmpty }
}

enum TargetCSV {
    static let headers = ["name", "type", "status", "priority", "website", "submission_url", "submission_email",
                          "accepts_submissions", "genres", "location", "similar_artists", "guidelines", "notes", "tags", "next_check"]

    static func export(_ targets: [Target]) -> String {
        let rows = targets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }.map { t -> [String] in
            [t.name, t.kind.shortLabel, t.status.label(for: t.kind), t.tier.label, t.website, t.submissionURL, t.submissionEmail,
             t.submissionPolicy.label, t.genres.commaJoined, t.location, t.similarArtists, t.guidelines, t.notes,
             t.tags.commaJoined, t.nextCheck.map { DateParsing.iso($0) } ?? ""]
        }
        return CSV.write(headers: headers, rows: rows)
    }

    static func kind(from raw: String) -> TargetKind? {
        let v = raw.trimmed.lowercased()
        guard !v.isEmpty else { return nil }
        if let exact = TargetKind.allCases.first(where: { $0.rawValue == v || $0.label.lowercased() == v || $0.shortLabel.lowercased() == v }) {
            return exact
        }
        let synonyms: [(String, TargetKind)] = [("label", .label), ("record", .label), ("radio", .radio), ("station", .radio),
                                                ("podcast", .podcast), ("playlist", .playlist), ("curator", .playlist),
                                                ("festival", .festival), ("agency", .agency), ("pr", .agency), ("booking", .agency),
                                                ("blog", .publication), ("magazine", .publication), ("zine", .publication),
                                                ("newspaper", .publication), ("publication", .publication), ("press", .publication),
                                                ("outlet", .publication)]
        return synonyms.first { v.contains($0.0) }?.1
    }

    static func status(from raw: String) -> TargetStatus? {
        let v = raw.trimmed.lowercased()
        guard !v.isEmpty else { return nil }
        if let exact = TargetStatus.allCases.first(where: { $0.rawValue.lowercased() == v }) { return exact }
        let synonyms: [(String, TargetStatus)] = [("watch", .watching), ("eye", .watching), ("research", .researching),
                                                  ("ready", .ready), ("to pitch", .ready), ("pitched", .pitched), ("sent", .pitched),
                                                  ("conversation", .talking), ("talking", .talking), ("replied", .talking),
                                                  ("covered", .won), ("signed", .won), ("booked", .won), ("added", .won), ("played", .won),
                                                  ("working", .won), ("not now", .notNow), ("not right", .notNow), ("pass", .notNow),
                                                  ("no fit", .notNow), ("not a fit", .notNow)]
        return synonyms.first { v.contains($0.0) }?.1
    }

    static func tier(from raw: String) -> TargetTier? {
        let v = raw.trimmed.lowercased()
        if v.contains("dream") || v == "a" || v == "1" { return .dream }
        if v.contains("stretch") || v.contains("reach") { return .stretch }
        if v.contains("fit") || v.contains("realistic") || v.contains("now") { return .realistic }
        return nil
    }

    static func policy(from raw: String) -> SubmissionPolicy {
        let v = raw.trimmed.lowercased()
        if v.isEmpty || v.contains("not sure") || v.contains("unknown") { return .unknown }
        if v.contains("referral") || v.contains("invitation") || v.contains("invite") { return .referral }
        if v.contains("not") || v.contains("closed") || v == "no" || v == "false" { return .closed }
        if v.contains("yes") || v.contains("open") || v.contains("takes") || v.contains("accept") || v == "true" { return .open }
        return .unknown
    }

    static func preview(csv text: String, existing: [Target], now: Date = Date()) -> TargetImportPreview {
        let table = CSV.parseTable(text)
        var preview = TargetImportPreview()
        preview.totalRows = table.rows.count
        var names = Set(existing.map { Targets.squashed($0.name) })
        var hosts = Set(existing.compactMap { Targets.host($0.website) })
        for (index, row) in table.rows.enumerated() {
            let label = "Row \(index + 2)"
            var t = Target()
            t.name = CSV.value(row, ["name", "outlet", "publication", "label", "organization", "company", "station", "playlist", "title"])
            t.website = CSV.value(row, ["website", "url", "site", "link"])
            if t.name.isBlank && !t.website.isBlank { t.name = LinkReader.outletName(fromURL: t.website) }
            guard !t.name.isBlank else {
                preview.skipped.append("\(label): no name or website")
                continue
            }
            if !t.website.isBlank { t.website = Targets.siteRoot(t.website) }
            t.kind = kind(from: CSV.value(row, ["type", "kind", "category"]))
                ?? Targets.guessKind(name: t.name, description: CSV.value(row, ["notes", "description"]), url: t.website)
            t.status = status(from: CSV.value(row, ["status", "stage"])) ?? .watching
            t.tier = tier(from: CSV.value(row, ["priority", "tier"])) ?? .realistic
            t.submissionURL = CSV.value(row, ["submission_url", "submissions", "submit", "form", "submission_link"])
            t.submissionEmail = CSV.value(row, ["submission_email", "email", "contact_email", "demo_email"])
            t.submissionPolicy = policy(from: CSV.value(row, ["accepts_submissions", "submissions_open", "accepts_demos", "open"]))
            t.genres = CSV.value(row, ["genres", "genre", "style"]).commaSeparatedValues
            t.location = CSV.value(row, ["location", "city", "region", "country"])
            t.similarArtists = CSV.value(row, ["similar_artists", "roster", "artists", "covers"])
            t.guidelines = CSV.value(row, ["guidelines", "how_to_submit", "rules"])
            t.notes = CSV.value(row, ["notes", "description", "comments"])
            t.tags = CSV.value(row, ["tags", "tag"]).commaSeparatedValues
            t.nextCheck = DateParsing.parse(CSV.value(row, ["next_check", "check_again", "follow_up", "deadline"]))
            t.createdAt = now

            let key = Targets.squashed(t.name)
            let site = Targets.host(t.website)
            if names.contains(key) || (site.map(hosts.contains) ?? false) {
                preview.duplicates.append("\(label): \(t.name) is already on your list")
                continue
            }
            names.insert(key)
            if let site { hosts.insert(site) }
            preview.added.append(t)
        }
        return preview
    }
}
