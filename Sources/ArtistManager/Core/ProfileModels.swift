import Foundation

// MARK: - Artist profile (captured during onboarding, editable any time)

struct ArtistProfile: Codable, Equatable {
    var artistName = ""
    var legalName = ""
    var pronouns = ""
    var location = ""
    var country = "US"
    var genres: [String] = []
    var soundDescription = ""
    var influences = ""
    var positioning = ""
    var visualIdentity = ""
    var bioShort = ""
    var bioLong = ""
    var links = MusicLinks()
    var audience = AudienceProfile()
    var budget = BudgetSettings()
    var availability = Availability()
    var communication = CommunicationPreferences()
    var rightsMemberships: [RightsMembership] = []
    var onboardingCompleted = false
    var updatedAt: Date?

    var displayName: String { artistName.isBlank ? "Your artist name" : artistName }

    var isUnitedStates: Bool {
        let c = country.trimmed.lowercased()
        return c == "us" || c == "usa" || c == "united states" || c == "united states of america"
    }
}

struct MusicLinks: Codable, Equatable {
    var website = ""
    var spotify = ""
    var appleMusic = ""
    var bandcamp = ""
    var youtube = ""
    var soundcloud = ""
    var instagram = ""
    var tiktok = ""
    var other = ""

    /// Non-empty links with display labels, in a stable order.
    var labeled: [(label: String, url: String)] {
        [("Website", website), ("Spotify", spotify), ("Apple Music", appleMusic), ("Bandcamp", bandcamp),
         ("YouTube", youtube), ("SoundCloud", soundcloud), ("Instagram", instagram), ("TikTok", tiktok),
         ("Other", other)]
            .filter { !$0.1.isBlank }
            .map { (label: $0.0, url: $0.1.trimmed) }
    }
}

struct AudienceProfile: Codable, Equatable {
    var description = ""
    var topMarkets = ""          // comma-separated cities/regions
    var ageRange = ""
    var discoveryChannels = ""   // where fans find music
    var comparableArtists = ""
}

struct BudgetSettings: Codable, Equatable {
    var currency = "USD"
    var monthlyMarketingBudget: Double = 0
    var annualBudget: Double = 0
    var notes = ""
}

struct DateRange: Codable, Equatable, Identifiable {
    var id = UUID()
    var start: Date
    var end: Date
    var reason = ""

    func contains(_ date: Date) -> Bool {
        let day = date.startOfDay
        return day >= start.startOfDay && day <= end.startOfDay
    }
}

struct Availability: Codable, Equatable {
    var hoursPerWeek: Double = 10
    /// Weekdays the artist works on career tasks (1 = Sunday … 7 = Saturday).
    var workDays: [Int] = [2, 3, 4, 5, 6]
    var blackoutDates: [DateRange] = []
    var notes = ""

    func isBlackedOut(_ date: Date) -> Bool {
        blackoutDates.contains { $0.contains(date) }
    }
}

enum DraftTone: String, Codable, CaseIterable, Identifiable {
    case warm, professional, brief, playful
    var id: String { rawValue }
    var label: String {
        switch self {
        case .warm: return "Warm and personal"
        case .professional: return "Professional"
        case .brief: return "Short and direct"
        case .playful: return "Playful"
        }
    }
}

struct CommunicationPreferences: Codable, Equatable {
    var draftTone: DraftTone = .warm
    var signOff = ""
    var replyEmail = ""
    /// Required in commercial email footers in many places (e.g. CAN-SPAM in the US).
    var mailingAddress = ""
    var notifyForApprovals = true
    var notifyForDeadlines = true
    var deadlineWarningDays = 3
}

enum RightsOrgType: String, Codable, CaseIterable, Identifiable {
    case performingRights, mechanical, neighboringRights, publisherAdmin, distributor, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .performingRights: return "Performing rights (PRO)"
        case .mechanical: return "Mechanical licensing"
        case .neighboringRights: return "Neighboring rights / digital performance"
        case .publisherAdmin: return "Publishing administrator"
        case .distributor: return "Distributor"
        case .other: return "Other"
        }
    }
}

enum RegistrationStatus: String, Codable, CaseIterable, Identifiable {
    case notStarted, inProgress, registered
    var id: String { rawValue }
    var label: String {
        switch self {
        case .notStarted: return "Not started"
        case .inProgress: return "In progress"
        case .registered: return "Registered"
        }
    }
}

struct RightsMembership: Codable, Equatable, Identifiable {
    var id = UUID()
    var organization = ""
    var type: RightsOrgType = .performingRights
    var status: RegistrationStatus = .notStarted
    var notes = ""
}

// MARK: - Goals and plan

enum GoalCategory: String, Codable, CaseIterable, Identifiable {
    case audience, streaming, live, revenue, press, creative, deals, rights
    var id: String { rawValue }
    var label: String {
        switch self {
        case .audience: return "Grow audience"
        case .streaming: return "Streaming"
        case .live: return "Live and touring"
        case .revenue: return "Income"
        case .press: return "Press and media"
        case .creative: return "Creative output"
        case .deals: return "Deals and partnerships"
        case .rights: return "Rights and royalties"
        }
    }
    var symbol: String {
        switch self {
        case .audience: return "person.3"
        case .streaming: return "waveform"
        case .live: return "music.mic"
        case .revenue: return "dollarsign.circle"
        case .press: return "newspaper"
        case .creative: return "paintpalette"
        case .deals: return "signature"
        case .rights: return "c.circle"
        }
    }
}

enum GoalStatus: String, Codable, CaseIterable, Identifiable {
    case notStarted, inProgress, achieved, paused
    var id: String { rawValue }
    var label: String {
        switch self {
        case .notStarted: return "Not started"
        case .inProgress: return "In progress"
        case .achieved: return "Achieved"
        case .paused: return "Paused"
        }
    }
}

struct CareerGoal: Entity {
    var id = UUID()
    var title = ""
    var category: GoalCategory = .audience
    var metric = ""
    var targetDate: Date?
    var status: GoalStatus = .notStarted
    var notes = ""
}

enum RecommendationStatus: String, Codable, CaseIterable, Identifiable {
    case open, accepted, done, dismissed, resolved
    var id: String { rawValue }
    var label: String {
        switch self {
        case .open: return "Recommended"
        case .accepted: return "Added to tasks"
        case .done: return "Done"
        case .dismissed: return "Dismissed"
        case .resolved: return "No longer needed"
        }
    }
}

enum Priority: String, Codable, CaseIterable, Identifiable, Comparable {
    case low, normal, high
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var rank: Int {
        switch self {
        case .low: return 0
        case .normal: return 1
        case .high: return 2
        }
    }
    static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rank < rhs.rank }
}

/// Where in the app a recommendation's next step lives.
enum AppDestination: String, Codable, CaseIterable {
    case today, plan, profile, releases, press, coverage, targets, email, calendar, tasks, contacts, approvals, integrations, roadmap
}

struct Recommendation: Entity {
    var id = UUID()
    /// Stable key for the rule that produced this, so refreshing the plan updates rather than duplicates.
    var ruleKey: String
    var title: String
    var detail: String
    var rationale: String
    var area: WorkArea
    var priority: Priority = .normal
    var destination: AppDestination = .plan
    /// A tab on the destination page, e.g. "playlists" on Press Kit.
    var destinationTab: String? = nil
    var suggestedDue: Date?
    var relatedID: UUID?
    var status: RecommendationStatus = .open
    var createdAt = Date()
    var updatedAt = Date()
}

struct Milestone: Identifiable, Equatable {
    var id: String
    var title: String
    var date: Date?
    var area: WorkArea
    var isComplete: Bool
}
