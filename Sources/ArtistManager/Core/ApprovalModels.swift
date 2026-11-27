import Foundation

// MARK: - What kinds of actions exist, and what the artist allows

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    // External or binding actions — always require the artist's approval.
    case sendExternalMessage
    case sendPressOutreach
    case sendEmailCampaign
    case publishContent
    case acceptOffer
    case spendMoney
    case contractualCommitment

    // Routine work the artist can let the app do on its own.
    case organizeData
    case updateCalendar
    case createTasks
    case draftMaterials
    case trackBudget
    case refreshPlan
    case sendPreApprovedReminders

    // Bookkeeping for the artist's own edits.
    case editRecord
    case importData
    case exportData
    case approvalDecision
    case undo

    var id: String { rawValue }

    /// Anything that leaves the app, commits money, or binds the artist. Never automatic.
    var alwaysRequiresApproval: Bool {
        switch self {
        case .sendExternalMessage, .sendPressOutreach, .sendEmailCampaign, .publishContent,
             .acceptOffer, .spendMoney, .contractualCommitment:
            return true
        default:
            return false
        }
    }

    /// Routine actions the artist can switch between automatic / ask first / off.
    var isConfigurable: Bool {
        switch self {
        case .organizeData, .updateCalendar, .createTasks, .draftMaterials, .trackBudget,
             .refreshPlan, .sendPreApprovedReminders:
            return true
        default:
            return false
        }
    }

    var defaultMode: PermissionMode {
        if alwaysRequiresApproval { return .askFirst }
        switch self {
        case .sendPreApprovedReminders: return .askFirst
        default: return .automatic
        }
    }

    var label: String {
        switch self {
        case .sendExternalMessage: return "Send messages to other people"
        case .sendPressOutreach: return "Send press and playlist pitches"
        case .sendEmailCampaign: return "Send email campaigns to subscribers"
        case .publishContent: return "Publish content"
        case .acceptOffer: return "Accept offers (shows, deals, sync)"
        case .spendMoney: return "Spend money"
        case .contractualCommitment: return "Make contractual or financial commitments"
        case .organizeData: return "Organize records"
        case .updateCalendar: return "Add release days and deadlines to the calendar"
        case .createTasks: return "Create tasks from release timelines and follow-ups"
        case .draftMaterials: return "Draft pitches, follow-ups and press releases"
        case .trackBudget: return "Watch budgets and flag overspending"
        case .refreshPlan: return "Refresh career plan recommendations"
        case .sendPreApprovedReminders: return "Approve reminders that match your reminder templates"
        case .editRecord: return "Edit records"
        case .importData: return "Import data"
        case .exportData: return "Export data"
        case .approvalDecision: return "Approval decision"
        case .undo: return "Undo"
        }
    }

    var explanation: String {
        switch self {
        case .sendExternalMessage, .sendPressOutreach, .sendEmailCampaign, .publishContent,
             .acceptOffer, .spendMoney, .contractualCommitment:
            return "Always asks you first. This can't be made automatic."
        case .organizeData: return "Tidy tags, link records together and flag duplicates."
        case .updateCalendar: return "Put release days from your releases on the calendar."
        case .createTasks: return "Add campaign tasks when a release gets a date, and follow-up tasks for contacts."
        case .draftMaterials: return "Write drafts only. Drafts are never sent without your approval."
        case .trackBudget: return "Include budget warnings in your plan."
        case .refreshPlan: return "Update next-step recommendations as your data changes."
        case .sendPreApprovedReminders: return "Reminders to people on your team (e.g. before a show) can be marked approved by rule. You still send them."
        default: return ""
        }
    }
}

enum PermissionMode: String, Codable, CaseIterable, Identifiable {
    case automatic, askFirst, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .automatic: return "Do it automatically"
        case .askFirst: return "Ask me first"
        case .off: return "Don't do this"
        }
    }
}

struct PermissionPolicy: Codable, Equatable {
    /// Keyed by `ActionKind.rawValue`.
    var modes: [String: PermissionMode] = [:]

    func mode(for kind: ActionKind) -> PermissionMode {
        if kind.alwaysRequiresApproval { return .askFirst }
        if !kind.isConfigurable { return .automatic }
        return modes[kind.rawValue] ?? kind.defaultMode
    }

    mutating func set(_ mode: PermissionMode, for kind: ActionKind) {
        guard kind.isConfigurable else { return }
        modes[kind.rawValue] = mode
    }
}

struct AppSettings: Codable, Equatable {
    var automationEnabled = true
    var followUpAfterDays = 7
    var teamCheckInDays = 30
    var reminderLeadDays = 2
    var lastAutomationRun: Date?
}

// MARK: - Approval requests

enum ApprovalState: String, Codable, CaseIterable, Identifiable {
    case pending, approved, declined, superseded
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pending: return "Waiting for you"
        case .approved: return "Approved"
        case .declined: return "Declined"
        case .superseded: return "Replaced by a newer version"
        }
    }
}

/// Housekeeping that changes existing records. Stored as operations (not copies of records) so an
/// "ask first" suggestion approved later is worked out against the data as it is then.
enum OrganizeOperation: Codable, Equatable {
    /// A release marked "delivered" whose date has passed becomes "released".
    case markReleased(UUID)
    /// Trims tags and removes case-insensitive duplicates on contacts.
    case tidyContactTags
    /// Trims tags and removes case-insensitive duplicates on subscribers.
    case tidySubscriberTags

    var label: String {
        switch self {
        case .markReleased: return "Mark a delivered release as released"
        case .tidyContactTags: return "Tidy duplicate and untrimmed contact tags"
        case .tidySubscriberTags: return "Tidy duplicate and untrimmed subscriber tags"
        }
    }
}

/// New records the app wants to add. Kept as data so an "ask first" suggestion survives relaunch.
struct Proposal: Codable, Equatable {
    var tasks: [TaskItem] = []
    var events: [CalendarEvent] = []
    var outreach: [Outreach] = []
    var recommendations: [Recommendation] = []
    var resolvedRuleKeys: [String] = []
    /// Optional so files written before this field existed still load.
    var organize: [OrganizeOperation]? = nil

    var isEmpty: Bool {
        tasks.isEmpty && events.isEmpty && outreach.isEmpty && recommendations.isEmpty && resolvedRuleKeys.isEmpty
            && (organize ?? []).isEmpty
    }

    var summary: String {
        var parts: [String] = []
        if !tasks.isEmpty { parts.append("\(tasks.count) task\(tasks.count == 1 ? "" : "s")") }
        if !events.isEmpty { parts.append("\(events.count) calendar event\(events.count == 1 ? "" : "s")") }
        if !outreach.isEmpty { parts.append("\(outreach.count) draft message\(outreach.count == 1 ? "" : "s")") }
        if !recommendations.isEmpty { parts.append("\(recommendations.count) recommendation\(recommendations.count == 1 ? "" : "s")") }
        let cleanups = (organize ?? []).count
        if cleanups > 0 { parts.append("\(cleanups) cleanup\(cleanups == 1 ? "" : "s")") }
        return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
    }
}

struct ApprovalRequest: Entity {
    var id = UUID()
    var createdAt = Date()
    var kind: ActionKind
    var title: String
    var summary: String
    /// Exactly what will go out / be committed, shown to the artist before they decide.
    var preview: String
    var subjectKind: EntityKind?
    var subjectID: UUID?
    var proposal: Proposal?
    var requestedBy: Actor = .artist
    var state: ApprovalState = .pending
    var decidedAt: Date?
    var decisionNote = ""
    /// Lets automation avoid asking the same question twice.
    var dedupeKey: String?
}

// MARK: - Activity log

enum ActionStatus: String, Codable, CaseIterable {
    case completed, drafted, recommended, awaitingApproval, approved, declined, undone, failed
    var label: String {
        switch self {
        case .completed: return "Done"
        case .drafted: return "Drafted"
        case .recommended: return "Recommended"
        case .awaitingApproval: return "Waiting for approval"
        case .approved: return "Approved"
        case .declined: return "Declined"
        case .undone: return "Undone"
        case .failed: return "Failed"
        }
    }
}

/// One record-level change: the JSON of the record before and after.
struct EntityChange: Codable, Equatable {
    var kind: EntityKind
    var id: UUID
    var before: Data?
    var after: Data?

    var changeDescription: String {
        switch (before, after) {
        case (nil, .some): return "Added"
        case (.some, nil): return "Removed"
        default: return "Changed"
        }
    }
}

struct ActionRecord: Codable, Equatable, Identifiable {
    var id = UUID()
    var date = Date()
    var title: String
    var detail = ""
    var kind: ActionKind
    var actor: Actor
    var status: ActionStatus
    var changes: [EntityChange] = []
    var undoneBy: UUID?
    var undoOf: UUID?

    var canUndo: Bool { !changes.isEmpty && undoneBy == nil }
}
