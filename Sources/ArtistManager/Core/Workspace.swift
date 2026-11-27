import Foundation

/// The kinds of records the workspace holds. Used for diffs, undo, and linking approvals to records.
enum EntityKind: String, Codable, CaseIterable {
    case profile, pressKit, permissions, settings
    case goals, recommendations, releases, tasks, events, contacts
    case outreach, pressReleases, coverage, targets, subscribers, segments, campaigns
    case budgetLines, approvals

    var isSingleton: Bool {
        switch self {
        case .profile, .pressKit, .permissions, .settings: return true
        default: return false
        }
    }

    /// Fixed IDs for the singleton records so they diff like everything else.
    var singletonID: UUID {
        switch self {
        case .profile: return UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        case .pressKit: return UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        case .permissions: return UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        case .settings: return UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        default: return UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        }
    }

    var label: String {
        switch self {
        case .profile: return "Profile"
        case .pressKit: return "Press kit"
        case .permissions: return "Permissions"
        case .settings: return "Settings"
        case .goals: return "Goal"
        case .recommendations: return "Recommendation"
        case .releases: return "Release"
        case .tasks: return "Task"
        case .events: return "Calendar event"
        case .contacts: return "Contact"
        case .outreach: return "Outreach"
        case .pressReleases: return "Press release"
        case .coverage: return "Coverage"
        case .targets: return "Target"
        case .subscribers: return "Subscriber"
        case .segments: return "Segment"
        case .campaigns: return "Email campaign"
        case .budgetLines: return "Budget line"
        case .approvals: return "Approval"
        }
    }
}

enum WorkspaceError: LocalizedError {
    case undoConflict(String)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .undoConflict(let message): return message
        case .decodeFailed(let message): return message
        }
    }
}

/// Everything the app knows, stored as one JSON document.
struct Workspace: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion = Workspace.currentSchemaVersion
    var profile = ArtistProfile()
    var pressKit = PressKit()
    var permissions = PermissionPolicy()
    var settings = AppSettings()

    var goals: [CareerGoal] = []
    var recommendations: [Recommendation] = []
    var releases: [Release] = []
    var tasks: [TaskItem] = []
    var events: [CalendarEvent] = []
    var contacts: [Contact] = []
    var outreach: [Outreach] = []
    var pressReleases: [PressRelease] = []
    var coverage: [Coverage] = []
    var targets: [Target] = []
    var subscribers: [Subscriber] = []
    var segments: [Segment] = []
    var campaigns: [EmailCampaign] = []
    var budgetLines: [BudgetLine] = []
    var approvals: [ApprovalRequest] = []

    /// The activity log. Not itself diffed or undoable.
    var actionLog: [ActionRecord] = []

    init() {}

    // Tolerant decoding: a missing collection becomes empty instead of failing the whole file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        profile = try c.decodeIfPresent(ArtistProfile.self, forKey: .profile) ?? ArtistProfile()
        pressKit = try c.decodeIfPresent(PressKit.self, forKey: .pressKit) ?? PressKit()
        permissions = try c.decodeIfPresent(PermissionPolicy.self, forKey: .permissions) ?? PermissionPolicy()
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        goals = try c.decodeIfPresent([CareerGoal].self, forKey: .goals) ?? []
        recommendations = try c.decodeIfPresent([Recommendation].self, forKey: .recommendations) ?? []
        releases = try c.decodeIfPresent([Release].self, forKey: .releases) ?? []
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        events = try c.decodeIfPresent([CalendarEvent].self, forKey: .events) ?? []
        contacts = try c.decodeIfPresent([Contact].self, forKey: .contacts) ?? []
        outreach = try c.decodeIfPresent([Outreach].self, forKey: .outreach) ?? []
        pressReleases = try c.decodeIfPresent([PressRelease].self, forKey: .pressReleases) ?? []
        coverage = try c.decodeIfPresent([Coverage].self, forKey: .coverage) ?? []
        targets = try c.decodeIfPresent([Target].self, forKey: .targets) ?? []
        subscribers = try c.decodeIfPresent([Subscriber].self, forKey: .subscribers) ?? []
        segments = try c.decodeIfPresent([Segment].self, forKey: .segments) ?? []
        campaigns = try c.decodeIfPresent([EmailCampaign].self, forKey: .campaigns) ?? []
        budgetLines = try c.decodeIfPresent([BudgetLine].self, forKey: .budgetLines) ?? []
        approvals = try c.decodeIfPresent([ApprovalRequest].self, forKey: .approvals) ?? []
        actionLog = try c.decodeIfPresent([ActionRecord].self, forKey: .actionLog) ?? []
    }

    // MARK: Generic helpers

    mutating func upsert<T: Entity>(_ item: T, in keyPath: WritableKeyPath<Workspace, [T]>) {
        if let index = self[keyPath: keyPath].firstIndex(where: { $0.id == item.id }) {
            self[keyPath: keyPath][index] = item
        } else {
            self[keyPath: keyPath].append(item)
        }
    }

    mutating func remove<T: Entity>(_ id: UUID, from keyPath: WritableKeyPath<Workspace, [T]>) {
        self[keyPath: keyPath].removeAll { $0.id == id }
    }

    func release(_ id: UUID?) -> Release? {
        guard let id else { return nil }
        return releases.first { $0.id == id }
    }

    func contact(_ id: UUID?) -> Contact? {
        guard let id else { return nil }
        return contacts.first { $0.id == id }
    }

    func segment(_ id: UUID?) -> Segment? {
        guard let id else { return nil }
        return segments.first { $0.id == id }
    }

    var pendingApprovals: [ApprovalRequest] {
        approvals.filter { $0.state == .pending }.sorted { $0.createdAt > $1.createdAt }
    }

    var teamMembers: [Contact] { contacts.filter(\.isTeamMember) }

    /// Subscribers a campaign would go to: subscribed only, then filtered by the segment.
    func recipients(for segmentID: UUID?) -> [Subscriber] {
        let sendable = subscribers.filter { $0.status.canReceiveCampaigns }
        guard let segment = segment(segmentID) else { return sendable }
        return sendable.filter { segment.rules.matches($0) }
    }
}

// MARK: - Diff and undo

extension Workspace {
    /// Every record that differs between two workspaces, with its JSON before and after.
    static func diff(_ old: Workspace, _ new: Workspace) -> [EntityChange] {
        var changes: [EntityChange] = []

        func single<T: Codable & Equatable>(_ kind: EntityKind, _ keyPath: KeyPath<Workspace, T>) {
            let a = old[keyPath: keyPath]
            let b = new[keyPath: keyPath]
            if a != b {
                changes.append(EntityChange(kind: kind, id: kind.singletonID,
                                            before: JSONCoding.encode(a), after: JSONCoding.encode(b)))
            }
        }

        func collection<T: Entity>(_ kind: EntityKind, _ keyPath: KeyPath<Workspace, [T]>) {
            let a = old[keyPath: keyPath]
            let b = new[keyPath: keyPath]
            if a == b { return }
            var oldByID: [UUID: T] = [:]
            for item in a { oldByID[item.id] = item }
            var newIDs = Set<UUID>()
            for item in b {
                newIDs.insert(item.id)
                if let previous = oldByID[item.id] {
                    if previous != item {
                        changes.append(EntityChange(kind: kind, id: item.id,
                                                    before: JSONCoding.encode(previous), after: JSONCoding.encode(item)))
                    }
                } else {
                    changes.append(EntityChange(kind: kind, id: item.id, before: nil, after: JSONCoding.encode(item)))
                }
            }
            for item in a where !newIDs.contains(item.id) {
                changes.append(EntityChange(kind: kind, id: item.id, before: JSONCoding.encode(item), after: nil))
            }
        }

        single(.profile, \.profile)
        single(.pressKit, \.pressKit)
        single(.permissions, \.permissions)
        single(.settings, \.settings)
        collection(.goals, \.goals)
        collection(.recommendations, \.recommendations)
        collection(.releases, \.releases)
        collection(.tasks, \.tasks)
        collection(.events, \.events)
        collection(.contacts, \.contacts)
        collection(.outreach, \.outreach)
        collection(.pressReleases, \.pressReleases)
        collection(.coverage, \.coverage)
        collection(.targets, \.targets)
        collection(.subscribers, \.subscribers)
        collection(.segments, \.segments)
        collection(.campaigns, \.campaigns)
        collection(.budgetLines, \.budgetLines)
        collection(.approvals, \.approvals)
        return changes
    }

    /// The current JSON of one record, for checking whether it changed after an action.
    func currentData(kind: EntityKind, id: UUID) -> Data? {
        func find<T: Entity>(_ items: [T]) -> Data? {
            guard let item = items.first(where: { $0.id == id }) else { return nil }
            return JSONCoding.encode(item)
        }
        switch kind {
        case .profile: return JSONCoding.encode(profile)
        case .pressKit: return JSONCoding.encode(pressKit)
        case .permissions: return JSONCoding.encode(permissions)
        case .settings: return JSONCoding.encode(settings)
        case .goals: return find(goals)
        case .recommendations: return find(recommendations)
        case .releases: return find(releases)
        case .tasks: return find(tasks)
        case .events: return find(events)
        case .contacts: return find(contacts)
        case .outreach: return find(outreach)
        case .pressReleases: return find(pressReleases)
        case .coverage: return find(coverage)
        case .targets: return find(targets)
        case .subscribers: return find(subscribers)
        case .segments: return find(segments)
        case .campaigns: return find(campaigns)
        case .budgetLines: return find(budgetLines)
        case .approvals: return find(approvals)
        }
    }

    /// Puts one record into the given state (`nil` removes it).
    mutating func setRecord(kind: EntityKind, id: UUID, data rawData: Data?) throws {
        // Records saved by an earlier version may lack newer fields.
        let data = rawData.map { TolerantDecoding.fillRecord(kind: kind, data: $0) }
        func put<T: Entity>(_ keyPath: WritableKeyPath<Workspace, [T]>) throws {
            if let data {
                let item = try JSONCoding.decode(T.self, from: data)
                upsert(item, in: keyPath)
            } else {
                remove(id, from: keyPath)
            }
        }
        switch kind {
        case .profile: if let data { profile = try JSONCoding.decode(ArtistProfile.self, from: data) }
        case .pressKit: if let data { pressKit = try JSONCoding.decode(PressKit.self, from: data) }
        case .permissions: if let data { permissions = try JSONCoding.decode(PermissionPolicy.self, from: data) }
        case .settings: if let data { settings = try JSONCoding.decode(AppSettings.self, from: data) }
        case .goals: try put(\.goals)
        case .recommendations: try put(\.recommendations)
        case .releases: try put(\.releases)
        case .tasks: try put(\.tasks)
        case .events: try put(\.events)
        case .contacts: try put(\.contacts)
        case .outreach: try put(\.outreach)
        case .pressReleases: try put(\.pressReleases)
        case .coverage: try put(\.coverage)
        case .targets: try put(\.targets)
        case .subscribers: try put(\.subscribers)
        case .segments: try put(\.segments)
        case .campaigns: try put(\.campaigns)
        case .budgetLines: try put(\.budgetLines)
        case .approvals: try put(\.approvals)
        }
    }

    /// Records touched by `changes` that have been edited again since. Undoing them would discard that later work.
    func conflicts(forUndoing changes: [EntityChange]) -> [EntityChange] {
        changes.filter { change in
            let current = currentData(kind: change.kind, id: change.id)
            return current != change.after
        }
    }

    /// Restores every record in `changes` to its "before" state.
    mutating func revert(_ changes: [EntityChange]) throws {
        for change in changes.reversed() {
            try setRecord(kind: change.kind, id: change.id, data: change.before)
        }
    }
}
