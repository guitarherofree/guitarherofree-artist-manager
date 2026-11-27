import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Publications, labels, stations, playlists and others to reach or keep an eye on.
struct TargetsView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedID: UUID?
    @State private var search = ""
    @State private var kindFilter: KindFilter = .all
    @State private var show: Show = .active
    @State private var sort: Sort = .name
    @State private var editing: TargetDraft?
    @State private var suggesting = false
    @State private var importing: IdentifiedTargetPreview?

    enum KindFilter: Hashable {
        case all
        case kind(TargetKind)
    }

    enum Show: String, CaseIterable, Identifiable {
        case active, due, ready, dream, won, notNow, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .active: return "Still to land"
            case .due: return "Due for a look"
            case .ready: return "Ready to pitch"
            case .dream: return "Dream list"
            case .won: return "Already working with you"
            case .notNow: return "Not right now"
            case .all: return "Everything"
            }
        }
        func includes(_ t: Target, today: Date) -> Bool {
            switch self {
            case .active: return t.status.isOpen
            case .due: return Targets.isDue(t, today: today)
            case .ready: return t.status == .ready
            case .dream: return t.tier == .dream && t.status != .notNow
            case .won: return t.status == .won
            case .notNow: return t.status == .notNow
            case .all: return true
            }
        }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case name, nextCheck, priority, status
        var id: String { rawValue }
        var label: String {
            switch self {
            case .name: return "Name"
            case .nextCheck: return "Next look"
            case .priority: return "Priority"
            case .status: return "Progress"
            }
        }
    }

    private var all: [Target] { model.workspace.targets }

    private var items: [Target] {
        let today = Date().startOfDay
        return all.filter { t in
            if case .kind(let k) = kindFilter, t.kind != k { return false }
            guard show.includes(t, today: today) else { return false }
            guard !search.isBlank else { return true }
            return [t.name, t.website, t.location, t.similarArtists, t.notes, t.guidelines, t.kind.label]
                .contains { $0.localizedCaseInsensitiveContains(search) }
                || t.genres.contains { $0.localizedCaseInsensitiveContains(search) }
                || t.tags.contains { $0.localizedCaseInsensitiveContains(search) }
        }
        .sorted { a, b in
            switch sort {
            case .name: return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .nextCheck: return (a.nextCheck ?? .distantFuture) < (b.nextCheck ?? .distantFuture)
            case .priority:
                if a.tier.order != b.tier.order { return a.tier.order < b.tier.order }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .status:
                if a.status.rank != b.status.rank { return a.status.rank > b.status.rank }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }

    private var suggestionCount: Int { Targets.suggestions(in: model.workspace).count }

    private var summary: String {
        let counts = Dictionary(grouping: all.filter { $0.status != .notNow }, by: \.kind).mapValues(\.count)
        return TargetKind.allCases.compactMap { k in
            guard let n = counts[k], n > 0 else { return nil }
            return "\(n) \(n == 1 ? k.shortLabel.lowercased() : k.pluralLabel)"
        }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Targets").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        Spacer()
                        addMenu
                    }
                    HStack {
                        fileMenu
                        if suggestionCount > 0 {
                            Button("\(suggestionCount) Suggested") { suggesting = true }
                                .help("Outlets and labels from your contacts and coverage that aren't on the list yet")
                        }
                    }
                    .controlSize(.small)
                    TextField("Search name, genre, location, notes", text: $search).textFieldStyle(.roundedBorder)
                    HStack {
                        Picker("Type", selection: $kindFilter) {
                            Text("All types").tag(KindFilter.all)
                            Divider()
                            ForEach(TargetKind.allCases) { Text($0.shortLabel).tag(KindFilter.kind($0)) }
                        }
                        Picker("Show", selection: $show) {
                            ForEach(Show.allCases) { Text($0.label).tag($0) }
                        }
                    }
                    .labelsHidden()
                    HStack {
                        Picker("Sort by", selection: $sort) {
                            ForEach(Sort.allCases) { Text($0.label).tag($0) }
                        }
                        .fixedSize()
                        Spacer()
                    }
                    if !summary.isEmpty {
                        Text(summary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
                List(selection: $selectedID) {
                    ForEach(items) { t in
                        TargetListRow(target: t).tag(t.id)
                            .contextMenu {
                                Button("Edit…") { editing = TargetDraft(target: t) }
                                if let url = webURL(t.website) { Button("Open Website") { NSWorkspace.shared.open(url) } }
                                Menu("Set Status") {
                                    ForEach(TargetStatus.allCases) { s in
                                        Button(s.label(for: t.kind)) { model.setTargetStatus(t.id, to: s) }
                                    }
                                }
                                Divider()
                                Button("Remove from Targets", role: .destructive) { remove(t) }
                            }
                    }
                }
                .overlay {
                    if !all.isEmpty && items.isEmpty {
                        Text("Nothing matches these filters.").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 330)
            Divider()
            detail
        }
        .sheet(item: $editing) { draft in
            TargetEditor(draft: draft) { saved in selectedID = saved }.environmentObject(model)
        }
        .sheet(isPresented: $suggesting) {
            TargetSuggestionsSheet().environmentObject(model)
        }
        .sheet(item: $importing) { item in
            TargetImportSheet(preview: item.preview, fileName: item.fileName).environmentObject(model)
        }
        .onAppear {
            if let focus = model.focusedRecordID, all.contains(where: { $0.id == focus }) {
                selectedID = focus
                model.focusedRecordID = nil
            } else if selectedID == nil {
                if all.contains(where: { Targets.isDue($0, today: Date()) }) { show = .due }
                selectedID = items.first?.id
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let id = selectedID, let t = all.first(where: { $0.id == id }) {
            TargetDetail(target: t, onEdit: { editing = TargetDraft(target: t) }, onRemove: { remove(t) })
                .id(t.id)
        } else if all.isEmpty {
            ContentUnavailableView {
                Label("No targets yet", systemImage: "scope")
            } description: {
                Text("Keep a list of the publications, labels, radio shows, podcasts, playlists and festivals you want to reach — or just want to keep an eye on. Note how they take submissions and who works there, set a date to look again, and see every pitch and piece of coverage connected to each one.")
            } actions: {
                Button("Add from a Website…") { editing = model.newTargetDraft() }.buttonStyle(.borderedProminent)
                if suggestionCount > 0 {
                    Button("Add \(suggestionCount) from Contacts & Coverage…") { suggesting = true }
                }
                Button("Import a CSV File…") { importCSV() }
            }
        } else {
            EmptyStateView(title: "Choose a target", symbol: "scope", message: "Select one on the left.")
        }
    }

    private var addMenu: some View {
        Menu {
            Button("Add a Publication…") { editing = model.newTargetDraft(kind: .publication) }
            Button("Add a Label…") { editing = model.newTargetDraft(kind: .label) }
            Menu("Add Another Kind") {
                ForEach(TargetKind.allCases.filter { $0 != .publication && $0 != .label }) { k in
                    Button(k.label) { editing = model.newTargetDraft(kind: k) }
                }
            }
            Divider()
            Button("Suggestions from Contacts & Coverage…") { suggesting = true }.disabled(suggestionCount == 0)
        } label: {
            Image(systemName: "plus")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add a target")
        .accessibilityLabel("Add a target")
    }

    private var fileMenu: some View {
        Menu {
            Button("Import a CSV File…") { importCSV() }
            Button("Export as CSV…") {
                model.exportText(model.exportTargetsCSV(), suggestedName: "Targets.csv", types: [.commaSeparatedText], logTitle: "Exported targets")
            }
            .disabled(all.isEmpty)
        } label: {
            Label("Import / Export", systemImage: "square.and.arrow.up.on.square")
        }
        .fixedSize()
    }

    private func importCSV() {
        guard let url = FilePanels.openFile(types: [.commaSeparatedText, .plainText], message: "Choose a CSV of publications, labels or other targets") else { return }
        do {
            let text = try FilePanels.readText(url)
            importing = IdentifiedTargetPreview(preview: TargetCSV.preview(csv: text, existing: all), fileName: url.lastPathComponent)
        } catch {
            model.showError("Couldn't read \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func remove(_ t: Target) {
        model.deleteTarget(t)
        if selectedID == t.id { selectedID = nil }
    }
}

private struct IdentifiedTargetPreview: Identifiable {
    let id = UUID()
    var preview: TargetImportPreview
    var fileName: String
}

extension TargetStatus {
    func badge(for kind: TargetKind) -> StatusBadge {
        switch self {
        case .watching: return StatusBadge(text: label(for: kind), tone: .neutral, symbol: "eye")
        case .researching: return StatusBadge(text: label(for: kind), tone: .neutral, symbol: "magnifyingglass")
        case .ready: return StatusBadge(text: label(for: kind), tone: .info, symbol: "paperplane")
        case .pitched: return StatusBadge(text: label(for: kind), tone: .draft, symbol: "envelope")
        case .talking: return StatusBadge(text: label(for: kind), tone: .warning, symbol: "bubble.left.and.bubble.right")
        case .won: return StatusBadge(text: label(for: kind), tone: .success, symbol: "checkmark.seal")
        case .notNow: return StatusBadge(text: label(for: kind), tone: .neutral, symbol: "moon.zzz")
        }
    }
}

// MARK: - List row

private struct TargetListRow: View {
    var target: Target

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: target.kind.symbol).foregroundStyle(.secondary).frame(width: 18).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.displayName).fontWeight(.medium).lineLimit(1)
                Text([target.kind.shortLabel, target.tier.label, target.location].filter { !$0.isBlank }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 4) {
                    target.status.badge(for: target.kind)
                    if Targets.isDue(target, today: Date()) {
                        StatusBadge(text: "Look again", tone: .warning, symbol: "clock")
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail

private struct TargetDetail: View {
    @EnvironmentObject var model: AppModel
    var target: Target
    var onEdit: () -> Void
    var onRemove: () -> Void
    @State private var pitching: Outreach?
    @State private var pitchingSeveral = false
    @State private var addingContact: Contact?

    private var activity: TargetActivity { Targets.activity(for: target, in: model.workspace) }

    var body: some View {
        let a = activity
        let fit = Targets.fitReasons(for: target, profile: model.workspace.profile)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(fit: fit)
                if let next = a.suggestedStatus { suggestion(next, activity: a) }
                actions(a)
                submissionCard
                peopleCard(a)
                if !a.pitches.isEmpty { pitchesCard(a) }
                if !a.coverage.isEmpty || target.kind.isMedia { coverageCard(a) }
                aboutCard
                HStack {
                    Spacer()
                    Button("Remove from Targets", role: .destructive, action: onRemove)
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .sheet(item: $pitching) { item in
            OutreachSheet(item: item).environmentObject(model)
        }
        .sheet(isPresented: $pitchingSeveral) {
            BatchPitchSheet(kind: target.kind.pitchKind, contactIDs: activity.reachable.map(\.id)).environmentObject(model)
        }
        .sheet(item: $addingContact) { c in
            ContactEditor(contact: c) { _ in }.environmentObject(model)
        }
    }

    private func header(fit: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(target.kind.label, systemImage: target.kind.symbol).font(.callout).foregroundStyle(.secondary)
            Text(target.displayName).font(.title.weight(.semibold)).accessibilityAddTraits(.isHeader)
            let line = [target.location, target.genres.commaJoined].filter { !$0.isBlank }
            if !line.isEmpty { Text(line.joined(separator: " · ")).foregroundStyle(.secondary) }
            HStack(spacing: 6) {
                target.status.badge(for: target.kind)
                StatusBadge(text: target.tier.label, tone: target.tier == .dream ? .draft : .neutral,
                            symbol: target.tier == .dream ? "sparkles" : "flag")
                if let next = target.nextCheck {
                    StatusBadge(text: Targets.isDue(target, today: Date()) ? "Look again now" : "Look again \(next.shortDate)",
                                tone: Targets.isDue(target, today: Date()) ? .warning : .neutral, symbol: "clock")
                }
            }
            if !fit.isEmpty {
                Label(fit.joined(separator: " · "), systemImage: "hand.thumbsup").font(.callout).foregroundStyle(.green)
            }
        }
    }

    private func suggestion(_ next: TargetStatus, activity a: TargetActivity) -> some View {
        let reason: String
        switch next {
        case .won:
            reason = "\(a.coverage.count == 1 ? "A piece" : "\(a.coverage.count) pieces") of coverage from \(target.displayName) \(a.coverage.count == 1 ? "is" : "are") saved."
        case .talking:
            reason = "Someone at \(target.displayName) replied to a pitch."
        default:
            let who = a.pitches.first.flatMap { model.workspace.contact($0.contactID)?.displayName } ?? "someone there"
            reason = "You pitched \(who)\(a.lastPitch.map { " on \($0.shortDate)" } ?? "")."
        }
        return HStack {
            Image(systemName: "lightbulb").foregroundStyle(.orange).accessibilityHidden(true)
            Text("\(reason) Mark as “\(next.label(for: target.kind))”?")
            Spacer()
            Button("Update Status") { model.setTargetStatus(target.id, to: next) }
        }
        .padding(10)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func actions(_ a: TargetActivity) -> some View {
        HStack {
            Button("Edit…", action: onEdit).keyboardShortcut("e", modifiers: .command)
            if let url = webURL(target.website) {
                Button { NSWorkspace.shared.open(url) } label: { Label("Website", systemImage: "safari") }
            }
            if let url = webURL(target.submissionURL) {
                Button { NSWorkspace.shared.open(url) } label: { Label("Submission Page", systemImage: "arrow.up.right.square") }
            }
            if a.reachable.count > 1 {
                Button { pitchingSeveral = true } label: { Label("Pitch Everyone Here…", systemImage: "person.3.sequence") }
                    .help("Draft a personal note to each person here. Each needs your approval.")
            } else if let person = a.reachable.first {
                Button { pitching = OutreachEditor.newDraft(kind: target.kind.pitchKind, contactID: person.id, workspace: model.workspace) } label: {
                    Label("Draft a Pitch…", systemImage: "square.and.pencil")
                }
                .help("Draft a \(target.kind.pitchKind.label.lowercased()) to \(person.displayName). It needs your approval before it goes out.")
            }
            Menu {
                Button("Look Again in a Week") { model.markTargetChecked(target.id, lookAgainInDays: 7) }
                Button("Look Again in a Month") { model.markTargetChecked(target.id, lookAgainInDays: 30) }
                Button("Look Again in 3 Months") { model.markTargetChecked(target.id, lookAgainInDays: 90) }
                Button("Look Again in 6 Months") { model.markTargetChecked(target.id, lookAgainInDays: 182) }
                Divider()
                Button("Checked — No Reminder") { model.markTargetChecked(target.id, lookAgainInDays: nil) }
            } label: {
                Label("Checked", systemImage: "eye")
            }
            .fixedSize()
            .help("Record that you looked today, and when to look again")
        }
    }

    private var submissionCard: some View {
        Card("How to reach them", symbol: "tray.and.arrow.down") {
            LabeledText(label: "Submissions", value: target.submissionPolicy.label)
            if !target.submissionURL.isBlank { LabeledText(label: "Submission page", value: target.submissionURL) }
            if !target.submissionEmail.isBlank {
                HStack {
                    LabeledText(label: "Submission email", value: target.submissionEmail)
                    if !hasContact(email: target.submissionEmail) {
                        Button("Save as Contact") { model.addSubmissionContact(for: target.id) }
                            .controlSize(.small)
                            .help("Add this address to Contacts so Manager can draft pitches to it")
                    }
                }
            }
            if !target.guidelines.isBlank {
                Text(target.guidelines).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if target.submissionURL.isBlank && target.submissionEmail.isBlank && target.guidelines.isBlank {
                Text("No submission details yet. Edit and use Look Up on their website — Manager looks for a submissions page and address — or add what you know.")
                    .foregroundStyle(.secondary)
            }
            if target.submissionPolicy == .closed || target.submissionPolicy == .referral {
                Label(target.submissionPolicy == .closed ? "They aren't taking submissions. Set a date to look again."
                                                         : "They work by referral. A warm introduction from someone they know is the way in.",
                      systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func hasContact(email: String) -> Bool {
        model.workspace.contacts.contains { $0.email.caseInsensitiveCompare(email) == .orderedSame }
    }

    private func peopleCard(_ a: TargetActivity) -> some View {
        Card("People there", symbol: "person.2") {
            if a.contacts.isEmpty {
                Text("No one from \(target.displayName) in your contacts yet. Contacts whose organization is \(target.displayName) appear here automatically.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(a.contacts) { c in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.displayName)
                        Text([c.role.label, c.email].filter { !$0.isBlank }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !c.email.isBlank {
                        Button("Draft Pitch…") {
                            pitching = OutreachEditor.newDraft(kind: target.kind.pitchKind, contactID: c.id, workspace: model.workspace)
                        }
                        .controlSize(.small)
                    }
                    Button("Open") { model.open(.contacts, record: c.id) }.controlSize(.small)
                }
            }
            Button {
                var c = Contact(name: "", organization: target.name, role: target.kind.contactRole)
                c.website = target.website
                c.location = target.location
                addingContact = c
            } label: {
                Label("Add Someone Who Works There…", systemImage: "plus")
            }
            .controlSize(.small)
        }
    }

    private func pitchesCard(_ a: TargetActivity) -> some View {
        Card("Pitches", symbol: "paperplane") {
            ForEach(a.pitches) { o in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(o.subject.isBlank ? o.kind.label : o.subject).lineLimit(1)
                        Text([model.workspace.contact(o.contactID)?.displayName ?? "", o.sentAt?.shortDate ?? "",
                              model.workspace.release(o.releaseID)?.title ?? ""].filter { !$0.isBlank }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    o.status.badge
                }
            }
        }
    }

    private func coverageCard(_ a: TargetActivity) -> some View {
        Card(target.kind.isMedia ? "Coverage from them" : "Coverage", symbol: "quote.bubble") {
            if a.coverage.isEmpty {
                Text("Nothing saved yet. Coverage with \(target.displayName) as the outlet shows up here.").foregroundStyle(.secondary)
            }
            ForEach(a.coverage) { c in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.title.isBlank ? c.kind.label : c.title).lineLimit(1)
                        Text([c.kind.label, c.date?.shortDate ?? ""].filter { !$0.isBlank }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open") { model.open(.coverage, record: c.id) }.controlSize(.small)
                }
            }
        }
    }

    private var aboutCard: some View {
        Card("About", symbol: "info.circle") {
            if !target.website.isBlank { LabeledText(label: "Website", value: target.website) }
            LabeledText(label: "Genres", value: target.genres.commaJoined)
            LabeledText(label: target.kind == .label ? "Roster like you" : "Artists like you", value: target.similarArtists)
            if !target.tags.isEmpty { LabeledText(label: "Tags", value: target.tags.commaJoined) }
            LabeledText(label: "Last checked", value: target.lastChecked?.shortDate ?? "")
            if let added = target.createdAt { LabeledText(label: "Added", value: added.shortDate) }
            if !target.notes.isBlank {
                Divider()
                Text(target.notes).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Editor

struct TargetEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var draft: TargetDraft
    var onSaved: (UUID) -> Void = { _ in }
    @State private var lookingUp = false
    @State private var lookedUp = ""
    @State private var linkPick: UUID?

    private var t: Target { draft.target }
    private var exists: Bool { model.workspace.targets.contains { $0.id == t.id } }
    private var duplicate: Target? {
        model.workspace.targets.first { other in
            other.id != t.id && (Targets.sameName(other.name, t.name)
                || (Targets.host(t.website) != nil && Targets.host(other.website) == Targets.host(t.website)))
        }
    }
    private var autoLinked: [Contact] {
        var unlinked = t
        unlinked.contactIDs = []
        return Targets.contacts(for: unlinked, in: model.workspace.contacts)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack {
                        TextField("Website", text: $draft.target.website, prompt: Text("Paste their website"))
                            .onSubmit { if canLookUp { lookUp() } }
                        Button {
                            lookUp()
                        } label: {
                            if lookingUp { ProgressView().controlSize(.small) } else { Text("Look Up") }
                        }
                        .disabled(!canLookUp)
                        .help("Read their site for the name, what they do, and a submissions page or address")
                    }
                    if let problem = draft.problem {
                        Label("Couldn't read the site: \(problem) Fill in what you know.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange).font(.callout)
                    } else if !lookedUp.isEmpty {
                        Label(lookUpSummary, systemImage: "checkmark.circle").foregroundStyle(.green).font(.callout)
                    }
                    if let duplicate {
                        Label("Already on your list: \(duplicate.displayName)", systemImage: "doc.on.doc").foregroundStyle(.orange).font(.callout)
                    }
                }
                Section("Who they are") {
                    TextField("Name", text: $draft.target.name)
                    Picker("Type", selection: $draft.target.kind) {
                        ForEach(TargetKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    TextField("Location", text: $draft.target.location, prompt: Text("City, region or country"))
                    TagsField(title: "Genres they cover", values: $draft.target.genres)
                    TextField(t.kind == .label ? "Artists on their roster like you" : "Artists they cover or play like you",
                              text: $draft.target.similarArtists, axis: .vertical)
                        .lineLimit(1...3)
                }
                Section("Where it stands") {
                    Picker("Status", selection: $draft.target.status) {
                        ForEach(TargetStatus.allCases) { Text($0.label(for: t.kind)).tag($0) }
                    }
                    Picker("Priority", selection: $draft.target.tier) {
                        ForEach(TargetTier.allCases) { Text($0.label).tag($0) }
                    }
                    OptionalDatePicker(title: "Look again on", date: $draft.target.nextCheck)
                }
                Section {
                    Picker("Submissions", selection: $draft.target.submissionPolicy) {
                        ForEach(SubmissionPolicy.allCases) { Text($0.label).tag($0) }
                    }
                    TextField("Submission page", text: $draft.target.submissionURL, prompt: Text("Form, SubmitHub or Groover page, or guidelines"))
                    if draft.findings.submissionLinks.count > 1 {
                        Picker("Other pages found", selection: $draft.target.submissionURL) {
                            ForEach(draft.findings.submissionLinks, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    TextField("Submission email", text: $draft.target.submissionEmail)
                    if draft.findings.emails.count > 1 {
                        Picker("Other addresses found", selection: $draft.target.submissionEmail) {
                            ForEach(draft.findings.emails, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    TextField("Their rules", text: $draft.target.guidelines,
                              prompt: Text("Format, lead time, what not to send, response time"), axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("How to submit")
                } footer: {
                    Text("Found addresses and pages come from their public site. Check them before you pitch.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("People") {
                    if autoLinked.isEmpty && t.contactIDs.isEmpty {
                        Text("Contacts whose organization is “\(t.name.isBlank ? "this name" : t.name)” are linked automatically.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(autoLinked) { c in
                        Label("\(c.displayName) (works there)", systemImage: "person")
                    }
                    ForEach(t.contactIDs.compactMap { model.workspace.contact($0) }.filter { c in !autoLinked.contains { $0.id == c.id } }) { c in
                        HStack {
                            Label(c.displayName, systemImage: "person.badge.plus")
                            Spacer()
                            Button("Unlink") { draft.target.contactIDs.removeAll { $0 == c.id } }.controlSize(.small)
                        }
                    }
                    ContactPicker(title: "Link another contact", selection: $linkPick)
                }
                Section("Notes") {
                    TextField("Notes", text: $draft.target.notes, prompt: Text("Why they fit, who to ask for an intro, what they've covered lately"), axis: .vertical)
                        .lineLimit(2...6)
                    TagsField(title: "Tags", values: $draft.target.tags)
                }
            }
            .formStyle(.grouped)
            HStack {
                if exists {
                    Button("Remove", role: .destructive) {
                        model.deleteTarget(t)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(exists ? "Save" : "Add Target") {
                    var target = draft.target
                    target.name = target.name.trimmed
                    if !target.website.isBlank { target.website = Targets.siteRoot(target.website) }
                    let saved = model.saveTarget(target)
                    onSaved(saved.id)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(t.name.isBlank)
            }
            .padding()
        }
        .frame(width: 620, height: 760)
        .onChange(of: linkPick) { _, picked in
            guard let picked else { return }
            if !draft.target.contactIDs.contains(picked) { draft.target.contactIDs.append(picked) }
            linkPick = nil
        }
    }

    private var canLookUp: Bool {
        !lookingUp && !t.website.isBlank && Targets.siteRoot(t.website) != lookedUp
    }

    private var lookUpSummary: String {
        var found: [String] = []
        if !draft.findings.submissionLinks.isEmpty { found.append("a submissions page") }
        if !draft.findings.emails.isEmpty { found.append(draft.findings.emails.count == 1 ? "an email address" : "\(draft.findings.emails.count) email addresses") }
        return found.isEmpty ? "Filled in from their site. No submission details found there." : "Filled in from their site, including \(found.joined(separator: " and ")). Check them before saving."
    }

    private func lookUp() {
        let link = t.website
        lookingUp = true
        Task {
            let found = await model.lookUpTarget(link)
            lookingUp = false
            lookedUp = Targets.siteRoot(link)
            var current = draft.target
            let f = found.target
            if current.name.isBlank { current.name = f.name }
            if !exists && current.kind == .publication && f.kind != .publication { current.kind = f.kind }
            if current.notes.isBlank { current.notes = f.notes }
            if current.submissionURL.isBlank { current.submissionURL = f.submissionURL }
            if current.submissionEmail.isBlank { current.submissionEmail = f.submissionEmail }
            if found.problem == nil {
                current.website = f.website
                current.lastChecked = f.lastChecked
            }
            draft.target = current
            draft.findings = found.findings
            draft.problem = found.problem
        }
    }
}

// MARK: - Suggestions

private struct TargetSuggestionsSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var suggestions: [Target] = []
    @State private var include = Set<UUID>()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add from your contacts and coverage").font(.title2.weight(.semibold))
            Text("Outlets, labels and others you already have contacts at or coverage from, that aren't on your Targets list yet. Ones that have covered you start as “Covered you”.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if suggestions.isEmpty {
                Text("Nothing to suggest — everything is already on your list.").foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach($suggestions) { $t in
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { include.contains(t.id) },
                                set: { on in if on { include.insert(t.id) } else { include.remove(t.id) } }))
                                .labelsHidden()
                                .accessibilityLabel("Add \(t.displayName)")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.displayName)
                                Text(source(t)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("Type", selection: $t.kind) {
                                ForEach(TargetKind.allCases) { Text($0.shortLabel).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }
                    }
                }
            }
            HStack {
                Button("Select All") { include = Set(suggestions.map(\.id)) }.disabled(suggestions.isEmpty)
                Button("Select None") { include.removeAll() }.disabled(include.isEmpty)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add \(include.count)") {
                    let chosen = suggestions.filter { include.contains($0.id) }
                    model.addTargets(chosen, title: "Added \(chosen.count) target\(chosen.count == 1 ? "" : "s") from contacts and coverage")
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(include.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620, height: 560)
        .onAppear {
            suggestions = Targets.suggestions(in: model.workspace)
            include = Set(suggestions.map(\.id))
        }
    }

    private func source(_ t: Target) -> String {
        if t.status == .won { return "From your coverage" }
        let names = t.contactIDs.compactMap { model.workspace.contact($0)?.displayName }
        return names.isEmpty ? "From your contacts" : "Contacts: " + names.prefix(3).joined(separator: ", ")
    }
}

// MARK: - CSV import

private struct TargetImportSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var preview: TargetImportPreview
    var fileName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import targets").font(.title2.weight(.semibold))
            Text("\(fileName): \(preview.totalRows) row\(preview.totalRows == 1 ? "" : "s"). Columns Manager understands include name, type, status, priority, website, submission_url, submission_email, accepts_submissions, genres, location, similar_artists, guidelines, notes, tags and next_check.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Label("\(preview.added.count) to add", systemImage: "plus.circle")
                Label("\(preview.duplicates.count) already on your list", systemImage: "doc.on.doc")
                Label("\(preview.skipped.count) skipped", systemImage: "minus.circle")
            }
            List {
                if !preview.added.isEmpty {
                    Section("To add") {
                        ForEach(preview.added) { t in
                            VStack(alignment: .leading) {
                                Text(t.displayName)
                                Text([t.kind.shortLabel, t.status.label(for: t.kind), t.website].filter { !$0.isBlank }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !preview.duplicates.isEmpty || !preview.skipped.isEmpty {
                    Section("Not imported") {
                        ForEach(preview.duplicates + preview.skipped, id: \.self) { Text($0).font(.callout) }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import \(preview.added.count)") {
                    model.importTargets(preview, fileName: fileName)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!preview.hasChanges)
            }
        }
        .padding(20)
        .frame(width: 620, height: 560)
    }
}
