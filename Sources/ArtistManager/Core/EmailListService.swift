import Foundation

enum EmailAddress {
    static func normalize(_ raw: String) -> String {
        raw.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'")).lowercased()
    }

    /// A deliberately simple syntax check: one @, something before it, a dotted domain, no spaces.
    static func isValid(_ email: String) -> Bool {
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !email.contains(" ") else { return false }
        let domain = parts[1]
        guard domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix("."), !domain.contains("..") else { return false }
        return true
    }

    static let roleAccounts: Set<String> = ["info", "admin", "support", "sales", "contact", "hello", "office",
                                            "noreply", "no-reply", "webmaster", "postmaster", "abuse", "billing", "team"]

    static func isRoleAccount(_ email: String) -> Bool {
        guard let local = email.split(separator: "@").first else { return false }
        return roleAccounts.contains(String(local))
    }

    static let commonTypos: [String: String] = [
        "gmial.com": "gmail.com", "gmai.com": "gmail.com", "gmal.com": "gmail.com", "gamil.com": "gmail.com",
        "gmail.co": "gmail.com", "gnail.com": "gmail.com", "yaho.com": "yahoo.com", "yahooo.com": "yahoo.com",
        "hotmial.com": "hotmail.com", "hotmal.com": "hotmail.com", "outlok.com": "outlook.com",
        "iclod.com": "icloud.com", "icloud.co": "icloud.com"
    ]

    static func suggestedFix(_ email: String) -> String? {
        let parts = email.split(separator: "@")
        guard parts.count == 2, let fix = commonTypos[String(parts[1])] else { return nil }
        return "\(parts[0])@\(fix)"
    }
}

// MARK: - Import

struct SubscriberImportOptions: Equatable {
    /// Status for rows that don't have a status column (e.g. a provider's separate "unsubscribed" export).
    var defaultStatus: SubscriptionStatus = .subscribed
    var source = ""
    var consentMethod: ConsentMethod = .importedFromProvider
    var consentEvidence = ""
    var tagsToAdd: [String] = []
}

struct SubscriberImportPreview {
    var totalRows = 0
    var added: [Subscriber] = []
    var updated: [Subscriber] = []
    /// Addresses the file tried to (re)subscribe that are unsubscribed/bounced here. Kept suppressed.
    var suppressionsKept: [String] = []
    /// Addresses newly marked unsubscribed/bounced/complained by this file.
    var newlySuppressed: [String] = []
    var invalidRows: [String] = []
    var duplicateRowsInFile = 0
    var missingConsent = 0
    var recognizedColumns: [String] = []
    var unrecognizedColumns: [String] = []

    var hasChanges: Bool { !added.isEmpty || !updated.isEmpty }
}

enum SubscriberImporter {
    static let emailKeys = ["email", "email_address", "e_mail", "emailaddress", "subscriber_email", "address"]
    static let firstNameKeys = ["first_name", "firstname", "fname", "given_name", "first"]
    static let lastNameKeys = ["last_name", "lastname", "lname", "surname", "family_name", "last"]
    static let nameKeys = ["name", "full_name", "fullname"]
    static let statusKeys = ["status", "subscription_status", "member_status", "state", "subscribed", "email_status"]
    static let sourceKeys = ["source", "signup_source", "opt_in_source", "referrer", "form", "acquisition_source"]
    /// Dates that record an opt-in. These count as consent evidence.
    static let consentDateKeys = ["optin_time", "opt_in_time", "confirm_time", "confirmed_at", "consent_captured_at", "consent_date"]
    /// Dates that only say when someone was added. They set the signup date but aren't proof of consent.
    static let signupDateKeys = ["subscribed_at", "created_at", "date_added", "signup_date", "joined"]
    static let consentEvidenceKeys = ["consent_evidence", "consent", "gdpr_consent", "marketing_permissions"]
    static let consentMethodKeys = ["consent_method"]
    static let tagKeys = ["tags", "tag", "groups", "lists", "segments"]
    static let locationKeys = ["location", "city", "region", "country", "cc"]
    static let statusChangedKeys = ["unsub_time", "unsubscribed_at", "bounced_at", "status_changed_at", "clean_time"]

    static var knownKeys: Set<String> {
        Set(emailKeys + firstNameKeys + lastNameKeys + nameKeys + statusKeys + sourceKeys + consentDateKeys + signupDateKeys
            + consentEvidenceKeys + consentMethodKeys + tagKeys + locationKeys + statusChangedKeys
            + ["double_opt_in", "consent_source", "notes"])
    }

    /// Works out what an import would do without changing anything.
    ///
    /// Rules:
    /// - Unsubscribed, bounced, complained and cleaned addresses stay that way. An import can't re-subscribe them.
    /// - An import *can* newly suppress an address (an unsubscribe in the provider wins).
    /// - Within one file, a suppressed row wins over a subscribed row for the same address.
    static func preview(csv text: String, existing: [Subscriber], options: SubscriberImportOptions, now: Date = Date()) -> SubscriberImportPreview {
        let table = CSV.parseTable(text)
        var preview = SubscriberImportPreview()
        preview.recognizedColumns = table.headers.filter { knownKeys.contains($0) }
        preview.unrecognizedColumns = table.headers.filter { !knownKeys.contains($0) && !$0.isEmpty }
        preview.totalRows = table.rows.count

        guard table.headers.contains(where: { emailKeys.contains($0) }) else {
            preview.invalidRows = ["No email column found. Expected a header like “Email” or “Email Address”."]
            return preview
        }

        // Collapse duplicate rows in the file first.
        var incoming: [String: Subscriber] = [:]
        var order: [String] = []
        for (index, row) in table.rows.enumerated() {
            let email = EmailAddress.normalize(CSV.value(row, emailKeys))
            guard EmailAddress.isValid(email) else {
                let shown = CSV.value(row, emailKeys)
                preview.invalidRows.append("Row \(index + 2): \(shown.isEmpty ? "no email" : shown)")
                continue
            }
            let candidate = subscriber(from: row, email: email, options: options, now: now)
            if let previous = incoming[email] {
                preview.duplicateRowsInFile += 1
                incoming[email] = mergeDuplicate(previous, candidate)
            } else {
                incoming[email] = candidate
                order.append(email)
            }
        }

        var existingByEmail: [String: Subscriber] = [:]
        for s in existing { existingByEmail[EmailAddress.normalize(s.email)] = s }

        for email in order {
            guard let row = incoming[email] else { continue }
            if var current = existingByEmail[email] {
                let before = current
                if current.status.isSuppressed && !row.status.isSuppressed {
                    preview.suppressionsKept.append(email)
                } else if row.status != current.status && (row.status.isSuppressed || current.status == .pending) {
                    current.status = row.status
                    current.statusChangedAt = row.statusChangedAt ?? now
                    current.statusReason = "Imported from \(options.source.isBlank ? "file" : options.source)"
                    if row.status.isSuppressed { preview.newlySuppressed.append(email) }
                }
                if current.firstName.isBlank { current.firstName = row.firstName }
                if current.lastName.isBlank { current.lastName = row.lastName }
                if current.location.isBlank { current.location = row.location }
                if current.signupSource.isBlank { current.signupSource = row.signupSource }
                if current.consent == nil, let consent = row.consent { current.consent = consent }
                let tagSet = Set(current.tags.map { $0.lowercased() })
                for tag in row.tags where !tagSet.contains(tag.lowercased()) { current.tags.append(tag) }
                if row.createdAt < current.createdAt { current.createdAt = row.createdAt }
                if current != before { preview.updated.append(current) }
            } else {
                preview.added.append(row)
                if row.status == .subscribed && row.consent == nil { preview.missingConsent += 1 }
            }
        }
        return preview
    }

    private static func subscriber(from row: [String: String], email: String, options: SubscriberImportOptions, now: Date) -> Subscriber {
        var s = Subscriber()
        s.email = email
        s.firstName = CSV.value(row, firstNameKeys)
        s.lastName = CSV.value(row, lastNameKeys)
        if s.firstName.isBlank && s.lastName.isBlank {
            let full = CSV.value(row, nameKeys)
            if !full.isBlank {
                var parts = full.split(separator: " ").map(String.init)
                s.firstName = parts.isEmpty ? "" : parts.removeFirst()
                s.lastName = parts.joined(separator: " ")
            }
        }
        let rawStatus = CSV.value(row, statusKeys)
        s.status = SubscriptionStatus.parse(rawStatus) ?? options.defaultStatus
        s.signupSource = CSV.value(row, sourceKeys)
        if s.signupSource.isBlank { s.signupSource = options.source }
        s.location = CSV.value(row, locationKeys)
        var tags = CSV.value(row, tagKeys).commaSeparatedValues
        for tag in options.tagsToAdd where !tags.contains(where: { $0.lowercased() == tag.lowercased() }) { tags.append(tag) }
        s.tags = tags
        let consentDate = DateParsing.parse(CSV.value(row, consentDateKeys))
        let signupDate = DateParsing.parse(CSV.value(row, signupDateKeys))
        s.createdAt = signupDate ?? consentDate ?? now
        s.statusChangedAt = DateParsing.parse(CSV.value(row, statusChangedKeys))

        let rowEvidence = CSV.value(row, consentEvidenceKeys)
        let rowMethod = ConsentMethod(rawValue: CSV.value(row, consentMethodKeys))
        let doubleOptIn = ["true", "yes", "1", "y"].contains(CSV.value(row, ["double_opt_in"]).lowercased())
        let hasRowConsent = consentDate != nil || !rowEvidence.isBlank || rowMethod != nil
        if hasRowConsent || !options.consentEvidence.isBlank {
            var consent = ConsentRecord()
            consent.method = rowMethod ?? (doubleOptIn ? .doubleOptIn : options.consentMethod)
            consent.source = CSV.value(row, ["consent_source"]).isBlank ? s.signupSource : CSV.value(row, ["consent_source"])
            consent.capturedAt = consentDate
            consent.evidence = rowEvidence.isBlank ? options.consentEvidence : rowEvidence
            s.consent = consent
        }
        return s
    }

    private static func mergeDuplicate(_ a: Subscriber, _ b: Subscriber) -> Subscriber {
        var merged = b
        if a.status.isSuppressed && !b.status.isSuppressed { merged.status = a.status; merged.statusChangedAt = a.statusChangedAt }
        if merged.firstName.isBlank { merged.firstName = a.firstName }
        if merged.lastName.isBlank { merged.lastName = a.lastName }
        if merged.consent == nil { merged.consent = a.consent }
        merged.tags = Array(Set(a.tags + b.tags)).sorted()
        merged.createdAt = min(a.createdAt, b.createdAt)
        return merged
    }

    /// Applies a preview to the subscriber list.
    static func apply(_ preview: SubscriberImportPreview, to subscribers: inout [Subscriber]) {
        var indexByID: [UUID: Int] = [:]
        for (i, s) in subscribers.enumerated() { indexByID[s.id] = i }
        for updated in preview.updated {
            if let i = indexByID[updated.id] { subscribers[i] = updated }
        }
        subscribers.append(contentsOf: preview.added)
    }
}

// MARK: - Export

enum SubscriberExporter {
    static let headers = ["email", "first_name", "last_name", "status", "status_changed_at", "status_reason",
                          "signup_source", "consent_method", "consent_source", "consent_captured_at", "consent_evidence",
                          "tags", "location", "created_at"]

    /// Full export including unsubscribed and bounced addresses, so the suppression list travels with the data.
    static func csv(_ subscribers: [Subscriber]) -> String {
        let rows = subscribers.sorted { $0.email < $1.email }.map { s -> [String] in
            [s.email, s.firstName, s.lastName, s.status.rawValue, DateParsing.iso(s.statusChangedAt), s.statusReason,
             s.signupSource, s.consent?.method.rawValue ?? "", s.consent?.source ?? "",
             DateParsing.iso(s.consent?.capturedAt), s.consent?.evidence ?? "",
             s.tags.commaJoined, s.location, DateParsing.iso(s.createdAt)]
        }
        return CSV.write(headers: headers, rows: rows)
    }

    /// Only addresses that may receive a campaign, in a shape email providers import directly.
    static func sendableCSV(_ subscribers: [Subscriber]) -> String {
        let rows = subscribers.filter { $0.status.canReceiveCampaigns }.sorted { $0.email < $1.email }.map {
            [$0.email, $0.firstName, $0.lastName, $0.tags.commaJoined]
        }
        return CSV.write(headers: ["Email Address", "First Name", "Last Name", "Tags"], rows: rows)
    }

    /// Unsubscribed, bounced, complained and cleaned addresses — upload to a provider as a suppression list.
    static func suppressionCSV(_ subscribers: [Subscriber]) -> String {
        let rows = subscribers.filter { $0.status.isSuppressed }.sorted { $0.email < $1.email }.map {
            [$0.email, $0.status.rawValue, DateParsing.iso($0.statusChangedAt)]
        }
        return CSV.write(headers: ["email", "status", "status_changed_at"], rows: rows)
    }
}

// MARK: - List hygiene

struct ListHygieneReport: Equatable {
    var countsByStatus: [SubscriptionStatus: Int] = [:]
    var subscribedWithoutConsent: [String] = []
    var invalidAddresses: [String] = []
    var roleAccounts: [String] = []
    var likelyTypos: [String] = []
    var stalePending: [String] = []
    var duplicateAddresses: [String] = []

    var total: Int { countsByStatus.values.reduce(0, +) }
    func count(_ status: SubscriptionStatus) -> Int { countsByStatus[status] ?? 0 }
    var issueCount: Int {
        subscribedWithoutConsent.count + invalidAddresses.count + roleAccounts.count + likelyTypos.count
            + stalePending.count + duplicateAddresses.count
    }
}

enum ListHygiene {
    static func report(_ subscribers: [Subscriber], now: Date = Date()) -> ListHygieneReport {
        var report = ListHygieneReport()
        var seen = Set<String>()
        for s in subscribers {
            report.countsByStatus[s.status, default: 0] += 1
            let email = EmailAddress.normalize(s.email)
            if seen.contains(email) { report.duplicateAddresses.append(email) }
            seen.insert(email)
            if !EmailAddress.isValid(email) { report.invalidAddresses.append(s.email); continue }
            guard !s.status.isSuppressed else { continue }
            if s.status == .subscribed && s.consent == nil { report.subscribedWithoutConsent.append(email) }
            if EmailAddress.isRoleAccount(email) { report.roleAccounts.append(email) }
            if EmailAddress.suggestedFix(email) != nil { report.likelyTypos.append(email) }
            if s.status == .pending && Date.daysBetween(s.createdAt, now) > 30 { report.stalePending.append(email) }
        }
        return report
    }
}

// MARK: - Campaign checks before approval

struct CampaignCheck: Identifiable, Equatable {
    enum Level: String { case error, warning, ok }
    var id: String
    var level: Level
    var message: String
}

enum CampaignLint {
    static func check(_ campaign: EmailCampaign, workspace: Workspace) -> [CampaignCheck] {
        var checks: [CampaignCheck] = []
        func add(_ id: String, _ level: CampaignCheck.Level, _ message: String) {
            checks.append(CampaignCheck(id: id, level: level, message: message))
        }
        let recipients = workspace.recipients(for: campaign.segmentID)
        if campaign.subject.isBlank { add("subject", .error, "Add a subject line.") }
        if campaign.subject.count > 80 { add("subject-length", .warning, "Subject lines over ~60–80 characters get cut off in most inboxes.") }
        let letters = campaign.subject.filter(\.isLetter)
        if letters.count > 8 && letters == letters.uppercased() { add("caps", .warning, "An all-caps subject line is more likely to be filtered as spam.") }
        if campaign.body.isBlank { add("body", .error, "The email has no body text.") }
        if campaign.segmentID != nil && workspace.segment(campaign.segmentID) == nil { add("segment-missing", .error, "The selected segment no longer exists.") }
        if recipients.isEmpty { add("recipients", .error, "No subscribed recipients match this audience.") }
        let noConsent = recipients.filter { $0.consent == nil }.count
        if noConsent > 0 { add("consent", .warning, "\(noConsent) recipient\(noConsent == 1 ? " has" : "s have") no consent record. Check where they came from before sending.") }
        if workspace.profile.communication.mailingAddress.isBlank {
            add("address", .warning, "Add a mailing address in Profile › Communication. Commercial email in the US (CAN-SPAM) must include a valid postal address.")
        }
        let body = campaign.body.lowercased()
        if !body.contains("unsubscribe") && !body.contains("*|unsub|*") && !body.contains("{{unsubscribe") {
            add("unsubscribe", .warning, "No unsubscribe link in the text. Your email provider normally adds one in its footer — keep it when you paste this in.")
        }
        if checks.isEmpty || checks.allSatisfy({ $0.level != .error }) {
            add("ok", .ok, "Ready for your review: \(recipients.count) subscribed recipient\(recipients.count == 1 ? "" : "s").")
        }
        return checks
    }

    static func hasErrors(_ checks: [CampaignCheck]) -> Bool { checks.contains { $0.level == .error } }
}

// MARK: - Campaign results from a provider report

struct CampaignResultsImport {
    var results = CampaignResults()
    var statusUpdates: [String: SubscriptionStatus] = [:]
    var unknownAddresses = 0
}

enum CampaignResultsImporter {
    /// Reads a per-recipient report (email + event/status columns) and works out delivery stats and
    /// which subscribers bounced, unsubscribed, or complained. Soft bounces are counted but not suppressed.
    static func read(csv text: String, subscribers: [Subscriber], fileName: String) -> CampaignResultsImport {
        let table = CSV.parseTable(text)
        var output = CampaignResultsImport()
        output.results.sourceFile = fileName
        let known = Set(subscribers.map { EmailAddress.normalize($0.email) })
        var recipients = Set<String>()
        for row in table.rows {
            let email = EmailAddress.normalize(CSV.value(row, SubscriberImporter.emailKeys))
            guard EmailAddress.isValid(email) else { continue }
            recipients.insert(email)
            if !known.contains(email) { output.unknownAddresses += 1 }
            let event = CSV.value(row, ["event", "status", "activity", "action", "result", "type"]).lowercased()
            let bounceType = CSV.value(row, ["bounce_type", "bounce", "bounce_category"]).lowercased()
            let opened = CSV.value(row, ["opened", "opens", "open_count"]).lowercased()
            let clicked = CSV.value(row, ["clicked", "clicks", "click_count"]).lowercased()

            if event.contains("bounce") || !bounceType.isEmpty {
                output.results.bounces += 1
                if !bounceType.contains("soft") && !event.contains("soft") { output.statusUpdates[email] = .bounced }
            } else if event.contains("unsub") {
                output.results.unsubscribes += 1
                output.results.delivered += 1
                output.statusUpdates[email] = .unsubscribed
            } else if event.contains("spam") || event.contains("complain") || event.contains("abuse") {
                output.results.complaints += 1
                output.results.delivered += 1
                output.statusUpdates[email] = .complained
            } else {
                output.results.delivered += 1
            }
            if event.contains("open") || isTruthy(opened) { output.results.opens += 1 }
            if event.contains("click") || isTruthy(clicked) { output.results.clicks += 1 }
        }
        output.results.recipients = recipients.count
        return output
    }

    private static func isTruthy(_ value: String) -> Bool {
        if ["true", "yes", "y"].contains(value) { return true }
        if let n = Int(value) { return n > 0 }
        return false
    }

    /// Applies bounces/unsubscribes/complaints. Never re-subscribes anyone.
    static func apply(_ result: CampaignResultsImport, to subscribers: inout [Subscriber], campaignName: String, now: Date = Date()) {
        for i in subscribers.indices {
            let email = EmailAddress.normalize(subscribers[i].email)
            guard let status = result.statusUpdates[email], subscribers[i].status != status else { continue }
            // Don't downgrade a stronger suppression (complaint) to a weaker one.
            if subscribers[i].status == .complained { continue }
            subscribers[i].status = status
            subscribers[i].statusChangedAt = now
            subscribers[i].statusReason = "\(status.label) — campaign “\(campaignName)”"
        }
    }
}
