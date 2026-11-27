import Foundation

// MARK: - Model

/// Who looks after the artist's music if they can't, where everything is, and what they want done with it.
/// An organizer for the artist and their estate attorney: nothing here is a will, and no passwords are kept.
struct LegacyPlan: Codable, Equatable {
    /// The person who would manage the catalog (sometimes called a music, creative or literary executor).
    var executorID: UUID?
    var backupExecutorID: UUID?
    var attorneyID: UUID?
    var accountantID: UUID?
    /// Who has a copy of this plan or knows where to find it.
    var whoKnows = ""
    var documents: [LegacyDocument] = LegacyDocument.starterSet
    var accounts: [LegacyAccount] = []
    var archive: [ArchiveLocation] = []
    var wishes = LegacyWishes()
    var lastReviewed: Date?
    var reviewEveryMonths = 12
}

enum LegacyDocumentKind: String, Codable, CaseIterable, Identifiable {
    case will, trust, powerOfAttorney, publishing, recording, management, splitSheets, registrations, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .will: return "Will"
        case .trust: return "Trust"
        case .powerOfAttorney: return "Power of attorney"
        case .publishing: return "Publishing and admin agreements"
        case .recording: return "Record, distribution and producer agreements"
        case .management: return "Management and agency agreements"
        case .splitSheets: return "Split sheets"
        case .registrations: return "Copyright and royalty registrations"
        case .other: return "Other document"
        }
    }
    var explanation: String {
        switch self {
        case .will: return "Names who inherits your music rights and royalties, and can name your music executor."
        case .trust: return "Many artists hold their catalog in a trust so royalties keep flowing without probate."
        case .powerOfAttorney: return "Lets someone act for you if you're alive but can't manage things yourself."
        case .publishing: return "Who controls and collects for your songs."
        case .recording: return "Who owns and pays out on your recordings."
        case .management: return "Commissions and terms that may continue after you."
        case .splitSheets: return "Who wrote what share of each song."
        case .registrations: return "Copyright Office, PRO, The MLC and SoundExchange registrations."
        case .other: return ""
        }
    }
}

enum LegacyDocumentStatus: String, Codable, CaseIterable, Identifiable {
    case missing, inProgress, inPlace, needsUpdate, notNeeded
    var id: String { rawValue }
    var label: String {
        switch self {
        case .missing: return "Don't have it"
        case .inProgress: return "Working on it"
        case .inPlace: return "In place"
        case .needsUpdate: return "Needs updating"
        case .notNeeded: return "Doesn't apply"
        }
    }
}

struct LegacyDocument: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: LegacyDocumentKind = .other
    var title = ""
    var status: LegacyDocumentStatus = .missing
    /// Where to find it: "Safe at home", "Attorney's office", "Dropbox › Legal". Never the document's contents.
    var location = ""
    var lastReviewed: Date?
    var notes = ""

    var displayTitle: String { kind == .other && !title.isBlank ? title : kind.label }

    static var starterSet: [LegacyDocument] {
        [.will, .trust, .powerOfAttorney, .publishing, .recording, .splitSheets, .registrations].map { LegacyDocument(kind: $0) }
    }
}

enum AccountLegacyOption: String, Codable, CaseIterable, Identifiable {
    case unknown, setUp, notSetUp, notOffered
    var id: String { rawValue }
    var label: String {
        switch self {
        case .unknown: return "Not checked yet"
        case .setUp: return "Set up"
        case .notSetUp: return "Offered, not set up"
        case .notOffered: return "Not offered"
        }
    }
}

/// An account someone would need: what it controls and where its sign-in is kept. Never the password itself.
struct LegacyAccount: Codable, Equatable, Identifiable {
    var id = UUID()
    var service = ""
    var controls = ""
    var accessKeptAt = ""
    var legacyOption: AccountLegacyOption = .unknown
    var notes = ""
}

struct ArchiveLocation: Codable, Equatable, Identifiable {
    var id = UUID()
    var what = ""
    var location = ""
    var backupLocation = ""
    var notes = ""
}

struct LegacyWishes: Codable, Equatable {
    /// Keep releases in stores, who decides on reissues, how to handle the catalog if it's offered for sale.
    var catalog = ""
    /// Which unreleased songs, demos or sessions may be finished or released, and which must not.
    var unreleased = ""
    /// Licensing: uses you'd welcome, and ones never to approve (causes, products, samples).
    var licensing = ""
    /// Use of your name, image and voice, including AI voice models and recreations.
    var nameAndLikeness = ""
    /// Instruments, notebooks, recordings and memorabilia: keep, give, donate or sell.
    var archive = ""
    var other = ""

    var isEmpty: Bool { [catalog, unreleased, licensing, nameAndLikeness, archive, other].allSatisfy(\.isBlank) }
}

// MARK: - Readiness

enum LegacySection: String, CaseIterable, Identifiable {
    case overview, people, documents, accounts, archive, wishes
    var id: String { rawValue }
    var label: String {
        switch self {
        case .overview: return "Overview"
        case .people: return "People"
        case .documents: return "Documents"
        case .accounts: return "Accounts"
        case .archive: return "Recordings & files"
        case .wishes: return "Wishes"
        }
    }
}

struct LegacyCheck: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var done: Bool
    var section: LegacySection
    /// Where to fix it when it's somewhere else in Manager (Releases, Profile).
    var destination: AppDestination? = nil
}

enum LegacyReadiness {
    static func releasedReleases(_ ws: Workspace, now: Date = Date()) -> [Release] {
        ws.releases.filter { $0.stage == .released || ($0.stage != .idea && ($0.releaseDate ?? .distantFuture) <= now) }
    }

    static func checks(for ws: Workspace, now: Date = Date()) -> [LegacyCheck] {
        let plan = ws.legacy
        var checks: [LegacyCheck] = []
        func add(_ id: String, _ title: String, _ detail: String, _ done: Bool, _ section: LegacySection, _ destination: AppDestination? = nil) {
            checks.append(LegacyCheck(id: id, title: title, detail: detail, done: done, section: section, destination: destination))
        }
        add("executor", "Choose who would look after your music",
            "Someone who'd handle releases, licensing requests and royalties. Name them in your will or trust too.",
            ws.contact(plan.executorID) != nil, .people)
        add("backup", "Choose a backup", "In case your first choice can't do it.", ws.contact(plan.backupExecutorID) != nil, .people)

        let estate = plan.documents.filter { $0.kind == .will || $0.kind == .trust }
        add("will", "Have a will or trust that covers your music",
            "Without one, rights and royalties follow your state's default rules, which may not be what you want.",
            estate.contains { $0.status == .inPlace }, .documents)
        let stale = plan.documents.filter { $0.status == .needsUpdate }
        add("documents-current", "Bring documents up to date",
            stale.isEmpty ? "Nothing is marked as needing an update." : stale.map(\.displayTitle).joined(separator: ", "),
            stale.isEmpty && plan.documents.contains { $0.status == .inPlace }, .documents)
        let unplaced = plan.documents.filter { $0.status == .inPlace && $0.location.isBlank }
        add("documents-located", "Say where each document is",
            unplaced.isEmpty ? "Every document you have says where to find it." : "No location yet: " + unplaced.map(\.displayTitle).joined(separator: ", "),
            plan.documents.contains { $0.status == .inPlace } && unplaced.isEmpty, .documents)

        let noAccess = plan.accounts.filter { $0.accessKeptAt.isBlank }
        add("accounts", "List the accounts someone would need, and where each sign-in is kept",
            plan.accounts.isEmpty ? "Your distributor, royalty organizations, email, website and social accounts."
                : (noAccess.isEmpty ? "\(plan.accounts.count) accounts listed." : "No sign-in location yet: " + noAccess.prefix(4).map(\.service).joined(separator: ", ")),
            !plan.accounts.isEmpty && noAccess.isEmpty, .accounts)
        let offered = plan.accounts.filter { $0.legacyOption == .notSetUp }
        add("legacy-contacts", "Set up legacy contacts where services offer them",
            offered.isEmpty ? "Apple, Google and some other services let you name someone in advance."
                : "Offered but not set up: " + offered.map(\.service).joined(separator: ", "),
            !plan.accounts.isEmpty && offered.isEmpty && !plan.accounts.allSatisfy { $0.legacyOption == .unknown }, .accounts)

        add("archive", "Write down where your masters and session files are",
            "Masters, stems, multitracks and unreleased material — the things that can't be downloaded from a store.",
            plan.archive.contains { !$0.location.isBlank }, .archive)
        let single = plan.archive.filter { !$0.location.isBlank && $0.backupLocation.isBlank }
        add("archive-backup", "Keep a second copy",
            single.isEmpty ? "Every location has a backup." : "Only one copy: " + single.map { $0.what.isBlank ? $0.location : $0.what }.joined(separator: ", "),
            !plan.archive.isEmpty && single.isEmpty, .archive)

        let released = releasedReleases(ws, now: now)
        let tracks = released.flatMap(\.tracks)
        let unsplit = tracks.filter { abs($0.splitTotal - 100) > 0.01 }
        add("splits", "Record songwriter splits for every released song",
            tracks.isEmpty ? "Nothing released yet." : (unsplit.isEmpty ? "All \(tracks.count) released songs have splits that add up to 100%."
                : "\(unsplit.count) song\(unsplit.count == 1 ? "" : "s") without complete splits."),
            !tracks.isEmpty && unsplit.isEmpty, .overview, .releases)
        let memberships = ws.profile.rightsMemberships
        let unregistered = memberships.filter { $0.status != .registered }
        add("registrations", "Finish your royalty registrations",
            memberships.isEmpty ? "Add your PRO, mechanical and neighboring-rights memberships in Profile › Rights."
                : (unregistered.isEmpty ? "All \(memberships.count) memberships are registered." : "Not finished: " + unregistered.map(\.organization).joined(separator: ", ")),
            !memberships.isEmpty && unregistered.isEmpty, .overview, .profile)

        add("unreleased", "Say what should happen to unreleased music",
            "Which demos and sessions may be finished or released, and which must never be.", !plan.wishes.unreleased.isBlank, .wishes)
        add("likeness", "Say how your name, image and voice may be used",
            "Including AI voice models and recreations. Rights here after death depend on where you live.", !plan.wishes.nameAndLikeness.isBlank, .wishes)
        add("shared", "Tell someone where this plan is",
            "Export the letter and give it to your executor or attorney, or keep it with your will.", !plan.whoKnows.isBlank, .people)
        add("reviewed", "Review the plan once a year",
            plan.lastReviewed.map { "Last reviewed \(DateParsing.iso($0).prefix(10))." } ?? "Not reviewed yet.",
            !isReviewDue(plan, now: now), .overview)
        return checks
    }

    static func score(_ checks: [LegacyCheck]) -> Double {
        checks.isEmpty ? 0 : Double(checks.filter(\.done).count) / Double(checks.count)
    }

    static func isReviewDue(_ plan: LegacyPlan, now: Date = Date()) -> Bool {
        guard let last = plan.lastReviewed else { return true }
        let months = max(1, plan.reviewEveryMonths)
        guard let due = Calendar.current.date(byAdding: .month, value: months, to: last) else { return true }
        return due <= now
    }

    /// Whether the artist has started: anything entered beyond the starter document list.
    static func hasStarted(_ plan: LegacyPlan) -> Bool {
        plan.executorID != nil || !plan.accounts.isEmpty || !plan.archive.isEmpty || !plan.wishes.isEmpty
            || plan.documents.contains { $0.status != .missing || !$0.location.isBlank } || plan.lastReviewed != nil
    }
}

// MARK: - Account suggestions

struct AccountSuggestion: Equatable {
    var service: String
    var controls: String
    /// What the service offers for this, when it's known to offer something.
    var legacyHint: String
}

enum LegacyAccounts {
    /// Accounts most artists would want listed, plus the ones Manager can see in this workspace.
    static func suggestions(for ws: Workspace) -> [AccountSuggestion] {
        var result: [AccountSuggestion] = []
        func add(_ service: String, _ controls: String, _ hint: String = "") {
            guard !service.isBlank else { return }
            let key = service.lowercased()
            guard !result.contains(where: { $0.service.lowercased() == key }),
                  !ws.legacy.accounts.contains(where: { $0.service.lowercased() == key }) else { return }
            result.append(AccountSuggestion(service: service, controls: controls, legacyHint: hint))
        }
        for distributor in Set(ws.releases.map(\.distributor).filter { !$0.isBlank }).sorted() {
            let hint = distributor.lowercased().contains("distrokid")
                ? "DistroKid's “Leave a Legacy” extra keeps a release in stores even if the membership stops being paid. It's bought per release."
                : "Ask what happens to your releases if the account stops being paid."
            add(distributor, "Your releases in stores, and the royalties they earn", hint)
        }
        for m in ws.profile.rightsMemberships where !m.organization.isBlank {
            add(m.organization, "\(m.type.label) royalties", "Ask how they pay an estate or a beneficiary.")
        }
        for link in ws.profile.links.labeled where link.label != "Other" {
            switch link.label {
            case "Website": add("Website and domain", "Your site and the domain name, which must be renewed to keep working")
            case "Spotify": add("Spotify for Artists", "Your artist profile and pitches")
            case "Apple Music": add("Apple Music for Artists", "Your artist profile")
            case "Bandcamp": add("Bandcamp", "Sales, downloads and the money they pay out")
            case "YouTube": add("YouTube", "Your channel and videos", "Google's Inactive Account Manager can share your data with people you choose after a period of inactivity.")
            case "Instagram": add("Instagram", "Your profile and posts")
            case "TikTok": add("TikTok", "Your profile and videos")
            case "SoundCloud": add("SoundCloud", "Your uploads")
            default: break
            }
        }
        add("Email", "Where everyone — labels, writers, royalty organizations — sends messages and password resets")
        add("Password manager", "Every other sign-in", "Many password managers offer emergency access for someone you choose.")
        add("Apple Account", "Your iCloud files and devices", "Apple lets you add a Legacy Contact who can request access to your data.")
        add("Google Account", "Gmail, Drive and YouTube", "Google's Inactive Account Manager shares your data with up to 10 people after 3 to 18 months of inactivity.")
        add("Bank account royalties are paid into", "Where royalty and sales income lands — record where to find the details, not the numbers")
        if !ws.subscribers.isEmpty || !ws.campaigns.isEmpty {
            add("Email list provider", "Your fans' email addresses and newsletters")
        }
        return result
    }
}

extension LegacyAccounts {
    /// True when text looks like a password or key rather than a note about where one is kept.
    static func looksLikeSecret(_ text: String) -> Bool {
        let lower = text.lowercased()
        for label in ["password:", "password =", "password is", "pw:", "pwd:", "passcode:", "pin:", "pin is", "secret:", "recovery code"] {
            if lower.contains(label) { return true }
        }
        for word in text.split(whereSeparator: { $0.isWhitespace }) where word.count >= 12 {
            let w = String(word)
            if w.contains("@") || w.contains("/") || w.contains(".com") || w.lowercased().hasPrefix("http") { continue }
            let hasLetter = w.contains { $0.isLetter }
            let hasDigit = w.contains { $0.isNumber }
            let hasSymbol = w.contains { !$0.isLetter && !$0.isNumber }
            let mixedCase = w.contains { $0.isUppercase } && w.contains { $0.isLowercase }
            if hasLetter && hasDigit && (hasSymbol || mixedCase) { return true }
        }
        return false
    }
}

// MARK: - The letter

enum LegacyLetter {
    static func markdown(for ws: Workspace, now: Date = Date()) -> String {
        let plan = ws.legacy
        let name = ws.profile.displayName
        var out: [String] = []
        out.append("# \(name): my music — what to do if something happens to me")
        out.append("Written with Manager on \(DateParsing.iso(now).prefix(10)).\(plan.lastReviewed.map { " Last reviewed \(DateParsing.iso($0).prefix(10))." } ?? "")")
        out.append("> This isn't a will and doesn't contain any passwords. It says who should look after my music, where everything is, and what I want. My will or trust is what makes it official.")

        func person(_ id: UUID?) -> String? {
            guard let c = ws.contact(id) else { return nil }
            return [c.displayName, c.organization.isBlank || c.organization == c.displayName ? "" : c.organization, c.email, c.phone]
                .filter { !$0.isBlank }.joined(separator: " · ")
        }
        var people: [String] = []
        if let p = person(plan.executorID) { people.append("- **Looks after my music:** \(p)") }
        if let p = person(plan.backupExecutorID) { people.append("- **If they can't:** \(p)") }
        if let p = person(plan.attorneyID) { people.append("- **Attorney:** \(p)") }
        if let p = person(plan.accountantID) { people.append("- **Accountant:** \(p)") }
        for member in ws.teamMembers where ![plan.executorID, plan.backupExecutorID, plan.attorneyID, plan.accountantID].contains(member.id) {
            let detail = [member.role.label, member.organization, member.email, member.phone].filter { !$0.isBlank }.joined(separator: " · ")
            people.append("- \(member.displayName): \(detail)\(member.responsibilities.isBlank ? "" : " — \(member.responsibilities)")")
        }
        if !plan.whoKnows.isBlank { people.append("- **Who has this plan:** \(plan.whoKnows)") }
        if !people.isEmpty { out.append("## People\n\n" + people.joined(separator: "\n")) }

        let docs = plan.documents.filter { $0.status != .notNeeded && ($0.status != .missing || !$0.location.isBlank) }
        if !docs.isEmpty {
            out.append("## Documents\n\n" + docs.map { d in
                "- **\(d.displayTitle)** — \(d.status.label)\(d.location.isBlank ? "" : ". Where: \(d.location)")\(d.notes.isBlank ? "" : ". \(d.notes)")"
            }.joined(separator: "\n"))
        }

        let released = LegacyReadiness.releasedReleases(ws, now: now)
        if !released.isEmpty {
            var lines: [String] = []
            for r in released.sorted(by: { ($0.releaseDate ?? .distantPast) < ($1.releaseDate ?? .distantPast) }) {
                let meta = [r.type.label, r.releaseDate.map { String(DateParsing.iso($0).prefix(10)) } ?? "", r.distributor.isBlank ? "" : "via \(r.distributor)",
                            r.label.isBlank ? "" : "label: \(r.label)", r.upc.isBlank ? "" : "UPC \(r.upc)"].filter { !$0.isBlank }
                lines.append("### \(r.title.isBlank ? "Untitled release" : r.title)\n\n" + meta.joined(separator: " · "))
                for t in r.tracks where !t.title.isBlank {
                    let codes = [t.isrc.isBlank ? "" : "ISRC \(t.isrc)", t.iswc.isBlank ? "" : "ISWC \(t.iswc)"].filter { !$0.isBlank }.joined(separator: ", ")
                    let splits = t.writers.filter { !$0.name.isBlank }.map { w in
                        "\(w.name) \(Self.percent(w.share))\(w.pro.isBlank ? "" : " (\(w.pro)\(w.ipi.isBlank ? "" : ", IPI \(w.ipi)"))")"
                    }.joined(separator: "; ")
                    lines.append("- \(t.title)\(codes.isBlank ? "" : " — \(codes)")\(splits.isBlank ? "" : ". Writers: \(splits)")")
                }
            }
            out.append("## My releases\n\n" + lines.joined(separator: "\n"))
        }
        let memberships = ws.profile.rightsMemberships.filter { !$0.organization.isBlank }
        if !memberships.isEmpty {
            out.append("## Where royalties are collected\n\n" + memberships.map { m in
                "- **\(m.organization)** — \(m.type.label), \(m.status.label.lowercased())\(m.notes.isBlank ? "" : ". \(m.notes)")"
            }.joined(separator: "\n"))
        }
        if !plan.accounts.isEmpty {
            out.append("## Accounts\n\nNo passwords are written here. Each line says where the sign-in is kept.\n\n" + plan.accounts.map { a in
                var parts = ["- **\(a.service.isBlank ? "Account" : a.service)**"]
                if !a.controls.isBlank { parts.append("— \(a.controls)") }
                var line = parts.joined(separator: " ")
                if !a.accessKeptAt.isBlank { line += ". Sign-in kept: \(a.accessKeptAt)" }
                if a.legacyOption == .setUp { line += ". Legacy contact set up" }
                if !a.notes.isBlank { line += ". \(a.notes)" }
                return line
            }.joined(separator: "\n"))
        }
        if !plan.archive.isEmpty {
            out.append("## Recordings and files\n\n" + plan.archive.map { item in
                "- **\(item.what.isBlank ? "Files" : item.what)** — \(item.location.isBlank ? "location not written down" : item.location)\(item.backupLocation.isBlank ? "" : "; copy at \(item.backupLocation)")\(item.notes.isBlank ? "" : ". \(item.notes)")"
            }.joined(separator: "\n"))
        }
        let w = plan.wishes
        let wishes = [("My catalog", w.catalog), ("Unreleased music", w.unreleased), ("Licensing", w.licensing),
                      ("My name, image and voice", w.nameAndLikeness), ("Instruments, notebooks and memorabilia", w.archive),
                      ("Anything else", w.other)].filter { !$0.1.isBlank }
        if !wishes.isEmpty {
            out.append("## My wishes\n\n" + wishes.map { "### \($0.0)\n\n\($0.1)" }.joined(separator: "\n\n"))
        }
        return out.joined(separator: "\n\n") + "\n"
    }

    static func percent(_ share: Double) -> String {
        share == share.rounded() ? "\(Int(share))%" : String(format: "%.1f%%", share)
    }

    /// A printable page: open it in a browser and print or save as PDF.
    static func html(for ws: Workspace, now: Date = Date()) -> String {
        let md = markdown(for: ws, now: now)
        var body: [String] = []
        var list: [String] = []
        func flushList() {
            if !list.isEmpty { body.append("<ul>" + list.joined() + "</ul>"); list = [] }
        }
        func inline(_ text: String) -> String {
            var t = PressKitRenderer.html(text)
            while let open = t.range(of: "**"), let close = t.range(of: "**", range: open.upperBound..<t.endIndex) {
                let inner = String(t[open.upperBound..<close.lowerBound])
                t.replaceSubrange(open.lowerBound..<close.upperBound, with: "<strong>\(inner)</strong>")
            }
            return t
        }
        for raw in md.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flushList(); continue }
            if line.hasPrefix("- ") { list.append("<li>\(inline(String(line.dropFirst(2))))</li>"); continue }
            flushList()
            if line.hasPrefix("### ") { body.append("<h3>\(inline(String(line.dropFirst(4))))</h3>") }
            else if line.hasPrefix("## ") { body.append("<h2>\(inline(String(line.dropFirst(3))))</h2>") }
            else if line.hasPrefix("# ") { body.append("<h1>\(inline(String(line.dropFirst(2))))</h1>") }
            else if line.hasPrefix("> ") { body.append("<blockquote>\(inline(String(line.dropFirst(2))))</blockquote>") }
            else { body.append("<p>\(inline(line))</p>") }
        }
        flushList()
        let title = PressKitRenderer.html("\(ws.profile.displayName) — Legacy plan")
        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><title>\(title)</title>
        <style>
        body { font: 15px/1.55 -apple-system, "Helvetica Neue", sans-serif; color: #1d1d1f; max-width: 760px; margin: 40px auto; padding: 0 24px; }
        h1 { font-size: 26px; margin-bottom: 4px; } h2 { font-size: 19px; margin-top: 32px; border-bottom: 1px solid #ddd; padding-bottom: 4px; }
        h3 { font-size: 16px; margin: 18px 0 4px; } blockquote { margin: 16px 0; padding: 10px 14px; background: #f5f5f7; border-left: 3px solid #999; }
        li { margin: 4px 0; } @media print { body { margin: 0 auto; } h2 { break-after: avoid; } }
        </style></head><body>
        \(body.joined(separator: "\n"))
        </body></html>
        """
    }
}
