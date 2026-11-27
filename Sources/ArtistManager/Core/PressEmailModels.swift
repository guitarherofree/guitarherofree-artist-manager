import Foundation

// MARK: - Electronic press kit

struct ContactCard: Codable, Equatable {
    var name = ""
    var organization = ""
    var email = ""
    var phone = ""

    var isEmpty: Bool { name.isBlank && email.isBlank && phone.isBlank }
}

struct PressPhoto: Codable, Equatable, Identifiable {
    var id = UUID()
    /// File name inside the app's Media folder.
    var fileName = ""
    var caption = ""
    var photographerCredit = ""
    var isPrimary = false
}

struct FeaturedTrack: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = ""
    var url = ""
}

struct PressKit: Codable, Equatable {
    var headline = ""
    var photos: [PressPhoto] = []
    var featuredTracks: [FeaturedTrack] = []
    var credits = ""
    var achievements = ""
    var bookingContact = ContactCard()
    var publicityContact = ContactCard()
    var technicalRider = ""
    var updatedAt: Date?
}

enum CoverageKind: String, Codable, CaseIterable, Identifiable {
    case review, article, interview, feature, premiere, mention, podcast, radioPlay, video, playlistAdd
    var id: String { rawValue }
    var label: String {
        switch self {
        case .review: return "Review"
        case .article: return "Article / news"
        case .interview: return "Interview"
        case .feature: return "Feature"
        case .premiere: return "Premiere"
        case .mention: return "Mention"
        case .podcast: return "Podcast"
        case .radioPlay: return "Radio play"
        case .video: return "TV / video"
        case .playlistAdd: return "Playlist add"
        }
    }
    var pluralLabel: String {
        switch self {
        case .review: return "reviews"
        case .article: return "articles"
        case .interview: return "interviews"
        case .feature: return "features"
        case .premiere: return "premieres"
        case .mention: return "mentions"
        case .podcast: return "podcasts"
        case .radioPlay: return "radio plays"
        case .video: return "videos"
        case .playlistAdd: return "playlist adds"
        }
    }
    var symbol: String {
        switch self {
        case .review: return "star.bubble"
        case .article: return "newspaper"
        case .interview: return "mic"
        case .feature: return "doc.richtext"
        case .premiere: return "sparkles"
        case .mention: return "quote.bubble"
        case .podcast: return "headphones"
        case .radioPlay: return "radio"
        case .video: return "play.rectangle"
        case .playlistAdd: return "music.note.list"
        }
    }
}

/// A file kept with a piece of coverage: a PDF, a scan of a print clipping, a screenshot, an audio clip.
struct CoverageAttachment: Codable, Equatable, Identifiable {
    var id = UUID()
    /// Path inside the media folder, e.g. "Coverage/<id>.pdf".
    var fileName = ""
    var originalName = ""
}

struct Coverage: Entity {
    var id = UUID()
    var outlet = ""
    var title = ""
    var url = ""
    var date: Date?
    var kind: CoverageKind = .feature
    var quote = ""
    var includeInPressKit = true
    var releaseID: UUID?
    var contactID: UUID?
    /// True when the link was opened (by the artist or a link check) and the page was there.
    var verified = false
    var author = ""
    /// A review score as the outlet gives it, e.g. "8.2/10" or "4/5".
    var rating = ""
    /// The outlet's own summary of the piece, or the artist's notes.
    var excerpt = ""
    var notes = ""
    /// A copy of the page saved when the coverage was added, inside the media folder.
    var savedCopy: String? = nil
    var attachments: [CoverageAttachment] = []
    var linkCheckedAt: Date? = nil
    /// What went wrong the last time the link was checked, e.g. "Page not found (404)". Empty when it worked.
    var linkIssue = ""
    var addedAt: Date? = nil

    var headline: String {
        let name = outlet.isBlank ? "Unknown outlet" : outlet
        return title.isBlank ? "\(name): \(kind.label)" : "\(name): \(title)"
    }

    /// How the piece is credited under a pull quote: "Jane Doe, Paste (8.2/10)".
    var citation: String {
        var s = [author, outlet.isBlank ? "Unknown outlet" : outlet].filter { !$0.isBlank }.joined(separator: ", ")
        if !rating.isBlank { s += " (\(rating))" }
        return s
    }

    var fileNames: [String] { (savedCopy.map { [$0] } ?? []) + attachments.map(\.fileName) }
}

enum PressReleaseStatus: String, Codable, CaseIterable, Identifiable {
    case draft, ready, distributed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .draft: return "Draft"
        case .ready: return "Final — not distributed"
        case .distributed: return "Distributed (confirmed by you)"
        }
    }
}

struct PressRelease: Entity {
    var id = UUID()
    var headline = ""
    var subheadline = ""
    var dateline = ""
    var publishDate: Date?
    var body = ""
    var releaseID: UUID?
    var status: PressReleaseStatus = .draft
    var createdAt = Date()
    var createdBy: Actor = .artist
}

// MARK: - Outreach (press pitches, playlist pitches, follow-ups, reminders)

enum OutreachKind: String, Codable, CaseIterable, Identifiable {
    case press, review, playlist, spotifyEditorial, radio, label, booking, sync, partnership, followUp, reminder, general
    var id: String { rawValue }
    var label: String {
        switch self {
        case .press: return "Press pitch"
        case .review: return "Review request"
        case .playlist: return "Playlist curator pitch"
        case .spotifyEditorial: return "Spotify editorial pitch"
        case .radio: return "Radio pitch"
        case .label: return "Label pitch"
        case .booking: return "Booking inquiry"
        case .sync: return "Sync submission"
        case .partnership: return "Partnership"
        case .followUp: return "Follow-up"
        case .reminder: return "Reminder"
        case .general: return "Message"
        }
    }
    var permission: ActionKind {
        switch self {
        case .press, .review, .playlist, .spotifyEditorial, .radio: return .sendPressOutreach
        default: return .sendExternalMessage
        }
    }
    var isMediaPitch: Bool { [.press, .review, .playlist, .spotifyEditorial, .radio].contains(self) }
    /// Sent to a person by email (everything except the Spotify for Artists form).
    var isEmail: Bool { self != .spotifyEditorial }
    /// The contact roles a batch of this kind of pitch is usually for.
    var suggestedRoles: [ContactRole] {
        switch self {
        case .press, .review: return [.journalist]
        case .playlist: return [.playlistCurator]
        case .radio: return [.radio]
        case .label: return [.label]
        case .booking: return [.venue, .promoter, .bookingAgent]
        case .sync: return [.musicSupervisor, .syncAgent]
        case .partnership: return [.brand]
        default: return []
        }
    }
}

// MARK: - Spotify editorial pitch

/// The pitch form in Spotify for Artists (Music › Upcoming). Spotify takes one unreleased song per
/// artist at a time. Pitches made at least 7 days before release also reach followers' Release Radar;
/// about four weeks ahead gives editors time to listen. There's no public API, so the artist submits it.
struct EditorialPitch: Codable, Equatable {
    static let maxDescription = 500
    static let maxSubgenres = 3
    static let minimumLeadDays = 7
    static let recommendedLeadDays = 28
    static let submitURL = URL(string: "https://artists.spotify.com/")!

    var trackID: UUID?
    var trackTitle = ""
    var primaryGenre = ""
    var subgenres: [String] = []
    var moods: [String] = []
    var styles: [String] = []
    var instruments: [String] = []
    var culture = ""
    var language = ""
    var hometown = ""
    var currentLocation = ""
    var description = ""
    /// What the artist plans around the release (press, shows, ads), for their own reference in the pitch.
    var marketingNotes = ""

    struct Issue: Equatable, Identifiable {
        enum Level: Equatable { case error, warning }
        var id: String
        var level: Level
        var message: String
    }

    func issues(releaseDate: Date?, now: Date = Date()) -> [Issue] {
        var out: [Issue] = []
        func add(_ id: String, _ level: Issue.Level, _ message: String) { out.append(Issue(id: id, level: level, message: message)) }
        if trackTitle.isBlank { add("track", .error, "Choose the song to pitch. Spotify takes one song per release.") }
        if primaryGenre.isBlank { add("genre", .error, "Choose a main genre.") }
        if subgenres.count > Self.maxSubgenres { add("subgenres", .error, "Spotify allows up to \(Self.maxSubgenres) subgenres.") }
        if description.isBlank { add("description", .error, "Write the description editors will read.") }
        if description.count > Self.maxDescription {
            add("length", .error, "The description is \(description.count) characters; Spotify allows \(Self.maxDescription).")
        }
        if description.contains("[") { add("placeholders", .warning, "Fill in or remove the parts in [brackets].") }
        if moods.isEmpty { add("moods", .warning, "Add a few moods. Editors use them to route the song to the right playlists.") }
        if hometown.isBlank && currentLocation.isBlank { add("location", .warning, "Add your hometown or where you're based; editors look for local scenes.") }
        if let releaseDate {
            let days = Date.daysBetween(now, releaseDate)
            if days < 0 {
                add("released", .error, "This song is already out. Spotify only takes pitches for unreleased music.")
            } else if days < Self.minimumLeadDays {
                add("late", .warning, "Release day is \(days) day\(days == 1 ? "" : "s") away. Pitches sent less than 7 days ahead miss your followers' Release Radar.")
            } else if days < Self.recommendedLeadDays {
                add("early", .warning, "Editors need time to listen; about four weeks ahead is best. Submit as soon as you can.")
            }
        } else {
            add("date", .warning, "The release has no date yet.")
        }
        return out
    }

    /// Every field, in the order the form asks for them, to paste from.
    var formText: String {
        var lines = ["Song: \(trackTitle)", "Main genre: \(primaryGenre)"]
        if !subgenres.isEmpty { lines.append("Subgenres: \(subgenres.commaJoined)") }
        if !moods.isEmpty { lines.append("Moods: \(moods.commaJoined)") }
        if !styles.isEmpty { lines.append("Styles: \(styles.commaJoined)") }
        if !instruments.isEmpty { lines.append("Instruments: \(instruments.commaJoined)") }
        if !culture.isBlank { lines.append("Culture: \(culture)") }
        if !language.isBlank { lines.append("Language: \(language)") }
        if !hometown.isBlank { lines.append("Hometown: \(hometown)") }
        if !currentLocation.isBlank { lines.append("Based in: \(currentLocation)") }
        lines.append("")
        lines.append("Description (\(description.count)/\(Self.maxDescription)):")
        lines.append(description)
        return lines.joined(separator: "\n")
    }

    /// Latest day to submit and still reach Release Radar.
    static func deadline(for releaseDate: Date) -> Date { releaseDate.startOfDay.adding(days: -minimumLeadDays) }
    static func recommendedDate(for releaseDate: Date) -> Date { releaseDate.startOfDay.adding(days: -recommendedLeadDays) }
}

enum OutreachStatus: String, Codable, CaseIterable, Identifiable {
    case draft, awaitingApproval, approved, sent, replied, covered, declined, noResponse
    var id: String { rawValue }
    var label: String {
        switch self {
        case .draft: return "Draft"
        case .awaitingApproval: return "Awaiting your approval"
        case .approved: return "Approved — not sent yet"
        case .sent: return "Sent (confirmed by you)"
        case .replied: return "Replied"
        case .covered: return "Resulted in coverage"
        case .declined: return "Passed"
        case .noResponse: return "No response"
        }
    }
    var isClosed: Bool { [.replied, .covered, .declined, .noResponse].contains(self) }
}

struct Outreach: Entity {
    var id = UUID()
    var kind: OutreachKind = .press
    var contactID: UUID?
    var releaseID: UUID?
    var subject = ""
    var body = ""
    var status: OutreachStatus = .draft
    var createdAt = Date()
    var createdBy: Actor = .artist
    var approvedAt: Date?
    var approvedByRule: String?
    var sentAt: Date?
    var followUpDue: Date?
    var responseNotes = ""
    var parentID: UUID?
    var templateKey: String?
    /// The Spotify for Artists form fields, for Spotify editorial pitches.
    var editorial: EditorialPitch? = nil
}

// MARK: - Email audience

enum SubscriptionStatus: String, Codable, CaseIterable, Identifiable {
    case subscribed, pending, unsubscribed, bounced, complained, cleaned
    var id: String { rawValue }
    var label: String {
        switch self {
        case .subscribed: return "Subscribed"
        case .pending: return "Pending confirmation"
        case .unsubscribed: return "Unsubscribed"
        case .bounced: return "Bounced"
        case .complained: return "Marked as spam"
        case .cleaned: return "Cleaned"
        }
    }
    /// Suppressed addresses must never be emailed or silently re-subscribed by an import.
    var isSuppressed: Bool { [.unsubscribed, .bounced, .complained, .cleaned].contains(self) }
    var canReceiveCampaigns: Bool { self == .subscribed }

    /// Maps the status words common email providers use in their exports.
    static func parse(_ raw: String) -> SubscriptionStatus? {
        let value = raw.trimmed.lowercased()
        switch value {
        case "subscribed", "active", "confirmed", "opted in", "opt-in", "optin", "yes", "true", "member":
            return .subscribed
        case "pending", "unconfirmed", "awaiting confirmation":
            return .pending
        case "unsubscribed", "unsubscribe", "opted out", "opt-out", "optout", "inactive", "no", "false":
            return .unsubscribed
        case "bounced", "bounce", "hard bounce", "hard_bounce", "hardbounce", "undeliverable":
            return .bounced
        case "complained", "complaint", "spam", "spam complaint", "abuse":
            return .complained
        case "cleaned", "clean", "invalid":
            return .cleaned
        default:
            return nil
        }
    }
}

enum ConsentMethod: String, Codable, CaseIterable, Identifiable {
    case webForm, doubleOptIn, inPerson, importedFromProvider, manual, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .webForm: return "Signup form"
        case .doubleOptIn: return "Signup form (double opt-in)"
        case .inPerson: return "In person (e.g. merch table)"
        case .importedFromProvider: return "Imported from email provider"
        case .manual: return "Added manually"
        case .other: return "Other"
        }
    }
}

struct ConsentRecord: Codable, Equatable {
    var method: ConsentMethod = .manual
    var source = ""
    var capturedAt: Date?
    var evidence = ""
}

struct Subscriber: Entity {
    var id = UUID()
    var email = ""
    var firstName = ""
    var lastName = ""
    var status: SubscriptionStatus = .subscribed
    var consent: ConsentRecord?
    var signupSource = ""
    var tags: [String] = []
    var location = ""
    var createdAt = Date()
    var statusChangedAt: Date?
    var statusReason = ""

    var fullName: String { [firstName, lastName].filter { !$0.isBlank }.joined(separator: " ") }
}

struct SegmentRules: Codable, Equatable {
    var anyTags: [String] = []
    var sources: [String] = []
    var locationContains = ""
    var signedUpAfter: Date?
    var signedUpBefore: Date?
    var requireConsentRecord = false

    func matches(_ subscriber: Subscriber) -> Bool {
        if !anyTags.isEmpty {
            let tags = Set(subscriber.tags.map { $0.lowercased() })
            if !anyTags.contains(where: { tags.contains($0.lowercased()) }) { return false }
        }
        if !sources.isEmpty {
            let source = subscriber.signupSource.lowercased()
            if !sources.contains(where: { $0.lowercased() == source }) { return false }
        }
        if !locationContains.isBlank,
           !subscriber.location.lowercased().contains(locationContains.trimmed.lowercased()) {
            return false
        }
        if let after = signedUpAfter, subscriber.createdAt < after.startOfDay { return false }
        if let before = signedUpBefore, subscriber.createdAt >= before.startOfDay.adding(days: 1) { return false }
        if requireConsentRecord && subscriber.consent == nil { return false }
        return true
    }
}

struct Segment: Entity {
    var id = UUID()
    var name = ""
    var rules = SegmentRules()
    var notes = ""
}

enum CampaignStatus: String, Codable, CaseIterable, Identifiable {
    case draft, awaitingApproval, approved, exported, sent, cancelled
    var id: String { rawValue }
    var label: String {
        switch self {
        case .draft: return "Draft"
        case .awaitingApproval: return "Awaiting your approval"
        case .approved: return "Approved — not sent"
        case .exported: return "Exported to provider — not sent"
        case .sent: return "Sent (confirmed by you)"
        case .cancelled: return "Cancelled"
        }
    }
}

struct CampaignResults: Codable, Equatable {
    var recipients = 0
    var delivered = 0
    var opens = 0
    var clicks = 0
    var bounces = 0
    var unsubscribes = 0
    var complaints = 0
    var importedAt = Date()
    var sourceFile = ""
}

struct EmailCampaign: Entity {
    var id = UUID()
    var name = ""
    var subject = ""
    var preheader = ""
    var body = ""
    /// nil means "everyone who is subscribed".
    var segmentID: UUID?
    var releaseID: UUID?
    var scheduledFor: Date?
    var status: CampaignStatus = .draft
    var createdAt = Date()
    var createdBy: Actor = .artist
    var approvedAt: Date?
    var approvedRecipientCount = 0
    var exportedAt: Date?
    var sentAt: Date?
    var results: CampaignResults?
}
