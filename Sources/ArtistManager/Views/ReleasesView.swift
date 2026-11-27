import SwiftUI

struct ReleasesView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedID: UUID?

    private var releases: [Release] {
        model.workspace.releases.sorted { a, b in
            if a.stage.isActive != b.stage.isActive { return a.stage.isActive }
            return (a.releaseDate ?? .distantFuture) < (b.releaseDate ?? .distantFuture)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Releases").font(.title2.weight(.semibold))
                    Spacer()
                    Button {
                        addRelease()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("New release")
                    .accessibilityLabel("New release")
                }
                .padding()
                List(selection: $selectedID) {
                    ForEach(releases) { release in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(release.title.isBlank ? "Untitled release" : release.title).fontWeight(.medium)
                            Text([release.type.label, release.releaseDate?.shortDate ?? "No date", release.stage.label].joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(release.id)
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(width: 260)
            Divider()
            if let id = selectedID, let release = model.workspace.releases.first(where: { $0.id == id }) {
                ReleaseDetail(release: release)
                    .id(release.id)
            } else if model.workspace.releases.isEmpty {
                EmptyStateView(title: "No releases yet", symbol: "opticaldisc",
                               message: "Plan a single, EP or album. Give it a date and Manager builds the campaign timeline, checks metadata and tracks the budget.",
                               actionTitle: "Plan a Release", action: addRelease)
            } else {
                EmptyStateView(title: "Choose a release", symbol: "opticaldisc", message: "Select a release on the left to see its plan.")
            }
        }
        .onAppear {
            if let focus = model.focusedRecordID, model.workspace.releases.contains(where: { $0.id == focus }) {
                selectedID = focus
                model.focusedRecordID = nil
            } else if selectedID == nil {
                selectedID = releases.first?.id
            }
        }
    }

    private func addRelease() {
        var release = Release()
        release.title = "New Single"
        release.releaseDate = Date().startOfDay.adding(days: 56).nextOccurrence(ofWeekday: 6)
        release.tracks = [Track(title: "New Single")]
        release.assets = [AssetItem(name: "Cover artwork", kind: .artwork), AssetItem(name: "Spotify Canvas", kind: .canvas),
                          AssetItem(name: "Press photos", kind: .photo)]
        let r = release
        model.perform("Created release “\(r.title)”", showUndo: true) { $0.upsert(r, in: \.releases) }
        selectedID = r.id
    }
}

struct ReleaseDetail: View {
    @EnvironmentObject var model: AppModel
    @State var release: Release
    @State private var tab: DetailTab = .overview
    @State private var confirmDelete = false

    enum DetailTab: String, CaseIterable, Identifiable {
        case overview, tracks, metadata, assets, campaign, budget
        var id: String { rawValue }
        var label: String {
            switch self {
            case .overview: return "Overview"
            case .tracks: return "Tracks & credits"
            case .metadata: return "Metadata check"
            case .assets: return "Artwork & assets"
            case .campaign: return "Campaign"
            case .budget: return "Budget"
            }
        }
    }

    private var stored: Release? { model.workspace.releases.first { $0.id == release.id } }
    /// False once the release is deleted, so leaving the page doesn't bring it back.
    private var hasChanges: Bool {
        guard let s = stored else { return false }
        return s != release
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(release.title.isBlank ? "Untitled release" : release.title).font(.title.weight(.semibold))
                    Text("\(release.type.label) · \(release.releaseDate?.formatted(date: .long, time: .omitted) ?? "No date") · \(release.stage.label)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Revert") { if let s = stored { release = s } }.disabled(!hasChanges)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!hasChanges)
                Menu {
                    Button("Delete Release…", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
                .accessibilityLabel("More actions")
            }
            .padding()
            Picker("Section", selection: $tab) {
                ForEach(DetailTab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            Group {
                switch tab {
                case .overview: ReleaseOverviewForm(release: $release)
                case .tracks: TracksEditor(release: $release)
                case .metadata: MetadataCheckView(release: release)
                case .assets: AssetsEditor(release: $release)
                case .campaign: ReleaseCampaignView(release: release, hasUnsavedChanges: hasChanges, save: save)
                case .budget: ReleaseBudgetView(release: $release)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onDisappear { if hasChanges { save() } }
        .confirmationDialog("Delete “\(release.title)”?", isPresented: $confirmDelete) {
            Button("Delete Release", role: .destructive) {
                let id = release.id
                let title = release.title
                model.perform("Deleted release “\(title)”", showUndo: true) { ws in
                    ws.remove(id, from: \.releases)
                }
            }
        } message: {
            Text("Its tasks, budget lines and calendar entries stay, unlinked. You can undo this from the activity log.")
        }
    }

    private func save() {
        let updated = release
        let dateChanged = stored?.releaseDate != updated.releaseDate
        let hasTimeline = ReleaseTimeline.hasTimeline(updated.id, tasks: model.workspace.tasks)
        model.perform("Updated release “\(updated.title)”", showUndo: true) { ws in
            ws.upsert(updated, in: \.releases)
            // Keep the release-day calendar entry in step with the release date.
            if let index = ws.events.firstIndex(where: { $0.sourceKey == ReleaseTimeline.releaseDayKey(updated.id) }) {
                if let date = updated.releaseDate {
                    ws.events[index].start = date.startOfDay
                    ws.events[index].end = date.startOfDay
                    ws.events[index].title = "Release day: \(updated.title)"
                } else {
                    ws.events.remove(at: index)
                }
            }
        }
        if dateChanged && hasTimeline {
            model.showInfo("The release date changed. Open the Campaign tab to move the open campaign tasks to match.")
        }
    }
}

// MARK: - Overview

private struct ReleaseOverviewForm: View {
    @Binding var release: Release
    var body: some View {
        Form {
            Section("Release") {
                TextField("Title", text: $release.title)
                Picker("Type", selection: $release.type) {
                    ForEach(ReleaseType.allCases) { Text($0.label).tag($0) }
                }
                Picker("Stage", selection: $release.stage) {
                    ForEach(ReleaseStage.allCases) { Text($0.label).tag($0) }
                }
                OptionalDatePicker(title: "Release date", date: $release.releaseDate)
                if let date = release.releaseDate, date.weekday != 6 {
                    Label("Releases usually go out on Fridays.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Distribution") {
                TextField("Distributor", text: $release.distributor)
                TextField("Label (leave blank if self-released)", text: $release.label)
                TextField("UPC / EAN", text: $release.upc)
                TextField("Primary genre", text: $release.primaryGenre)
            }
            Section("Links") {
                TextField("Pre-save link", text: $release.preSaveURL)
                TextField("Smart link", text: $release.smartLinkURL)
            }
            Section("Notes") {
                TextEditor(text: $release.notes).frame(minHeight: 100).accessibilityLabel("Release notes")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tracks

private struct TracksEditor: View {
    @Binding var release: Release
    var body: some View {
        Form {
            ForEach($release.tracks) { $track in
                Section {
                    TextField("Title", text: $track.title)
                    TextField("Version (e.g. Radio Edit)", text: $track.version)
                    HStack {
                        TextField("ISRC", text: $track.isrc)
                        TextField("ISWC", text: $track.iswc)
                    }
                    HStack {
                        TextField("Duration (seconds)", value: $track.durationSeconds, format: .number)
                        Toggle("Explicit", isOn: $track.explicit)
                        Toggle("Mastered", isOn: $track.mastered)
                    }
                    TextField("Featured artists", text: $track.featuredArtists)
                    TextField("Producers", text: $track.producers)
                    SplitsEditor(track: $track)
                    Button("Remove Track", role: .destructive) {
                        release.tracks.removeAll { $0.id == track.id }
                    }
                } header: {
                    Text(track.title.isBlank ? "Untitled track" : track.title)
                }
            }
            Section {
                Button("Add Track") { release.tracks.append(Track()) }
            }
        }
        .formStyle(.grouped)
    }
}

private struct SplitsEditor: View {
    @Binding var track: Track
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Songwriter splits").font(.subheadline.weight(.medium))
                Spacer()
                let total = track.splitTotal
                Text("Total: \(total.formatted(.number.precision(.fractionLength(0...2))))%")
                    .foregroundStyle(abs(total - 100) < 0.01 || track.writers.isEmpty ? Color.secondary : Color.orange)
                    .accessibilityLabel("Splits total \(Int(total)) percent")
            }
            ForEach($track.writers) { $split in
                HStack {
                    TextField("Name", text: $split.name)
                    TextField("Role", text: $split.role).frame(maxWidth: 110)
                    TextField("%", value: $split.share, format: .number).frame(maxWidth: 60)
                    TextField("PRO", text: $split.pro).frame(maxWidth: 80)
                    TextField("IPI", text: $split.ipi).frame(maxWidth: 110)
                    Button {
                        track.writers.removeAll { $0.id == split.id }
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove songwriter")
                }
            }
            Button("Add Songwriter") {
                let remaining = max(0, 100 - track.splitTotal)
                track.writers.append(Split(share: remaining))
            }
            .controlSize(.small)
        }
    }
}

// MARK: - Metadata

private struct MetadataCheckView: View {
    var release: Release
    var body: some View {
        let issues = MetadataValidator.issues(for: release)
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Checks what distributors and collection societies need. Save first to check your latest edits — this reflects what's on screen.")
                    .foregroundStyle(.secondary)
                if issues.isEmpty {
                    Label("No problems found.", systemImage: "checkmark.seal").foregroundStyle(.green)
                }
                ForEach(issues) { issue in
                    Label {
                        Text(issue.message)
                    } icon: {
                        Image(systemName: issue.severity == .blocking ? "xmark.octagon" : "exclamationmark.triangle")
                            .foregroundStyle(issue.severity == .blocking ? Color.red : Color.orange)
                    }
                    .accessibilityLabel("\(issue.severity == .blocking ? "Must fix" : "Warning"): \(issue.message)")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Assets

private struct AssetsEditor: View {
    @Binding var release: Release
    var body: some View {
        Form {
            Section("Cover artwork") {
                Picker("Status", selection: $release.artworkStatus) {
                    ForEach(AssetStatus.allCases) { Text($0.label).tag($0) }
                }
                TextField("Notes (designer, file location, specs)", text: $release.artworkNotes, axis: .vertical)
                Text("Most distributors want a square 3000 × 3000 px RGB JPG or PNG, with no web addresses, prices or social handles.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Campaign assets") {
                ForEach($release.assets) { $asset in
                    HStack {
                        TextField("Name", text: $asset.name)
                        Picker("Kind", selection: $asset.kind) {
                            ForEach(AssetKind.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden().frame(maxWidth: 150)
                        Picker("Status", selection: $asset.status) {
                            ForEach(AssetStatus.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden().frame(maxWidth: 130)
                        Button {
                            release.assets.removeAll { $0.id == asset.id }
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove asset")
                    }
                    TextField("File or link", text: $asset.location).font(.caption)
                }
                Button("Add Asset") { release.assets.append(AssetItem(name: "New asset")) }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Campaign

private struct ReleaseCampaignView: View {
    @EnvironmentObject var model: AppModel
    var release: Release
    var hasUnsavedChanges: Bool
    var save: () -> Void

    var body: some View {
        let tasks = model.workspace.tasks.filter { $0.releaseID == release.id }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        let missing = ReleaseTimeline.missingTasks(for: release, existing: model.workspace.tasks, actor: .artist)
        let needsReschedule = ReleaseTimeline.hasTimeline(release.id, tasks: tasks)
            && release.timelineGeneratedFor.map { !$0.isSameDay(as: release.releaseDate ?? $0) } == true
        let coverage = model.workspace.coverage.filter { $0.releaseID == release.id }
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !coverage.isEmpty {
                    HStack {
                        Label("\(coverage.count) piece\(coverage.count == 1 ? "" : "s") of coverage saved", systemImage: "quote.bubble")
                        Spacer()
                        Button("Open in Coverage") {
                            model.open(.coverage, record: coverage.max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }?.id)
                        }
                    }
                    Divider()
                }
                if hasUnsavedChanges {
                    Label("Save your changes first so the timeline uses the latest date and type.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    if release.releaseDate == nil {
                        Text("Give the release a date to build its campaign timeline.").foregroundStyle(.secondary)
                    } else if !missing.isEmpty {
                        Button("Generate Campaign Timeline (\(missing.count) tasks)") { generate(missing) }
                            .buttonStyle(.borderedProminent)
                            .disabled(hasUnsavedChanges)
                    }
                    if needsReschedule {
                        Button("Move Open Tasks to Match New Date") { reschedule() }.disabled(hasUnsavedChanges)
                    }
                    Spacer()
                }
                if tasks.isEmpty {
                    Text("No tasks for this release yet.").foregroundStyle(.secondary)
                }
                ForEach(tasks) { task in
                    TaskRow(task: task)
                    Divider()
                }
            }
            .padding()
        }
    }

    private func generate(_ missing: [TaskItem]) {
        let r = release
        let event = ReleaseTimeline.releaseDayEvent(for: r, actor: .artist)
        model.perform("Generated the campaign timeline for “\(r.title)”", kind: .createTasks, detail: "\(missing.count) tasks", showUndo: true) { ws in
            ws.tasks.append(contentsOf: missing)
            if let event, !ws.events.contains(where: { $0.sourceKey == event.sourceKey }) { ws.events.append(event) }
            if let i = ws.releases.firstIndex(where: { $0.id == r.id }) { ws.releases[i].timelineGeneratedFor = r.releaseDate }
        }
    }

    private func reschedule() {
        let r = release
        model.perform("Moved campaign tasks for “\(r.title)” to the new date", kind: .createTasks, showUndo: true) { ws in
            ws.tasks = ReleaseTimeline.rescheduled(tasks: ws.tasks, for: r)
            if let i = ws.releases.firstIndex(where: { $0.id == r.id }) { ws.releases[i].timelineGeneratedFor = r.releaseDate }
        }
    }
}

// MARK: - Budget

private struct ReleaseBudgetView: View {
    @EnvironmentObject var model: AppModel
    @Binding var release: Release
    @State private var editing: BudgetLine?

    var body: some View {
        let currency = model.workspace.profile.budget.currency
        let lines = model.workspace.budgetLines.filter { $0.releaseID == release.id }
        let summary = BudgetMath.summary(for: release, lines: model.workspace.budgetLines)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    MoneyField(title: "Release budget", value: $release.budget, currency: currency).frame(maxWidth: 220)
                    Text("Save to keep budget changes.").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 24) {
                    LabeledContent("Planned", value: Money.format(summary.planned, currency: currency))
                    LabeledContent("Approved / paid", value: Money.format(summary.committed, currency: currency))
                    LabeledContent("Paid", value: Money.format(summary.paid, currency: currency))
                    LabeledContent("Remaining", value: Money.format(summary.remaining, currency: currency))
                }
                if summary.isOver {
                    Label("Planned costs are over this release's budget.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                Text("Spending is never committed for you. Lines you want to pay for go to Approvals first; mark them paid once you've paid.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(lines) { line in
                    BudgetLineRow(line: line, currency: currency) { editing = line }
                    Divider()
                }
                Button {
                    editing = BudgetLine(releaseID: release.id)
                } label: {
                    Label("Add Cost", systemImage: "plus")
                }
            }
            .padding()
        }
        .sheet(item: $editing) { line in
            BudgetLineEditor(line: line).environmentObject(model)
        }
    }
}

struct BudgetLineRow: View {
    @EnvironmentObject var model: AppModel
    var line: BudgetLine
    var currency: String
    var onEdit: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title.isBlank ? line.category.label : line.title).fontWeight(.medium)
                Text([line.category.label, line.vendor, line.date?.shortDate ?? ""].filter { !$0.isBlank }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(line.effectiveAmount, currency: currency)).monospacedDigit()
            StatusBadge(text: line.status.label, tone: line.status == .paid ? .success : (line.status == .awaitingApproval ? .warning : (line.status == .approved ? .info : .neutral)))
            if line.status == .planned {
                Button("Ask to Spend") { model.requestApproval(forSpend: line) }.controlSize(.small)
            }
            if line.status == .approved {
                ConfirmSentButton(title: "Mark Paid", explanation: "Confirm you've paid \(Money.format(max(line.planned, line.actual), currency: currency)). Manager doesn't make payments.") {
                    model.perform("Marked paid: \(line.title)", kind: .editRecord, showUndo: true) { ws in
                        if let i = ws.budgetLines.firstIndex(where: { $0.id == line.id }) {
                            ws.budgetLines[i].status = .paid
                            if ws.budgetLines[i].actual <= 0 { ws.budgetLines[i].actual = ws.budgetLines[i].planned }
                            if ws.budgetLines[i].date == nil { ws.budgetLines[i].date = Date() }
                        }
                    }
                }
                .controlSize(.small)
            }
            Button("Edit", action: onEdit).controlSize(.small)
        }
        .accessibilityElement(children: .contain)
    }
}

struct BudgetLineEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var line: BudgetLine

    var body: some View {
        let currency = model.workspace.profile.budget.currency
        VStack(spacing: 0) {
            Form {
                TextField("What it's for", text: $line.title)
                Picker("Category", selection: $line.category) {
                    ForEach(BudgetCategory.allCases) { Text($0.label).tag($0) }
                }
                TextField("Vendor", text: $line.vendor)
                MoneyField(title: "Planned", value: $line.planned, currency: currency)
                MoneyField(title: "Actual", value: $line.actual, currency: currency)
                OptionalDatePicker(title: "Date", date: $line.date)
                Picker("Release", selection: $line.releaseID) {
                    Text("Not tied to a release").tag(UUID?.none)
                    ForEach(model.workspace.releases) { Text($0.title).tag(Optional($0.id)) }
                }
                if line.status == .approved || line.status == .paid {
                    Text("Status: \(line.status.label). Changing the amount sends it back for approval.").font(.caption).foregroundStyle(.secondary)
                }
                TextField("Notes", text: $line.notes, axis: .vertical)
            }
            .formStyle(.grouped)
            HStack {
                if model.workspace.budgetLines.contains(where: { $0.id == line.id }) {
                    Button("Delete", role: .destructive) {
                        let l = line
                        model.perform("Deleted cost: \(l.title)", showUndo: true) { $0.remove(l.id, from: \.budgetLines) }
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    var l = line
                    // A changed amount isn't covered by an earlier approval or a pending request.
                    if let old = model.workspace.budgetLines.first(where: { $0.id == l.id }),
                       old.status == .approved || old.status == .awaitingApproval,
                       old.planned != l.planned || (old.actual != l.actual && l.actual > max(old.planned, old.actual)) {
                        l.status = .planned
                    }
                    let saved = l
                    model.perform("Saved cost: \(saved.title.isBlank ? saved.category.label : saved.title)", showUndo: true) { ws in
                        ws.upsert(saved, in: \.budgetLines)
                        if saved.status == .planned { ApprovalService.clearApprovalAfterEdit(subjectID: saved.id, in: &ws) }
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480, height: 520)
    }
}
