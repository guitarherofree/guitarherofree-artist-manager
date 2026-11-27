import AppKit
import Foundation
import SwiftUI

enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case today, plan, profile, releases, press, coverage, targets, email, calendar, tasks, contacts, approvals, integrations, roadmap
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .plan: return "Career Plan"
        case .profile: return "Profile & Brand"
        case .releases: return "Releases"
        case .press: return "Press Kit"
        case .coverage: return "Coverage"
        case .targets: return "Targets"
        case .email: return "Email List"
        case .calendar: return "Calendar"
        case .tasks: return "Tasks"
        case .contacts: return "Contacts & Team"
        case .approvals: return "Approvals & Activity"
        case .integrations: return "Connections"
        case .roadmap: return "Coming Next"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .plan: return "map"
        case .profile: return "person.crop.circle"
        case .releases: return "opticaldisc"
        case .press: return "newspaper"
        case .coverage: return "quote.bubble"
        case .targets: return "scope"
        case .email: return "envelope"
        case .calendar: return "calendar"
        case .tasks: return "checklist"
        case .contacts: return "person.2"
        case .approvals: return "checkmark.shield"
        case .integrations: return "point.3.connected.trianglepath.dotted"
        case .roadmap: return "road.lanes"
        }
    }

    init(_ destination: AppDestination) {
        self = SidebarItem(rawValue: destination.rawValue) ?? .today
    }
}

struct Banner: Identifiable, Equatable {
    enum Style: Equatable { case info, success, warning, error }
    var id = UUID()
    var style: Style
    var message: String
    var undoRecordID: UUID?
}

/// The app's single source of truth. Every change goes through `perform`, which records it in the
/// activity log with enough information to undo it.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var workspace: Workspace
    @Published var selection: SidebarItem? = .today
    @Published var banner: Banner?
    @Published var showOnboarding = false
    @Published var focusedRecordID: UUID?
    /// A tab to show when a page opens (e.g. "outreach" on Press Kit), set by `open(_:record:tab:)`.
    @Published var requestedTab: String?

    let persistence: Persistence
    private var automationTimer: Timer?
    private let maxLogEntries = 3000
    private let maxUndoableEntries = 300

    init(persistence: Persistence = Persistence()) {
        self.persistence = persistence
        switch persistence.load() {
        case .fresh(let ws):
            workspace = ws
        case .loaded(let ws):
            workspace = ws
        case .recovered(let ws, let movedTo, let error):
            workspace = ws
            banner = Banner(style: .warning, message: "Your data file couldn't be read (\(error)). It was moved to \(movedTo.lastPathComponent) and the newest backup was loaded.")
        }
        showOnboarding = !workspace.profile.onboardingCompleted
        persistence.makeDailyBackupIfNeeded()
    }

    // MARK: Changing data

    /// Applies a change, logs it, and saves. Returns the log record (nil if nothing changed).
    @discardableResult
    func perform(_ title: String, kind: ActionKind = .editRecord, actor: Actor = .artist, status: ActionStatus = .completed,
                 detail: String = "", showUndo: Bool = false, _ mutate: (inout Workspace) -> Void) -> ActionRecord? {
        var updated = workspace
        mutate(&updated)
        let changes = Workspace.diff(workspace, updated)
        guard !changes.isEmpty else { return nil }
        let record = ActionRecord(title: title, detail: detail, kind: kind, actor: actor, status: status, changes: changes)
        updated.actionLog.append(record)
        trimLog(&updated)
        workspace = updated
        save()
        if showUndo {
            banner = Banner(style: .success, message: title, undoRecordID: record.id)
        }
        return record
    }

    /// Records something that happened without changing data (e.g. an export).
    func log(_ title: String, kind: ActionKind, actor: Actor = .artist, status: ActionStatus = .completed, detail: String = "") {
        workspace.actionLog.append(ActionRecord(title: title, detail: detail, kind: kind, actor: actor, status: status))
        save()
    }

    private func trimLog(_ ws: inout Workspace) {
        if ws.actionLog.count > maxLogEntries {
            ws.actionLog.removeFirst(ws.actionLog.count - maxLogEntries)
        }
        // Keep undo data only for recent entries so the file stays small.
        let cutoff = ws.actionLog.count - maxUndoableEntries
        if cutoff > 0 {
            for i in 0..<cutoff where !ws.actionLog[i].changes.isEmpty {
                ws.actionLog[i].changes = []
            }
        }
    }

    func save() {
        do {
            try persistence.save(workspace)
        } catch {
            banner = Banner(style: .error, message: "Couldn't save your changes: \(error.localizedDescription)")
        }
    }

    // MARK: Undo

    func undo(_ recordID: UUID, force: Bool = false) {
        guard let record = workspace.actionLog.first(where: { $0.id == recordID }), record.canUndo else { return }
        let conflicts = workspace.conflicts(forUndoing: record.changes)
        if !conflicts.isEmpty && !force {
            banner = Banner(style: .warning, message: "Some of these records were edited after “\(record.title)”. Undo from the activity log to confirm.")
            return
        }
        var updated = workspace
        do {
            try updated.revert(record.changes)
        } catch {
            banner = Banner(style: .error, message: "Couldn't undo: \(error.localizedDescription)")
            return
        }
        let changes = Workspace.diff(workspace, updated)
        var undoRecord = ActionRecord(title: "Undid: \(record.title)", kind: .undo, actor: .artist, status: .completed, changes: changes)
        undoRecord.undoOf = record.id
        if let index = updated.actionLog.firstIndex(where: { $0.id == record.id }) {
            updated.actionLog[index].undoneBy = undoRecord.id
        }
        updated.actionLog.append(undoRecord)
        workspace = updated
        save()
        banner = Banner(style: .info, message: "Undid “\(record.title)”.", undoRecordID: undoRecord.id)
    }

    var lastUndoableRecord: ActionRecord? {
        workspace.actionLog.last(where: { $0.canUndo && $0.kind != .undo })
    }

    func conflictsForUndo(_ recordID: UUID) -> Int {
        guard let record = workspace.actionLog.first(where: { $0.id == recordID }) else { return 0 }
        return workspace.conflicts(forUndoing: record.changes).count
    }

    // MARK: Approvals

    var pendingApprovalCount: Int { workspace.approvals.filter { $0.state == .pending }.count }

    func requestApproval(forOutreach item: Outreach) {
        perform("Asked for approval: \(item.subject)", kind: item.kind.permission, status: .awaitingApproval) { ws in
            ws.upsert(item, in: \.outreach)
            _ = ApprovalService.requestForOutreach(item, in: &ws)
        }
    }

    func requestApproval(forCampaign campaign: EmailCampaign) {
        perform("Asked for approval: email “\(campaign.subject)”", kind: .sendEmailCampaign, status: .awaitingApproval) { ws in
            ws.upsert(campaign, in: \.campaigns)
            _ = ApprovalService.requestForCampaign(campaign, in: &ws)
        }
    }

    func requestApproval(forSpend line: BudgetLine) {
        let currency = workspace.profile.budget.currency
        perform("Asked for approval to spend: \(line.title)", kind: .spendMoney, status: .awaitingApproval) { ws in
            ws.upsert(line, in: \.budgetLines)
            _ = ApprovalService.requestForSpend(line, currency: currency, in: &ws)
        }
    }

    func approve(_ requestID: UUID, note: String = "") {
        guard let request = workspace.approvals.first(where: { $0.id == requestID }) else { return }
        perform("Approved: \(request.title)", kind: .approvalDecision, status: .approved, detail: note, showUndo: true) { ws in
            ApprovalService.approve(requestID, note: note, in: &ws)
        }
    }

    func approveAll(_ requestIDs: [UUID], note: String = "") {
        let ids = requestIDs.filter { id in workspace.approvals.contains { $0.id == id && $0.state == .pending } }
        guard !ids.isEmpty else { return }
        perform("Approved \(ids.count) item\(ids.count == 1 ? "" : "s") together", kind: .approvalDecision, status: .approved,
                detail: note, showUndo: true) { ws in
            ApprovalService.approveAll(ids, note: note, in: &ws)
        }
    }

    func decline(_ requestID: UUID, note: String = "") {
        guard let request = workspace.approvals.first(where: { $0.id == requestID }) else { return }
        perform("Declined: \(request.title)", kind: .approvalDecision, status: .declined, detail: note, showUndo: true) { ws in
            ApprovalService.decline(requestID, note: note, in: &ws)
        }
    }

    // MARK: Automation

    func startAutomation() {
        runAutomation()
        automationTimer?.invalidate()
        automationTimer = Timer.scheduledTimer(withTimeInterval: 60 * 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runAutomation() }
        }
    }

    /// Runs routine work according to the artist's permissions.
    func runAutomation(now: Date = Date()) {
        guard workspace.settings.automationEnabled, workspace.profile.onboardingCompleted else { return }
        let items = AutomationEngine.plan(for: workspace, now: now)
        var asked = 0
        for item in items {
            switch workspace.permissions.mode(for: item.kind) {
            case .off:
                continue
            case .automatic:
                perform(item.title, kind: item.kind, actor: .automation,
                        status: item.kind == .draftMaterials ? .drafted : .completed, detail: item.detail) { ws in
                    item.proposal.apply(to: &ws, now: now)
                }
            case .askFirst:
                let alreadyAsked = workspace.approvals.contains { $0.dedupeKey == item.dedupeKey }
                // Don't re-ask while a similar request is waiting.
                let similarPending = workspace.approvals.contains { $0.state == .pending && $0.kind == item.kind && $0.title == item.title }
                guard !alreadyAsked && !similarPending else { continue }
                perform("Suggested: \(item.title)", kind: item.kind, actor: .automation, status: .awaitingApproval, detail: item.detail) { ws in
                    ws.approvals.append(ApprovalService.requestForAutomation(item))
                }
                asked += 1
            }
        }
        if workspace.settings.lastAutomationRun.map({ !$0.isSameDay(as: now) }) ?? true {
            var settings = workspace.settings
            settings.lastAutomationRun = now
            workspace.settings = settings
            save()
            Notifier.shared.dailySummary(for: workspace)
        }
        if asked > 0 {
            Notifier.shared.notify(title: "Manager", body: "\(asked) suggestion\(asked == 1 ? "" : "s") waiting for your approval.")
        }
    }

    func refreshPlanNow() {
        let output = PlanGenerator.generate(for: workspace, includeBudget: workspace.permissions.mode(for: .trackBudget) != .off)
        let proposal = PlanGenerator.proposal(merging: output, into: workspace.recommendations)
        if proposal.isEmpty {
            banner = Banner(style: .info, message: "Your plan is up to date.")
            return
        }
        perform("Refreshed career plan", kind: .refreshPlan, actor: .artist, status: .recommended, detail: proposal.summary, showUndo: true) { ws in
            proposal.apply(to: &ws)
        }
    }

    // MARK: Onboarding

    func completeOnboarding(profile: ArtistProfile, goals: [CareerGoal], team: [Contact], permissions: PermissionPolicy) {
        perform("Set up your profile and career plan", kind: .editRecord, actor: .artist) { ws in
            var p = profile
            p.onboardingCompleted = true
            p.updatedAt = Date()
            ws.profile = p
            ws.permissions = permissions
            for goal in goals where !goal.title.isBlank { ws.upsert(goal, in: \.goals) }
            for member in team where !member.name.isBlank { ws.upsert(member, in: \.contacts) }
            if ws.pressKit.bookingContact.isEmpty, let booker = team.first(where: { $0.role == .bookingAgent && !$0.email.isBlank }) {
                ws.pressKit.bookingContact = ContactCard(name: booker.name, organization: booker.organization, email: booker.email, phone: booker.phone)
            }
            if ws.pressKit.publicityContact.isEmpty, let publicist = team.first(where: { $0.role == .publicist && !$0.email.isBlank }) {
                ws.pressKit.publicityContact = ContactCard(name: publicist.name, organization: publicist.organization, email: publicist.email, phone: publicist.phone)
            }
        }
        showOnboarding = false
        refreshPlanNow()
        runAutomation()
        selection = .plan
    }

    // MARK: Navigation

    func open(_ destination: AppDestination, record: UUID? = nil, tab: String? = nil) {
        focusedRecordID = record
        requestedTab = tab
        selection = SidebarItem(destination)
    }

    // MARK: Data management

    func exportBackup(to url: URL) {
        do {
            let data = try JSONCoding.prettyEncoder.encode(workspace)
            try data.write(to: url, options: [.atomic])
            log("Exported a full backup", kind: .exportData, detail: url.lastPathComponent)
            banner = Banner(style: .success, message: "Backup saved to \(url.lastPathComponent).")
        } catch {
            banner = Banner(style: .error, message: "Couldn't export: \(error.localizedDescription)")
        }
    }

    func restoreBackup(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let restored = try TolerantDecoding.decodeWorkspace(data)
            perform("Restored data from \(url.lastPathComponent)", kind: .importData, showUndo: true) { ws in
                let log = ws.actionLog
                ws = restored
                ws.actionLog = log
            }
        } catch {
            banner = Banner(style: .error, message: "That file isn't a Manager backup: \(error.localizedDescription)")
        }
    }

    func writeText(_ text: String, to url: URL, logTitle: String) {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            log(logTitle, kind: .exportData, detail: url.lastPathComponent)
            banner = Banner(style: .success, message: "Saved \(url.lastPathComponent).")
        } catch {
            banner = Banner(style: .error, message: "Couldn't save \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func showError(_ message: String) { banner = Banner(style: .error, message: message) }
    func showInfo(_ message: String) { banner = Banner(style: .info, message: message) }
}
