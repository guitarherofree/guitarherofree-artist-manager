import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PressView: View {
    @EnvironmentObject var model: AppModel
    @State private var page: Page = .kit
    @State private var showStatementPrep = false
    @State private var importingMediaList = false

    enum Page: String, CaseIterable, Identifiable {
        case kit, releases, outreach, playlists
        var id: String { rawValue }
        var label: String {
            switch self {
            case .kit: return "Press kit"
            case .releases: return "Press releases"
            case .outreach: return "Pitches"
            case .playlists: return "Playlists"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader("Press Kit", subtitle: "Your EPK, press releases, and review and playlist pitches. Saved reviews and articles live in Coverage.") {
                Menu {
                    Button("Import Media List (CSV)…") { importingMediaList = true }
                    Button("Prepare a Public Statement…") { showStatementPrep = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .fixedSize()
            }
            .padding([.horizontal, .top], 24)
            SectionPicker(options: Page.allCases, selection: $page, label: \.label)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            switch page {
            case .kit: PressKitEditor()
            case .releases: PressReleasesList()
            case .outreach:
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Review requests, press, radio, booking and sync pitches. Use Pitch Several to draft a personal note to many writers or outlets at once. Everything goes to Approvals before it can be sent; approved messages open in your mail app, you press Send, then mark them sent here.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        OutreachListView(kinds: Set(OutreachKind.allCases.filter(\.isEmail)))
                    }
                    .padding(24)
                }
            case .playlists: PlaylistsPane()
            }
        }
        .sheet(isPresented: $showStatementPrep) {
            StatementPrepSheet().environmentObject(model)
        }
        .sheet(isPresented: $importingMediaList) {
            ContactImportSheet(title: "Import a Media List", defaultRole: .journalist, defaultTags: ["Media list"])
                .environmentObject(model)
        }
        .onAppear {
            if let tab = model.requestedTab, let requested = Page(rawValue: tab) {
                page = requested
                model.requestedTab = nil
            } else if let focus = model.focusedRecordID, model.workspace.releases.contains(where: { $0.id == focus }) {
                // Older recommendations about a release's press release open a draft for it.
                page = .releases
            }
        }
    }
}

// MARK: - Electronic press kit

private struct PressKitEditor: View {
    @EnvironmentObject var model: AppModel
    @State private var draft = PressKit()
    @State private var loaded = false

    private var ws: Workspace { model.workspace }
    private var hasChanges: Bool { loaded && draft != ws.pressKit }

    var body: some View {
        let score = PressKitScore.evaluate(previewWorkspace)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ProgressView(value: score.score) {
                    Text("\(Int(score.score * 100))% complete").font(.callout.weight(.medium))
                }
                .frame(maxWidth: 260)
                if !score.missing.isEmpty {
                    Text("Missing: \(score.missing.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button("Revert") { draft = ws.pressKit }.disabled(!hasChanges)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!hasChanges)
                Menu {
                    Button("Preview in Browser") { saveIfNeeded(); model.previewPressKit() }
                    Button("Export as Web Page (HTML)…") { saveIfNeeded(); exportHTML() }
                    Button("Export as Markdown…") { saveIfNeeded(); exportMarkdown() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .fixedSize()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            Form {
                Section {
                    TextField("One-line description", text: $draft.headline, prompt: Text("e.g. Brooklyn songwriter making late-night synth folk"))
                    LabeledContent("Short bio") {
                        Text(ws.profile.bioShort.isBlank ? "Not written yet" : ws.profile.bioShort)
                            .foregroundStyle(ws.profile.bioShort.isBlank ? .secondary : .primary)
                            .lineLimit(4)
                    }
                    LabeledContent("Full bio") {
                        Text(ws.profile.bioLong.isBlank ? "Not written yet" : "\(ws.profile.bioLong.split(whereSeparator: \.isWhitespace).count) words")
                            .foregroundStyle(.secondary)
                    }
                    Button("Edit Bios in Profile") { saveIfNeeded(); model.selection = .profile }.buttonStyle(.link)
                } header: {
                    Text("Summary and bio")
                }
                photosSection
                Section("Music") {
                    ForEach($draft.featuredTracks) { $track in
                        HStack {
                            TextField("Track title", text: $track.title)
                            TextField("Link", text: $track.url)
                            Button {
                                draft.featuredTracks.removeAll { $0.id == track.id }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove featured track")
                        }
                    }
                    Button("Add Featured Track") { draft.featuredTracks.append(FeaturedTrack()) }
                    if !ws.profile.links.labeled.isEmpty {
                        Text("Also listed: \(ws.profile.links.labeled.map(\.label).joined(separator: ", ")) (from your profile links).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Credits, highlights and rider") {
                    labeledEditor("Credits (collaborators, labels, studios)", text: $draft.credits)
                    labeledEditor("Highlights (notable shows, placements, milestones)", text: $draft.achievements)
                    labeledEditor("Technical rider / stage plot notes", text: $draft.technicalRider)
                }
                contactSection("Booking contact", card: $draft.bookingContact, role: .bookingAgent)
                contactSection("Publicity contact", card: $draft.publicityContact, role: .publicist)
                Section("Press quotes") {
                    let quotes = ws.coverage.filter(\.includeInPressKit)
                    if quotes.isEmpty {
                        Text("Coverage you mark “show in my press kit” appears here, with its pull quote.").foregroundStyle(.secondary)
                    }
                    ForEach(quotes) { q in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(q.quote.isBlank ? q.title : "“\(q.quote)”")
                            Text(q.citation).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .onAppear {
            if !loaded { draft = ws.pressKit; loaded = true }
        }
        .onChange(of: model.workspace.pressKit) { _, newValue in
            if !hasChanges { draft = newValue }
        }
        .onDisappear { saveIfNeeded() }
    }

    /// The workspace as it would be with the unsaved edits, so the score updates while typing.
    private var previewWorkspace: Workspace {
        var copy = ws
        copy.pressKit = draft
        return copy
    }

    private var photosSection: some View {
        Section {
            if draft.photos.isEmpty {
                Text("Add two to five high-resolution photos (JPG or PNG work everywhere). Credit the photographer on each.")
                    .foregroundStyle(.secondary)
            }
            ForEach($draft.photos) { $photo in
                HStack(alignment: .top, spacing: 12) {
                    MediaThumbnail(url: model.persistence.mediaFile(photo.fileName))
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel(photo.caption.isBlank ? "Press photo" : photo.caption)
                    VStack(alignment: .leading) {
                        TextField("Caption / alt text", text: $photo.caption)
                        TextField("Photographer credit", text: $photo.photographerCredit)
                        HStack {
                            Toggle("Main photo", isOn: Binding(
                                get: { photo.isPrimary },
                                set: { on in
                                    for i in draft.photos.indices { draft.photos[i].isPrimary = false }
                                    if let i = draft.photos.firstIndex(where: { $0.id == photo.id }) { draft.photos[i].isPrimary = on }
                                }))
                            Spacer()
                            Button("Remove", role: .destructive) {
                                draft.photos.removeAll { $0.id == photo.id }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            Button {
                let urls = FilePanels.openImages()
                guard !urls.isEmpty else { return }
                var added = model.copyPressPhotos(from: urls)
                if !draft.photos.contains(where: \.isPrimary), !added.isEmpty { added[0].isPrimary = true }
                draft.photos.append(contentsOf: added)
            } label: {
                Label("Add Photos…", systemImage: "photo.badge.plus")
            }
        } header: {
            Text("Photos")
        } footer: {
            Text("Photos are copied into Manager's data folder and embedded in exported press kits.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func contactSection(_ title: String, card: Binding<ContactCard>, role: ContactRole) -> some View {
        Section {
            TextField("Name", text: card.name)
            TextField("Company", text: card.organization)
            TextField("Email", text: card.email)
            TextField("Phone", text: card.phone)
            let candidates = ws.contacts.filter { $0.role == role || ($0.isTeamMember && role == .publicist && $0.role == .manager) }
            if !candidates.isEmpty {
                Menu("Fill From Contacts") {
                    ForEach(candidates) { c in
                        Button(c.displayName) {
                            card.wrappedValue = ContactCard(name: c.name, organization: c.organization, email: c.email, phone: c.phone)
                        }
                    }
                }
                .fixedSize()
            }
        } header: {
            Text(title)
        }
    }

    private func labeledEditor(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: text).frame(minHeight: 70).font(.body).accessibilityLabel(label)
        }
    }

    private func save() {
        var kit = draft
        kit.updatedAt = Date()
        model.perform("Updated your press kit", showUndo: true) { $0.pressKit = kit }
        draft = model.workspace.pressKit
    }

    private func saveIfNeeded() { if hasChanges { save() } }

    private func exportHTML() {
        let html = PressKitRenderer.htmlDocument(workspace: model.workspace, photoData: { model.photoData($0) })
        model.exportText(html, suggestedName: "\(model.safeFileName(ws.profile.displayName)) Press Kit.html",
                         types: [.html], logTitle: "Exported press kit (HTML)")
    }

    private func exportMarkdown() {
        model.exportText(PressKitRenderer.markdown(workspace: model.workspace),
                         suggestedName: "\(model.safeFileName(ws.profile.displayName)) Press Kit.md",
                         types: [UTType(filenameExtension: "md") ?? .plainText], logTitle: "Exported press kit (Markdown)")
    }
}

// MARK: - Press releases

private struct PressReleasesList: View {
    @EnvironmentObject var model: AppModel
    @State private var editing: PressRelease?

    private var items: [PressRelease] {
        model.workspace.pressReleases.sorted { ($0.publishDate ?? $0.createdAt) > ($1.publishDate ?? $1.createdAt) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Drafts are generated from a release and your bio. You distribute them yourself.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(model.workspace.releases) { release in
                        Button("From “\(release.title)”") { generate(for: release) }
                    }
                    if !model.workspace.releases.isEmpty { Divider() }
                    Button("Blank Press Release") {
                        editing = PressRelease(dateline: model.workspace.profile.location)
                    }
                } label: {
                    Label("New Press Release", systemImage: "doc.badge.plus")
                }
                .fixedSize()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            if items.isEmpty {
                EmptyStateView(title: "No press releases", symbol: "doc.text",
                               message: "Generate one from a release to get a formatted draft with the date, tracklist, bio and press contact filled in.")
            } else {
                List(items) { pr in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pr.headline.isBlank ? "Untitled press release" : pr.headline).fontWeight(.medium)
                            Text([model.workspace.release(pr.releaseID)?.title ?? "", pr.publishDate.map { "for \($0.shortDate)" } ?? ""]
                                .filter { !$0.isBlank }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusBadge(text: pr.status.label, tone: pr.status == .distributed ? .success : (pr.status == .ready ? .info : .draft))
                        Button("Edit") { editing = pr }.controlSize(.small)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .sheet(item: $editing) { pr in
            PressReleaseEditor(pressRelease: pr).environmentObject(model)
        }
        .onAppear {
            guard let focus = model.focusedRecordID, let release = model.workspace.release(focus) else { return }
            model.focusedRecordID = nil
            if let existing = model.workspace.pressReleases.first(where: { $0.releaseID == release.id }) {
                editing = existing
            } else {
                generate(for: release)
            }
        }
    }

    private func generate(for release: Release) {
        let draft = Drafting.pressRelease(for: release, profile: model.workspace.profile, pressKit: model.workspace.pressKit)
        var mine = draft
        mine.createdBy = .artist
        editing = mine
    }
}

private struct PressReleaseEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var pressRelease: PressRelease
    @State private var confirmDistributed = false

    private var exists: Bool { model.workspace.pressReleases.contains { $0.id == pressRelease.id } }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Headline") {
                    TextField("Headline", text: $pressRelease.headline)
                    TextField("Subheadline", text: $pressRelease.subheadline)
                    TextField("Dateline (city)", text: $pressRelease.dateline)
                    OptionalDatePicker(title: "Planned release to press", date: $pressRelease.publishDate)
                    ReleasePicker(selection: $pressRelease.releaseID)
                }
                Section("Body") {
                    TextEditor(text: $pressRelease.body).frame(minHeight: 260).font(.body).accessibilityLabel("Press release body")
                    Text("Fill in anything in [brackets] before you send it.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Status") {
                    Picker("Status", selection: $pressRelease.status) {
                        Text(PressReleaseStatus.draft.label).tag(PressReleaseStatus.draft)
                        Text(PressReleaseStatus.ready.label).tag(PressReleaseStatus.ready)
                        if pressRelease.status == .distributed {
                            Text(PressReleaseStatus.distributed.label).tag(PressReleaseStatus.distributed)
                        }
                    }
                    if pressRelease.status == .ready {
                        Button("I've Distributed It…") { confirmDistributed = true }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if exists {
                    Button("Delete", role: .destructive) {
                        let pr = pressRelease
                        model.perform("Deleted press release: \(pr.headline)", showUndo: true) { $0.remove(pr.id, from: \.pressReleases) }
                        dismiss()
                    }
                }
                Button("Copy Text") { Clipboard.copy(Drafting.pressReleaseText(pressRelease)) }
                Button("Save as Text…") {
                    model.exportText(Drafting.pressReleaseText(pressRelease), suggestedName: "\(model.safeFileName(pressRelease.headline)).txt",
                                     types: [.plainText], logTitle: "Exported press release")
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    let pr = pressRelease
                    model.perform(exists ? "Updated press release: \(pr.headline)" : "Drafted press release: \(pr.headline)",
                                  kind: .draftMaterials, status: .drafted, showUndo: true) { $0.upsert(pr, in: \.pressReleases) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(pressRelease.headline.isBlank)
            }
            .padding()
        }
        .frame(width: 680, height: 700)
        .confirmationDialog("Record this press release as distributed?", isPresented: $confirmDistributed) {
            Button("Record as Distributed") { pressRelease.status = .distributed }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Manager doesn't distribute press releases. Confirm you sent or published it yourself, then save.")
        }
    }
}

// MARK: - Playlists (Spotify editorial and independent curators)

private struct PlaylistsPane: View {
    @EnvironmentObject var model: AppModel
    @State private var editingPitch: Outreach?
    @State private var loggingAdd: CoverageDraft?

    private var upcoming: [Release] {
        model.workspace.releases
            .filter { $0.stage.isActive && ($0.releaseDate ?? .distantFuture) >= Date().startOfDay }
            .sorted { ($0.releaseDate ?? .distantFuture) < ($1.releaseDate ?? .distantFuture) }
    }

    private var adds: [Coverage] {
        model.workspace.coverage.filter { $0.kind == .playlistAdd }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card("Spotify editorial pitch", symbol: "music.note.house") {
                    Text("Pitch one unreleased song per release to Spotify's playlist editors. At least 7 days before release it also reaches your followers' Release Radar; about four weeks ahead is best. You fill in the form here and approve it, then submit it yourself in Spotify for Artists.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if upcoming.isEmpty {
                        Text("No upcoming releases. Give a release a future date in Releases to pitch it.").foregroundStyle(.secondary)
                    }
                    ForEach(upcoming) { release in
                        Divider()
                        SpotifyPitchRow(release: release, onEdit: { editingPitch = $0 })
                    }
                }
                Card("Independent playlist curators", symbol: "music.note.list") {
                    Text("Curators who take submissions by email. Use Pitch Several to draft a short, personal note to each one; Manager follows up a week later if there's no reply.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    OutreachListView(kinds: [.playlist], batchKind: .playlist, newPitchKinds: [.playlist])
                }
                Card("Playlist adds", symbol: "star") {
                    if adds.isEmpty {
                        Text("When your song lands on a playlist, log it here. Adds can appear in your press kit.").foregroundStyle(.secondary)
                    }
                    ForEach(adds) { add in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(add.title.isBlank ? add.outlet : "\(add.title) — \(add.outlet)").fontWeight(.medium)
                                Text([add.date?.shortDate ?? "", model.workspace.release(add.releaseID)?.title ?? ""].filter { !$0.isBlank }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Edit") { loggingAdd = CoverageDraft(coverage: add, keepCopy: false) }.controlSize(.small)
                        }
                    }
                    Button {
                        loggingAdd = model.newCoverageDraft(kind: .playlistAdd)
                    } label: {
                        Label("Log a Playlist Add", systemImage: "plus")
                    }
                }
            }
            .padding(24)
        }
        .sheet(item: $editingPitch) { item in
            SpotifyPitchEditor(item: item).environmentObject(model)
        }
        .sheet(item: $loggingAdd) { draft in
            CoverageEditor(draft: draft).environmentObject(model)
        }
        .onAppear {
            guard let focus = model.focusedRecordID, let release = model.workspace.release(focus) else { return }
            model.focusedRecordID = nil
            editingPitch = SpotifyPitchRow.pitch(for: release, in: model.workspace) ?? SpotifyPitchEditor.newPitch(for: release, workspace: model.workspace)
        }
    }
}

private struct SpotifyPitchRow: View {
    @EnvironmentObject var model: AppModel
    var release: Release
    var onEdit: (Outreach) -> Void

    static func pitch(for release: Release, in ws: Workspace) -> Outreach? {
        ws.outreach.filter { $0.kind == .spotifyEditorial && $0.releaseID == release.id }.max { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        let pitch = Self.pitch(for: release, in: model.workspace)
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(release.title.isBlank ? "Untitled release" : release.title).fontWeight(.medium)
                if let date = release.releaseDate {
                    Text("Out \(date.shortDate) · best by \(EditorialPitch.recommendedDate(for: date).shortDate) · Release Radar cutoff \(EditorialPitch.deadline(for: date).shortDate)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let song = pitch?.editorial?.trackTitle, !song.isBlank {
                    Text("Song: \(song)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let pitch {
                if pitch.status == .sent {
                    StatusBadge(text: "Submitted (confirmed by you)", tone: .success, symbol: "paperplane")
                } else {
                    pitch.status.badge
                }
            } else {
                StatusBadge(text: "Not pitched", tone: .neutral, symbol: "circle.dashed")
            }
            HStack(spacing: 6) {
                if let pitch {
                    switch pitch.status {
                    case .awaitingApproval:
                        Button("Review") { model.selection = .approvals }
                    case .approved:
                        Button("Copy Fields") { Clipboard.copy(pitch.editorial?.formText ?? pitch.body) }
                        Link("Open Spotify for Artists", destination: EditorialPitch.submitURL)
                        ConfirmSentButton(title: "Mark Submitted",
                                          explanation: "Confirm you submitted this pitch in Spotify for Artists yourself.") {
                            model.markOutreachSent(pitch.id)
                        }
                    default:
                        EmptyView()
                    }
                    Button(pitch.status == .sent ? "View" : "Edit") { onEdit(pitch) }
                } else {
                    Button("Start Pitch") { onEdit(SpotifyPitchEditor.newPitch(for: release, workspace: model.workspace)) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.small)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Public statement prep

private struct StatementPrepSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var topic = ""
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prepare a public statement").font(.title2.weight(.semibold))
            Text("A framework for responding to a public relations issue. Nothing is published from Manager.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("What's the issue?", text: $topic)
                Button("Build Outline") { text = ConversationPrep.statementOutline(topic: topic, profile: model.workspace.profile) }
                    .keyboardShortcut(.defaultAction)
            }
            TextEditor(text: $text)
                .font(.body)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                .accessibilityLabel("Statement outline")
            HStack {
                Button("Copy") { Clipboard.copy(text) }.disabled(text.isBlank)
                Button("Add Follow-up Task") {
                    let task = TaskItem(title: "Statement: \(topic.isBlank ? "PR issue" : topic)", notes: text,
                                        due: Date().startOfDay, area: .press, priority: .high)
                    model.perform("Added task: \(task.title)", kind: .createTasks, showUndo: true) { $0.tasks.append(task) }
                    dismiss()
                }
                .disabled(text.isBlank)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 660, height: 600)
        .onAppear { text = ConversationPrep.statementOutline(topic: "", profile: model.workspace.profile) }
    }
}
