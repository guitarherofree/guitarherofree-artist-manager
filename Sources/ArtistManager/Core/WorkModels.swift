import Foundation

/// Who did something. Used on records and in the activity log so the artist can always
/// tell their own work apart from work the app did on its own.
enum Actor: String, Codable, CaseIterable {
    case artist, automation, rule, importer, system
    var label: String {
        switch self {
        case .artist: return "You"
        case .automation: return "Manager (automation)"
        case .rule: return "Pre-approved rule"
        case .importer: return "Import"
        case .system: return "Manager"
        }
    }
}

enum WorkArea: String, Codable, CaseIterable, Identifiable {
    case strategy, release, press, email, marketing, live, finance, rights, team, admin, creative
    var id: String { rawValue }
    var label: String {
        switch self {
        case .strategy: return "Strategy"
        case .release: return "Release"
        case .press: return "Press"
        case .email: return "Email list"
        case .marketing: return "Marketing"
        case .live: return "Live"
        case .finance: return "Finance"
        case .rights: return "Rights"
        case .team: return "Team"
        case .admin: return "Admin"
        case .creative: return "Creative"
        }
    }
    var symbol: String {
        switch self {
        case .strategy: return "map"
        case .release: return "opticaldisc"
        case .press: return "newspaper"
        case .email: return "envelope"
        case .marketing: return "megaphone"
        case .live: return "music.mic"
        case .finance: return "dollarsign.circle"
        case .rights: return "c.circle"
        case .team: return "person.2"
        case .admin: return "tray"
        case .creative: return "paintpalette"
        }
    }
}

// MARK: - Tasks

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo, inProgress, waiting, done
    var id: String { rawValue }
    var label: String {
        switch self {
        case .todo: return "To do"
        case .inProgress: return "In progress"
        case .waiting: return "Waiting"
        case .done: return "Done"
        }
    }
}

struct TaskItem: Entity {
    var id = UUID()
    var title = ""
    var notes = ""
    var due: Date?
    var status: TaskStatus = .todo
    var area: WorkArea = .admin
    var priority: Priority = .normal
    var releaseID: UUID?
    var contactID: UUID?
    var createdBy: Actor = .artist
    /// Set on tasks generated from a template so automation never duplicates them.
    var templateKey: String?
    var estimatedHours: Double = 1
    var createdAt = Date()
    var completedAt: Date?

    var isOpen: Bool { status != .done }

    func isOverdue(now: Date = Date()) -> Bool {
        guard isOpen, let due else { return false }
        return due.startOfDay < now.startOfDay
    }
}

// MARK: - Releases

enum ReleaseType: String, Codable, CaseIterable, Identifiable {
    case single, ep, album
    var id: String { rawValue }
    var label: String {
        switch self {
        case .single: return "Single"
        case .ep: return "EP"
        case .album: return "Album"
        }
    }
    /// How much earlier than a single the campaign should start.
    var leadTimeMultiplier: Double {
        switch self {
        case .single: return 1.0
        case .ep: return 1.25
        case .album: return 1.6
        }
    }
}

enum ReleaseStage: String, Codable, CaseIterable, Identifiable {
    case idea, planning, production, delivered, released, archived
    var id: String { rawValue }
    var label: String {
        switch self {
        case .idea: return "Idea"
        case .planning: return "Planning"
        case .production: return "In production"
        case .delivered: return "Delivered to distributor"
        case .released: return "Released"
        case .archived: return "Archived"
        }
    }
    var isActive: Bool { self != .released && self != .archived }
}

enum AssetStatus: String, Codable, CaseIterable, Identifiable {
    case notStarted, inProgress, final
    var id: String { rawValue }
    var label: String {
        switch self {
        case .notStarted: return "Not started"
        case .inProgress: return "In progress"
        case .final: return "Final"
        }
    }
}

struct Split: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = ""
    var role = "Writer"
    var share: Double = 0
    var pro = ""
    var ipi = ""
}

struct Track: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = ""
    var version = ""
    var isrc = ""
    var iswc = ""
    var durationSeconds = 0
    var explicit = false
    var featuredArtists = ""
    var producers = ""
    var writers: [Split] = []
    var mastered = false

    var splitTotal: Double { writers.reduce(0) { $0 + $1.share } }
}

enum AssetKind: String, Codable, CaseIterable, Identifiable {
    case artwork, canvas, video, lyricVideo, photo, audio, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .artwork: return "Cover artwork"
        case .canvas: return "Spotify Canvas"
        case .video: return "Music video"
        case .lyricVideo: return "Lyric video"
        case .photo: return "Photos"
        case .audio: return "Audio files"
        case .other: return "Other"
        }
    }
}

struct AssetItem: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = ""
    var kind: AssetKind = .other
    var status: AssetStatus = .notStarted
    var location = ""   // file path or link
}

struct Release: Entity {
    var id = UUID()
    var title = ""
    var type: ReleaseType = .single
    var stage: ReleaseStage = .planning
    var releaseDate: Date?
    var distributor = ""
    var label = ""
    var upc = ""
    var primaryGenre = ""
    var artworkStatus: AssetStatus = .notStarted
    var artworkNotes = ""
    var preSaveURL = ""
    var smartLinkURL = ""
    var tracks: [Track] = []
    var assets: [AssetItem] = []
    var budget: Double = 0
    var notes = ""
    /// Date the campaign timeline was generated for, so automation can offer to reschedule.
    var timelineGeneratedFor: Date?
    var createdAt = Date()
}

// MARK: - Budget

enum BudgetCategory: String, Codable, CaseIterable, Identifiable {
    case recording, mixing, mastering, artwork, video, advertising, publicity, playlistPitching, distribution, travel, merch, gear, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .recording: return "Recording"
        case .mixing: return "Mixing"
        case .mastering: return "Mastering"
        case .artwork: return "Artwork & design"
        case .video: return "Video"
        case .advertising: return "Advertising"
        case .publicity: return "Publicity"
        case .playlistPitching: return "Playlist pitching"
        case .distribution: return "Distribution"
        case .travel: return "Travel"
        case .merch: return "Merch"
        case .gear: return "Gear"
        case .other: return "Other"
        }
    }
}

enum BudgetStatus: String, Codable, CaseIterable, Identifiable {
    case planned, awaitingApproval, approved, paid, cancelled
    var id: String { rawValue }
    var label: String {
        switch self {
        case .planned: return "Planned"
        case .awaitingApproval: return "Awaiting approval"
        case .approved: return "Approved to spend"
        case .paid: return "Paid"
        case .cancelled: return "Cancelled"
        }
    }
    var countsTowardSpend: Bool { self != .cancelled }
}

struct BudgetLine: Entity {
    var id = UUID()
    var releaseID: UUID?
    var category: BudgetCategory = .other
    var title = ""
    var vendor = ""
    var planned: Double = 0
    var actual: Double = 0
    var status: BudgetStatus = .planned
    var date: Date?
    var notes = ""
    var createdBy: Actor = .artist

    /// What this line costs or is expected to cost.
    var effectiveAmount: Double { status == .paid ? max(actual, 0) : max(planned, actual) }
}

// MARK: - Calendar

enum EventKind: String, Codable, CaseIterable, Identifiable {
    case show, release, deadline, studio, rehearsal, meeting, press, travel, personal, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .show: return "Show"
        case .release: return "Release"
        case .deadline: return "Deadline"
        case .studio: return "Studio"
        case .rehearsal: return "Rehearsal"
        case .meeting: return "Meeting"
        case .press: return "Press / interview"
        case .travel: return "Travel"
        case .personal: return "Personal"
        case .other: return "Other"
        }
    }
    var symbol: String {
        switch self {
        case .show: return "music.mic"
        case .release: return "opticaldisc"
        case .deadline: return "flag"
        case .studio: return "slider.horizontal.3"
        case .rehearsal: return "metronome"
        case .meeting: return "person.2"
        case .press: return "mic"
        case .travel: return "car"
        case .personal: return "person"
        case .other: return "calendar"
        }
    }
}

struct CalendarEvent: Entity {
    var id = UUID()
    var title = ""
    var kind: EventKind = .other
    var start = Date()
    var end = Date().adding(hours: 1)
    var isAllDay = false
    var location = ""
    var notes = ""
    var releaseID: UUID?
    var contactIDs: [UUID] = []
    var createdBy: Actor = .artist
    /// Dedupe key for generated events (release days) or the UID of an imported .ics event.
    var sourceKey: String?

    /// The half-open interval this event occupies; all-day events cover their whole days.
    var interval: DateInterval {
        if isAllDay {
            let s = start.startOfDay
            let e = max(end.startOfDay, s).adding(days: 1)
            return DateInterval(start: s, end: e)
        }
        return DateInterval(start: start, end: max(end, start))
    }
}

// MARK: - Contacts

enum ContactRole: String, Codable, CaseIterable, Identifiable {
    case manager, bookingAgent, attorney, accountant, businessManager, label, publisher, publicist, distributor
    case journalist, playlistCurator, radio, promoter, venue, producer, engineer, musician, designer
    case photographer, videographer, syncAgent, musicSupervisor, brand, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .manager: return "Manager"
        case .bookingAgent: return "Booking agent"
        case .attorney: return "Attorney"
        case .accountant: return "Accountant"
        case .businessManager: return "Business manager"
        case .label: return "Label"
        case .publisher: return "Publisher"
        case .publicist: return "Publicist"
        case .distributor: return "Distributor"
        case .journalist: return "Journalist / blogger"
        case .playlistCurator: return "Playlist curator"
        case .radio: return "Radio"
        case .promoter: return "Promoter"
        case .venue: return "Venue"
        case .producer: return "Producer"
        case .engineer: return "Engineer"
        case .musician: return "Musician"
        case .designer: return "Designer"
        case .photographer: return "Photographer"
        case .videographer: return "Videographer"
        case .syncAgent: return "Sync agent"
        case .musicSupervisor: return "Music supervisor"
        case .brand: return "Brand / sponsor"
        case .other: return "Other"
        }
    }
    var isMedia: Bool { [.journalist, .playlistCurator, .radio].contains(self) }
    var isIndustry: Bool { ![.musician, .other].contains(self) }
}

enum InteractionChannel: String, Codable, CaseIterable, Identifiable {
    case email, call, meeting, message, inPerson, note
    var id: String { rawValue }
    var label: String {
        switch self {
        case .email: return "Email"
        case .call: return "Call"
        case .meeting: return "Meeting"
        case .message: return "Message"
        case .inPerson: return "In person"
        case .note: return "Note"
        }
    }
}

struct Interaction: Codable, Equatable, Identifiable {
    var id = UUID()
    var date = Date()
    var channel: InteractionChannel = .email
    var summary = ""
}

struct Contact: Entity {
    var id = UUID()
    var name = ""
    var organization = ""
    var role: ContactRole = .other
    var email = ""
    var phone = ""
    var website = ""
    var location = ""
    var tags: [String] = []
    var isTeamMember = false
    var responsibilities = ""
    var notes = ""
    var interactions: [Interaction] = []
    var nextFollowUp: Date?
    var followUpReason = ""
    var createdAt = Date()

    var lastContacted: Date? { interactions.map(\.date).max() }
    var displayName: String { name.isBlank ? (organization.isBlank ? "Unnamed contact" : organization) : name }
}
