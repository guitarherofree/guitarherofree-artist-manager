import AppKit
import SwiftUI

// MARK: - Editing a pitch, follow-up, reminder or message

/// Drafts are saved locally. Asking for approval sends the draft to Approvals; nothing leaves the app from here.
struct OutreachEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var item: Outreach
    @State private var confirmDelete = false

    private var stored: Outreach? { model.workspace.outreach.first { $0.id == item.id } }
    private var isNew: Bool { stored == nil }
    private var contact: Contact? { model.workspace.contact(item.contactID) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Type", selection: $item.kind) {
                        ForEach(OutreachKind.allCases.filter(\.isEmail)) { Text($0.label).tag($0) }
                    }
                    ContactPicker(title: "To", selection: $item.contactID)
                    if let contact, contact.email.isBlank {
                        Label("\(contact.displayName) has no email address. Add one in Contacts before sending.", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    ReleasePicker(selection: $item.releaseID)
                } header: {
                    Text("Message")
                }
                Section {
                    TextField("Subject", text: $item.subject)
                    TextEditor(text: $item.body)
                        .frame(minHeight: 220)
                        .font(.body)
                        .accessibilityLabel("Message body")
                    HStack {
                        Button("Fill From Template") { fillFromTemplate() }
                            .help("Replaces the subject and body with a draft built from your profile, press kit and the release.")
                        Spacer()
                        Text("\(item.body.split(whereSeparator: \.isWhitespace).count) words").font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Draft")
                } footer: {
                    Text(statusExplanation).font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) { confirmDelete = true }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Draft") {
                    model.saveOutreach(item, requestApproval: false)
                    dismiss()
                }
                .disabled(item.subject.isBlank)
                Button("Save and Ask for Approval") {
                    model.saveOutreach(item, requestApproval: true)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(item.subject.isBlank || item.body.isBlank || item.contactID == nil)
                .help("Puts it in Approvals. Approving marks it ready for you to send from your mail app.")
            }
            .padding()
        }
        .frame(width: 640, height: 640)
        .confirmationDialog("Delete this message?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                model.deleteOutreach(item.id)
                dismiss()
            }
        } message: {
            Text("You can undo this from the activity log.")
        }
    }

    private var statusExplanation: String {
        switch stored?.status ?? .draft {
        case .draft: return "Draft. Nothing is sent until you approve it and send it yourself."
        case .awaitingApproval: return "Waiting for your approval. Editing it replaces the request with a new one."
        case .approved: return "Approved, not sent. Changing the recipient, subject or body means it needs approval again."
        case .sent: return "You recorded this as sent."
        default: return "Closed: \(stored?.status.label ?? "")."
        }
    }

    private func fillFromTemplate() {
        let ws = model.workspace
        let draft = Drafting.pitch(kind: item.kind, contact: ws.contact(item.contactID), release: ws.release(item.releaseID),
                                   profile: ws.profile, pressKit: ws.pressKit)
        item.subject = draft.subject
        item.body = draft.body
    }

    /// A new draft with the template already filled in.
    static func newDraft(kind: OutreachKind, contactID: UUID? = nil, releaseID: UUID? = nil, workspace ws: Workspace) -> Outreach {
        let draft = Drafting.pitch(kind: kind, contact: ws.contact(contactID), release: ws.release(releaseID),
                                   profile: ws.profile, pressKit: ws.pressKit)
        return Outreach(kind: kind, contactID: contactID, releaseID: releaseID, subject: draft.subject, body: draft.body)
    }
}

/// Opens the right editor for a piece of outreach.
struct OutreachSheet: View {
    var item: Outreach

    var body: some View {
        if item.kind == .spotifyEditorial {
            SpotifyPitchEditor(item: item)
        } else {
            OutreachEditor(item: item)
        }
    }
}

// MARK: - One row in an outreach list

struct OutreachRow: View {
    @EnvironmentObject var model: AppModel
    var item: Outreach
    var showContact = true
    var onEdit: () -> Void
    var onRecordResponse: () -> Void

    var body: some View {
        let contact = model.workspace.contact(item.contactID)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.subject.isBlank ? "No subject" : item.subject).fontWeight(.medium).lineLimit(2)
                HStack(spacing: 6) {
                    Text(item.kind.label)
                    if showContact && item.kind.isEmail { Text("· \(contact?.displayName ?? "No recipient")") }
                    if let release = model.workspace.release(item.releaseID) { Text("· \(release.title)") }
                    if let sent = item.sentAt { Text("· sent \(sent.shortDate)") }
                    if item.createdBy == .automation { Text("· drafted by Manager") }
                }
                .font(.caption).foregroundStyle(.secondary)
                if let due = item.followUpDue, item.status == .sent {
                    Label("Follow up \(due.relativeDayText.lowercased())", systemImage: "arrowshape.turn.up.right")
                        .font(.caption)
                        .foregroundStyle(due.startOfDay <= Date().startOfDay ? Color.orange : Color.secondary)
                }
                if let rule = item.approvedByRule, item.status == .approved {
                    Text("Approved by rule: \(rule)").font(.caption).foregroundStyle(.secondary)
                }
                if !item.responseNotes.isBlank {
                    Text(item.responseNotes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            item.status.badge
            actions
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        switch item.kind {
        case .press: return "newspaper"
        case .review: return "star.bubble"
        case .playlist: return "music.note.list"
        case .spotifyEditorial: return "music.note.house"
        case .radio: return "radio"
        case .label: return "opticaldisc"
        case .booking: return "music.mic"
        case .sync: return "film"
        case .partnership: return "signature"
        case .followUp: return "arrowshape.turn.up.right"
        case .reminder: return "bell"
        case .general: return "envelope"
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 6) {
            switch item.status {
            case .draft:
                Button("Ask for Approval") { model.requestApproval(forOutreach: item) }
                    .disabled((item.kind.isEmail && item.contactID == nil) || item.subject.isBlank)
            case .awaitingApproval:
                Button("Review") { model.selection = .approvals }
            case .approved where item.kind == .spotifyEditorial:
                Button("Copy Fields") { Clipboard.copy(item.editorial?.formText ?? item.body) }
                    .help("Copies every field so you can paste them into Spotify for Artists.")
                Link("Open Spotify for Artists", destination: EditorialPitch.submitURL)
                ConfirmSentButton(title: "Mark Submitted",
                                  explanation: "Confirm you submitted this pitch in Spotify for Artists yourself.") {
                    model.markOutreachSent(item.id)
                }
            case .approved:
                Button("Open in Mail") { model.openInMail(item) }
                    .help("Opens a new message in your mail app. You press Send there.")
                ConfirmSentButton(title: "Mark Sent",
                                  explanation: "Confirm you sent “\(item.subject)” yourself. Manager will suggest a follow-up if there's no reply.") {
                    model.markOutreachSent(item.id)
                }
            case .sent where item.kind == .spotifyEditorial:
                Button("Record Outcome…", action: onRecordResponse)
            case .sent:
                Button("Record Reply…", action: onRecordResponse)
            default:
                EmptyView()
            }
            Menu {
                Button("Edit…", action: onEdit)
                Button("Copy Text") { Clipboard.copy(item.kind == .spotifyEditorial ? (item.editorial?.formText ?? item.body) : "Subject: \(item.subject)\n\n\(item.body)") }
                if item.status == .sent && item.kind.isEmail {
                    Button("Draft Follow-up") { model.draftFollowUp(for: item.id) }
                }
                Divider()
                Button("Delete", role: .destructive) { model.deleteOutreach(item.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .accessibilityLabel("More actions for \(item.subject)")
        }
        .controlSize(.small)
    }
}

// MARK: - Recording a reply

struct OutreachResponseSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var item: Outreach
    @State private var status: OutreachStatus = .replied
    @State private var notes = ""
    @State private var addingCoverage: CoverageDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What happened with “\(item.subject)”?").font(.title3.weight(.semibold))
            if item.kind == .spotifyEditorial {
                Text("Spotify doesn't reply to pitches. Check your playlist adds in Spotify for Artists after release, and log any under Coverage.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Picker("Outcome", selection: $status) {
                ForEach([OutreachStatus.replied, .covered, .declined, .noResponse]) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
            TextField("Notes (what they said, next steps)", text: $notes, axis: .vertical).lineLimit(3...6)
            if status == .covered {
                Text("Save the piece in Coverage — paste its link and Manager fills in the details, keeps a copy, and can add the quote to your press kit.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if status == .covered {
                    Button("Save and Add the Piece…") {
                        model.recordOutreachResponse(item.id, status: status, notes: notes)
                        let c = CoverageLinks.coverage(resultOf: item, contact: model.workspace.contact(item.contactID))
                        addingCoverage = CoverageDraft(coverage: c, keepCopy: false)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Save") {
                        model.recordOutreachResponse(item.id, status: status, notes: notes)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .sheet(item: $addingCoverage, onDismiss: { dismiss() }) { draft in
            CoverageEditor(draft: draft).environmentObject(model)
        }
    }
}

/// The outreach list with filters, shared by Press Kit and Contacts.
struct OutreachListView: View {
    @EnvironmentObject var model: AppModel
    var contactID: UUID? = nil
    /// Only these kinds of outreach (nil shows everything).
    var kinds: Set<OutreachKind>? = nil
    /// The kind of pitch "Pitch Several" starts with.
    var batchKind: OutreachKind = .review
    var newPitchKinds: [OutreachKind] = [.review, .press, .playlist, .radio, .label, .booking, .sync, .partnership, .general]
    @State private var filter: Filter = .active
    @State private var editing: Outreach?
    @State private var responding: Outreach?
    @State private var batching = false

    enum Filter: String, CaseIterable, Identifiable {
        case active, drafts, waiting, ready, sent, closed, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .active: return "Active"
            case .drafts: return "Drafts"
            case .waiting: return "Awaiting approval"
            case .ready: return "Ready to send"
            case .sent: return "Sent"
            case .closed: return "Closed"
            case .all: return "All"
            }
        }
        func matches(_ status: OutreachStatus) -> Bool {
            switch self {
            case .active: return !status.isClosed
            case .drafts: return status == .draft
            case .waiting: return status == .awaitingApproval
            case .ready: return status == .approved
            case .sent: return status == .sent
            case .closed: return status.isClosed
            case .all: return true
            }
        }
    }

    private var items: [Outreach] {
        model.workspace.outreach
            .filter { contactID == nil || $0.contactID == contactID }
            .filter { kinds?.contains($0.kind) ?? true }
            .filter { filter.matches($0.status) }
            .sorted { ($0.sentAt ?? $0.createdAt) > ($1.sentAt ?? $1.createdAt) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.label).tag($0) }
                }
                .frame(maxWidth: 260)
                Spacer()
                if contactID == nil {
                    Button {
                        batching = true
                    } label: {
                        Label("Pitch Several…", systemImage: "person.3.sequence")
                    }
                    .help("Draft a personal note to each of several contacts in one go")
                }
                Menu {
                    ForEach(newPitchKinds) { kind in
                        Button(kind.label) {
                            editing = OutreachEditor.newDraft(kind: kind, contactID: contactID, workspace: model.workspace)
                        }
                    }
                } label: {
                    Label(contactID == nil ? "New Pitch" : "Draft Message", systemImage: "square.and.pencil")
                }
                .fixedSize()
            }
            if items.isEmpty {
                Text(filter == .active ? "No active outreach. Start a pitch and it will appear here, with its approval and reply status." : "Nothing here.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            ForEach(items) { item in
                OutreachRow(item: item, showContact: contactID == nil,
                            onEdit: { editing = item }, onRecordResponse: { responding = item })
                Divider()
            }
        }
        .sheet(item: $editing) { item in
            OutreachSheet(item: item).environmentObject(model)
        }
        .sheet(item: $responding) { item in
            OutreachResponseSheet(item: item).environmentObject(model)
        }
        .sheet(isPresented: $batching) {
            BatchPitchSheet(kind: batchKind).environmentObject(model)
        }
    }
}
