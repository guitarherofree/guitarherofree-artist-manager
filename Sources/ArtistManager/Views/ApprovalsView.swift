import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ApprovalsView: View {
    @EnvironmentObject var model: AppModel
    @State private var page: Page = .waiting

    enum Page: String, CaseIterable, Identifiable {
        case waiting, decided, activity
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader("Approvals & Activity", subtitle: "Nothing is sent, published, accepted, spent or signed without your approval. Everything Manager does is recorded here.") {
                SettingsLink {
                    Label("Permissions…", systemImage: "checkmark.shield")
                }
                .help("Choose which routine work happens automatically")
            }
            .padding([.horizontal, .top], 24)
            SectionPicker(options: Page.allCases, selection: $page) { p in
                switch p {
                case .waiting: return "Waiting (\(model.pendingApprovalCount))"
                case .decided: return "Decided"
                case .activity: return "Activity log"
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            switch page {
            case .waiting: WaitingApprovals()
            case .decided: DecidedApprovals()
            case .activity: ActivityLogView()
            }
        }
    }
}

// MARK: - Waiting

private struct WaitingApprovals: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmAll = false

    /// Pitches and messages waiting together, which can be approved in one step.
    private var pendingPitches: [ApprovalRequest] {
        model.workspace.pendingApprovals.filter { $0.subjectKind == .outreach }
    }

    var body: some View {
        let pending = model.workspace.pendingApprovals
        if pending.isEmpty {
            EmptyStateView(title: "Nothing waiting for you", symbol: "checkmark.shield",
                           message: "Pitches, email campaigns, spending and routine work set to “Ask me first” appear here before anything happens.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if pendingPitches.count > 1 {
                        HStack {
                            Text("\(pendingPitches.count) pitches and messages are waiting. Read each one below, or approve them all at once.")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Approve All \(pendingPitches.count) Pitches…") { confirmAll = true }
                        }
                    }
                    ForEach(pending) { request in
                        ApprovalCard(request: request)
                    }
                }
                .padding(24)
            }
            .confirmationDialog("Approve all \(pendingPitches.count) pitches and messages?", isPresented: $confirmAll) {
                Button("Approve All") { model.approveAll(pendingPitches.map(\.id)) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Each one becomes ready for you to send; nothing is sent. You can undo this from the activity log.")
            }
        }
    }
}

private struct ApprovalCard: View {
    @EnvironmentObject var model: AppModel
    var request: ApprovalRequest
    @State private var note = ""
    @State private var showFullPreview = false

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: symbol).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.title).font(.headline)
                    Text("\(request.kind.label) · asked by \(request.requestedBy.label) · \(request.createdAt.shortDateTime)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                request.state.badge
            }
            if !request.summary.isBlank && request.summary != request.title {
                Text(request.summary).foregroundStyle(.secondary)
            }
            Text(request.preview)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .lineLimit(showFullPreview ? nil : 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                .accessibilityLabel("Exactly what you're approving")
                .accessibilityValue(request.preview)
            if request.preview.components(separatedBy: "\n").count > 14 {
                Button(showFullPreview ? "Show Less" : "Show Everything") { showFullPreview.toggle() }.buttonStyle(.link)
            }
            Label(whatApprovalDoes, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("Note (optional)", text: $note).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                if destination != nil {
                    Button("Open Item") { openSubject() }
                }
                Spacer()
                Button("Decline") { model.decline(request.id, note: note) }
                Button("Approve") { model.approve(request.id, note: note) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canApprove)
            }
            if let problem = approvalProblem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var symbol: String {
        switch request.kind {
        case .sendExternalMessage, .sendPressOutreach: return "paperplane"
        case .sendEmailCampaign: return "envelope.badge"
        case .spendMoney: return "dollarsign.circle"
        case .acceptOffer, .contractualCommitment: return "signature"
        case .publishContent: return "megaphone"
        default: return "gearshape.2"
        }
    }

    private var destination: AppDestination? {
        switch request.subjectKind {
        case .outreach?: return .press
        case .campaigns?: return .email
        case .budgetLines?: return .releases
        default: return nil
        }
    }

    private func openSubject() {
        switch request.subjectKind {
        case .outreach?:
            model.open(.press, tab: isSpotifyPitch ? "playlists" : "outreach")
        case .campaigns?:
            model.open(.email, record: request.subjectID, tab: "campaigns")
        case .budgetLines?:
            let releaseID = model.workspace.budgetLines.first { $0.id == request.subjectID }?.releaseID
            model.open(.releases, record: releaseID)
        default:
            break
        }
    }

    private var isSpotifyPitch: Bool {
        guard request.subjectKind == .outreach, let id = request.subjectID else { return false }
        return model.workspace.outreach.first { $0.id == id }?.kind == .spotifyEditorial
    }

    private var whatApprovalDoes: String {
        if isSpotifyPitch {
            return "Approving marks the pitch ready. Manager can't submit to Spotify: you paste the fields into Spotify for Artists, submit it there, then mark it submitted."
        }
        switch request.kind {
        case .sendExternalMessage, .sendPressOutreach:
            return "Approving marks this message ready to send. Manager doesn't send email: you'll open it in your mail app, press Send, then mark it sent."
        case .sendEmailCampaign:
            return "Approving lets you export this campaign for your email provider. You send it from there. Editing it afterwards needs approval again."
        case .spendMoney:
            return "Approving records that you've agreed to this cost. No payment is made; mark it paid once you've paid."
        case .acceptOffer, .contractualCommitment:
            return "Approving records your decision. Nothing is signed or accepted on your behalf — reply to the other party yourself."
        case .publishContent:
            return "Approving records your go-ahead. Manager never posts; you publish it yourself."
        default:
            return "Approving applies these changes now. You can undo them from the activity log."
        }
    }

    /// Re-checks the subject at decision time, since data may have changed since the request was made.
    private var approvalProblem: String? {
        guard let id = request.subjectID else { return nil }
        switch request.subjectKind {
        case .outreach?:
            guard let item = model.workspace.outreach.first(where: { $0.id == id }) else { return "This message was deleted." }
            if item.kind.isEmail, model.workspace.contact(item.contactID)?.email.isBlank ?? true {
                return "The recipient has no email address yet. You can approve now and add it before sending."
            }
        case .campaigns?:
            guard let c = model.workspace.campaigns.first(where: { $0.id == id }) else { return "This campaign was deleted." }
            if CampaignLint.hasErrors(CampaignLint.check(c, workspace: model.workspace)) { return "This campaign has problems to fix before it can be approved. Open it to see them." }
        case .budgetLines?:
            if !model.workspace.budgetLines.contains(where: { $0.id == id }) { return "This cost was deleted." }
        default:
            break
        }
        return nil
    }

    private var canApprove: Bool {
        guard let id = request.subjectID else { return true }
        switch request.subjectKind {
        case .outreach?: return model.workspace.outreach.contains { $0.id == id }
        case .campaigns?:
            guard let c = model.workspace.campaigns.first(where: { $0.id == id }) else { return false }
            return !CampaignLint.hasErrors(CampaignLint.check(c, workspace: model.workspace))
        case .budgetLines?: return model.workspace.budgetLines.contains { $0.id == id }
        default: return true
        }
    }
}

// MARK: - Decided

private struct DecidedApprovals: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let decided = model.workspace.approvals.filter { $0.state != .pending }
            .sorted { ($0.decidedAt ?? $0.createdAt) > ($1.decidedAt ?? $1.createdAt) }
        if decided.isEmpty {
            EmptyStateView(title: "No decisions yet", symbol: "clock.arrow.circlepath", message: "Approvals and declines you make are kept here.")
        } else {
            List(decided) { request in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.title).fontWeight(.medium)
                        Text("\(request.kind.label) · asked \(request.createdAt.shortDateTime)\(request.decidedAt.map { " · decided \($0.shortDateTime)" } ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                        if !request.decisionNote.isBlank {
                            Text("Note: \(request.decisionNote)").font(.caption)
                        }
                    }
                    Spacer()
                    request.state.badge
                }
                .padding(.vertical, 3)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Activity log

private struct ActivityLogView: View {
    @EnvironmentObject var model: AppModel
    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var confirmUndo: ActionRecord?

    enum Filter: String, CaseIterable, Identifiable {
        case all, mine, automation, imports, approvals, undone
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "Everything"
            case .mine: return "By you"
            case .automation: return "By Manager"
            case .imports: return "Imports & exports"
            case .approvals: return "Approval decisions"
            case .undone: return "Undone"
            }
        }
        func matches(_ r: ActionRecord) -> Bool {
            switch self {
            case .all: return true
            case .mine: return r.actor == .artist
            case .automation: return r.actor == .automation || r.actor == .rule || r.actor == .system
            case .imports: return r.kind == .importData || r.kind == .exportData
            case .approvals: return r.kind == .approvalDecision || r.status == .awaitingApproval
            case .undone: return r.undoneBy != nil || r.kind == .undo
            }
        }
    }

    private var records: [ActionRecord] {
        model.workspace.actionLog.reversed().filter { r in
            filter.matches(r) && (search.isBlank || r.title.localizedCaseInsensitiveContains(search) || r.detail.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.label).tag($0) }
                }
                .frame(maxWidth: 240)
                TextField("Search the log", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Spacer()
                Button("Export Log…") {
                    model.exportText(model.activityLogCSV(), suggestedName: "Manager activity.csv",
                                     types: [.commaSeparatedText], logTitle: "Exported the activity log")
                }
                .disabled(model.workspace.actionLog.isEmpty)
            }
            .padding(.horizontal, 24)
            Text("Undo is available for recent changes to your records. Things that happened outside Manager — an email you sent, a payment you made — can't be undone here.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            if records.isEmpty {
                EmptyStateView(title: "Nothing recorded", symbol: "list.bullet.rectangle", message: "Actions appear here as you and Manager work.")
            } else {
                List(records.prefix(500)) { record in
                    ActivityRow(record: record) { undo(record) }
                }
            }
        }
        .confirmationDialog("Undo “\(confirmUndo?.title ?? "")”?", isPresented: Binding(get: { confirmUndo != nil }, set: { if !$0 { confirmUndo = nil } })) {
            Button("Undo Anyway", role: .destructive) {
                if let r = confirmUndo { model.undo(r.id, force: true) }
                confirmUndo = nil
            }
            Button("Cancel", role: .cancel) { confirmUndo = nil }
        } message: {
            Text("Some of the records it changed were edited afterwards. Undoing puts them back the way they were before this action, which discards those later edits.")
        }
    }

    private func undo(_ record: ActionRecord) {
        if model.conflictsForUndo(record.id) > 0 {
            confirmUndo = record
        } else {
            model.undo(record.id)
        }
    }
}

private struct ActivityRow: View {
    var record: ActionRecord
    var onUndo: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: actorSymbol).foregroundStyle(.secondary).frame(width: 18)
                    .accessibilityLabel(record.actor.label)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title).strikethrough(record.undoneBy != nil)
                    Text("\(record.date.shortDateTime) · \(record.actor.label)\(record.detail.isBlank ? "" : " · \(record.detail)")")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(expanded ? nil : 2)
                }
                Spacer()
                if record.undoneBy != nil {
                    ActionStatus.undone.badge
                } else {
                    record.status.badge
                }
                if !record.changes.isEmpty {
                    Button(expanded ? "Hide Changes" : "\(record.changes.count) Change\(record.changes.count == 1 ? "" : "s")") { expanded.toggle() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                if record.canUndo && record.kind != .undo {
                    Button("Undo", action: onUndo).controlSize(.small)
                }
            }
            if expanded {
                ForEach(Array(record.changes.enumerated()), id: \.offset) { _, change in
                    Text("\(change.changeDescription) \(change.kind.label.lowercased())\(changeName(change).map { ": \($0)" } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.leading, 26)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
    }

    private var actorSymbol: String {
        switch record.actor {
        case .artist: return "person"
        case .automation: return "gearshape.2"
        case .rule: return "checkmark.seal"
        case .importer: return "square.and.arrow.down"
        case .system: return "macwindow"
        }
    }

    /// A readable name for the changed record, pulled from its saved JSON.
    private func changeName(_ change: EntityChange) -> String? {
        guard let data = change.after ?? change.before,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        for key in ["title", "subject", "name", "email", "headline", "outlet", "artistName"] {
            if let value = object[key] as? String, !value.isBlank { return value }
        }
        return nil
    }
}
