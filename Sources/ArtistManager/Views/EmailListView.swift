import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EmailListView: View {
    @EnvironmentObject var model: AppModel
    @State private var page: Page = .overview
    @State private var importing = false
    @State private var editingSubscriber: Subscriber?

    enum Page: String, CaseIterable, Identifiable {
        case overview, subscribers, segments, campaigns
        var id: String { rawValue }
        var label: String {
            switch self {
            case .overview: return "Overview"
            case .subscribers: return "Subscribers"
            case .segments: return "Segments"
            case .campaigns: return "Campaigns"
            }
        }
    }

    private var ws: Workspace { model.workspace }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader("Email List", subtitle: subtitle) {
                HStack {
                    Button {
                        editingSubscriber = Subscriber(consent: ConsentRecord(method: .manual, capturedAt: Date()))
                    } label: {
                        Label("Add Subscriber", systemImage: "person.badge.plus")
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("Import CSV…", systemImage: "square.and.arrow.down")
                    }
                    Menu {
                        Button("All Subscribers, With Status and Consent…") {
                            model.exportText(SubscriberExporter.csv(ws.subscribers), suggestedName: "Email list — full.csv",
                                             types: [.commaSeparatedText], logTitle: "Exported full email list")
                        }
                        Button("Subscribed Only, for Your Email Provider…") {
                            model.exportText(SubscriberExporter.sendableCSV(ws.subscribers), suggestedName: "Email list — subscribed.csv",
                                             types: [.commaSeparatedText], logTitle: "Exported subscribed addresses")
                        }
                        Button("Do-Not-Email List (Unsubscribed, Bounced, Complaints)…") {
                            model.exportText(SubscriberExporter.suppressionCSV(ws.subscribers), suggestedName: "Email list — do not email.csv",
                                             types: [.commaSeparatedText], logTitle: "Exported suppression list")
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .fixedSize()
                    .disabled(ws.subscribers.isEmpty)
                }
            }
            .padding([.horizontal, .top], 24)
            SectionPicker(options: Page.allCases, selection: $page, label: \.label)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            switch page {
            case .overview: EmailOverview(onImport: { importing = true }, onEdit: { editingSubscriber = $0 })
            case .subscribers: SubscriberTable(onEdit: { editingSubscriber = $0 })
            case .segments: SegmentsPane()
            case .campaigns: CampaignsPane()
            }
        }
        .sheet(isPresented: $importing) {
            SubscriberImportSheet().environmentObject(model)
        }
        .sheet(item: $editingSubscriber) { subscriber in
            SubscriberEditor(subscriber: subscriber).environmentObject(model)
        }
        .onAppear {
            if let tab = model.requestedTab, let requested = Page(rawValue: tab) {
                page = requested
                model.requestedTab = nil
            }
            if let focus = model.focusedRecordID, ws.releases.contains(where: { $0.id == focus }) || ws.campaigns.contains(where: { $0.id == focus }) {
                page = .campaigns
            }
        }
    }

    private var subtitle: String {
        let subscribed = ws.subscribers.filter { $0.status == .subscribed }.count
        return "\(subscribed) subscribed · \(ws.subscribers.count) addresses in total, including unsubscribed and bounced"
    }
}

// MARK: - Overview: list health, consent and hygiene

private struct EmailOverview: View {
    @EnvironmentObject var model: AppModel
    var onImport: () -> Void
    var onEdit: (Subscriber) -> Void

    var body: some View {
        let subscribers = model.workspace.subscribers
        if subscribers.isEmpty {
            EmptyStateView(title: "No subscribers yet", symbol: "envelope.open",
                           message: "Import your list from your email provider (Mailchimp, Kit, MailerLite, Bandcamp and others export CSV), or add people from a merch-table signup sheet. Unsubscribes and bounces in the file are kept.",
                           actionTitle: "Import CSV…", action: onImport)
        } else {
            let report = ListHygiene.report(subscribers)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        statusCard(report)
                        consentCard(subscribers)
                    }
                    hygieneCard(report)
                    sourcesCard(subscribers)
                    Card("How sending works", symbol: "paperplane") {
                        Text("Manager doesn't send email. Draft a campaign, approve it, and export it with its recipient list and do-not-email list for your email provider. Your provider adds the unsubscribe link and handles bounces. Import its campaign report afterwards: bounces, unsubscribes and spam complaints are applied here, and an import can never re-subscribe someone who left.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
            }
        }
    }

    private func statusCard(_ report: ListHygieneReport) -> some View {
        Card("List status", symbol: "chart.bar") {
            ForEach(SubscriptionStatus.allCases) { status in
                HStack {
                    status.badge
                    Spacer()
                    Text("\(report.count(status))").monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func consentCard(_ subscribers: [Subscriber]) -> some View {
        let subscribed = subscribers.filter { $0.status == .subscribed }
        let withConsent = subscribed.filter { $0.consent != nil }.count
        let methods = Dictionary(grouping: subscribed.compactMap(\.consent), by: \.method).mapValues(\.count)
        return Card("Consent records", symbol: "checkmark.seal") {
            ProgressView(value: subscribed.isEmpty ? 1 : Double(withConsent) / Double(subscribed.count)) {
                Text("\(withConsent) of \(subscribed.count) subscribed addresses have a consent record")
            }
            ForEach(ConsentMethod.allCases.filter { methods[$0] != nil }) { method in
                HStack {
                    Text(method.label)
                    Spacer()
                    Text("\(methods[method] ?? 0)").monospacedDigit()
                }
                .font(.callout)
            }
            Text("A consent record says how and when someone agreed to hear from you. Keep one for everyone you email.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func hygieneCard(_ report: ListHygieneReport) -> some View {
        Card("List hygiene", symbol: "sparkles") {
            if report.issueCount == 0 {
                Label("No problems found.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
            issueGroup("Subscribed without a consent record", report.subscribedWithoutConsent,
                       help: "Check where these came from. Add a consent record, or mark them unsubscribed if you can't confirm it.")
            typoGroup(report.likelyTypos)
            issueGroup("Invalid addresses", report.invalidAddresses, help: "These can't receive email. Fix or remove them.")
            issueGroup("Role addresses (info@, booking@…)", report.roleAccounts,
                       help: "Shared inboxes often mark list email as spam. Keep them only if someone there signed up.")
            issueGroup("Pending for over 30 days", report.stalePending,
                       help: "They never confirmed. Don't email them; your provider may let you resend one confirmation.")
            issueGroup("Duplicate addresses", report.duplicateAddresses, help: "The same address appears more than once.")
        }
    }

    @ViewBuilder
    private func issueGroup(_ title: String, _ emails: [String], help: String) -> some View {
        if !emails.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 4) {
                    Text(help).font(.caption).foregroundStyle(.secondary)
                    ForEach(emails.prefix(100), id: \.self) { email in
                        HStack {
                            Text(email).font(.callout.monospaced()).textSelection(.enabled)
                            Spacer()
                            if let s = subscriber(email) {
                                Button("Edit") { onEdit(s) }.controlSize(.small)
                            }
                        }
                    }
                    if emails.count > 100 { Text("and \(emails.count - 100) more").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.leading, 4)
            } label: {
                Label("\(title): \(emails.count)", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func typoGroup(_ emails: [String]) -> some View {
        if !emails.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 4) {
                    Text("These look like misspelled domains. Fix only if you're sure — the person may really use that address.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(emails, id: \.self) { email in
                        HStack {
                            Text(email).font(.callout.monospaced())
                            if let fix = EmailAddress.suggestedFix(email) {
                                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                Text(fix).font(.callout.monospaced())
                                Spacer()
                                Button("Use \(fix)") { applyFix(email, fix) }.controlSize(.small)
                            }
                        }
                    }
                }
                .padding(.leading, 4)
            } label: {
                Label("Likely typos: \(emails.count)", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        }
    }

    private func sourcesCard(_ subscribers: [Subscriber]) -> some View {
        let groups = Dictionary(grouping: subscribers, by: { $0.signupSource.isBlank ? "Unknown" : $0.signupSource })
            .map { entry in
                SourceGroup(source: entry.key, total: entry.value.count,
                            subscribed: entry.value.filter { $0.status == .subscribed }.count)
            }
            .sorted { $0.total > $1.total }
        return Card("Signup sources", symbol: "arrow.down.forward.and.arrow.up.backward") {
            ForEach(groups.prefix(12)) { group in
                HStack {
                    Text(group.source)
                    Spacer()
                    Text("\(group.subscribed) subscribed of \(group.total)").font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if groups.contains(where: { $0.source == "Unknown" }) {
                Text("Record a source (website form, merch table, show, contest) so you can see what grows your list.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private struct SourceGroup: Identifiable {
        var source: String
        var total: Int
        var subscribed: Int
        var id: String { source }
    }

    private func subscriber(_ email: String) -> Subscriber? {
        model.workspace.subscribers.first { EmailAddress.normalize($0.email) == EmailAddress.normalize(email) }
    }

    private func applyFix(_ email: String, _ fix: String) {
        guard let s = subscriber(email) else { return }
        if model.workspace.subscribers.contains(where: { EmailAddress.normalize($0.email) == fix }) {
            model.showError("\(fix) is already on your list.")
            return
        }
        model.perform("Corrected \(email) to \(fix)", kind: .organizeData, showUndo: true) { ws in
            if let i = ws.subscribers.firstIndex(where: { $0.id == s.id }) { ws.subscribers[i].email = fix }
        }
    }
}

// MARK: - Subscribers table

private struct SubscriberTable: View {
    @EnvironmentObject var model: AppModel
    var onEdit: (Subscriber) -> Void
    @State private var search = ""
    @State private var status: SubscriptionStatus?
    @State private var selection = Set<Subscriber.ID>()
    @State private var sortOrder = [KeyPathComparator(\Subscriber.email)]
    @State private var pendingDelete: [UUID] = []

    private var rows: [Subscriber] {
        model.workspace.subscribers.filter { s in
            if let status, s.status != status { return false }
            if search.isBlank { return true }
            return s.email.localizedCaseInsensitiveContains(search) || s.fullName.localizedCaseInsensitiveContains(search)
                || s.tags.contains { $0.localizedCaseInsensitiveContains(search) } || s.signupSource.localizedCaseInsensitiveContains(search)
        }
        .sorted(using: sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Search email, name, tag or source", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                Picker("Status", selection: $status) {
                    Text("Any status").tag(SubscriptionStatus?.none)
                    ForEach(SubscriptionStatus.allCases) { Text($0.label).tag(Optional($0)) }
                }
                .frame(maxWidth: 220)
                Spacer()
                Text("\(rows.count) shown").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            if model.workspace.subscribers.isEmpty {
                EmptyStateView(title: "No subscribers yet", symbol: "envelope.open", message: "Import a CSV or add someone by hand.")
            } else {
                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Email", value: \.email) { s in Text(s.email).textSelection(.enabled) }
                    TableColumn("Name", value: \.fullName)
                    TableColumn("Status", value: \.status.label) { s in s.status.badge }
                        .width(min: 120, ideal: 150)
                    TableColumn("Source", value: \.signupSource)
                    TableColumn("Consent", value: \.consentSummary) { s in
                        Text(s.consentSummary).foregroundStyle(s.consent == nil && s.status == .subscribed ? Color.orange : Color.primary)
                    }
                    TableColumn("Tags", value: \.tagsText)
                    TableColumn("Added", value: \.createdAt) { s in Text(s.createdAt.shortDate) }
                        .width(min: 80, ideal: 100)
                }
                .contextMenu(forSelectionType: Subscriber.ID.self) { ids in
                    if ids.count == 1, let id = ids.first, let s = model.workspace.subscribers.first(where: { $0.id == id }) {
                        Button("Edit…") { onEdit(s) }
                    }
                    if !ids.isEmpty {
                        Button("Mark Unsubscribed") { markUnsubscribed(ids) }
                        Divider()
                        Button("Delete…", role: .destructive) { pendingDelete = Array(ids) }
                    }
                } primaryAction: { ids in
                    if let id = ids.first, let s = model.workspace.subscribers.first(where: { $0.id == id }) { onEdit(s) }
                }
            }
        }
        .confirmationDialog("Delete \(pendingDelete.count) subscriber\(pendingDelete.count == 1 ? "" : "s")?",
                            isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } })) {
            Button("Mark Unsubscribed Instead") { markUnsubscribed(Set(pendingDelete)); pendingDelete = [] }
            Button("Delete", role: .destructive) {
                let ids = Set(pendingDelete)
                model.perform("Deleted \(ids.count) subscriber\(ids.count == 1 ? "" : "s")", showUndo: true) { ws in
                    ws.subscribers.removeAll { ids.contains($0.id) }
                }
                pendingDelete = []
            }
            Button("Cancel", role: .cancel) { pendingDelete = [] }
        } message: {
            Text("Deleting removes the address entirely, including from your do-not-email list, so a future import could add it back. If someone asked to stop hearing from you, mark them unsubscribed instead. Delete only for a request to erase their data.")
        }
    }

    private func markUnsubscribed(_ ids: Set<UUID>) {
        let now = Date()
        model.perform("Marked \(ids.count) subscriber\(ids.count == 1 ? "" : "s") unsubscribed", showUndo: true) { ws in
            for i in ws.subscribers.indices where ids.contains(ws.subscribers[i].id) && !ws.subscribers[i].status.isSuppressed {
                ws.subscribers[i].status = .unsubscribed
                ws.subscribers[i].statusChangedAt = now
                ws.subscribers[i].statusReason = "Marked unsubscribed by you"
            }
        }
    }
}

private extension Subscriber {
    var consentSummary: String {
        guard let consent else { return "None recorded" }
        return [consent.method.label, consent.capturedAt?.shortDate ?? ""].filter { !$0.isBlank }.joined(separator: " · ")
    }
    var tagsText: String { tags.commaJoined }
}

// MARK: - Editing one subscriber

private struct SubscriberEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var subscriber: Subscriber
    @State private var hasConsent: Bool
    @State private var consent: ConsentRecord
    @State private var resubscribeConfirmed = false

    init(subscriber: Subscriber) {
        _subscriber = State(initialValue: subscriber)
        _hasConsent = State(initialValue: subscriber.consent != nil)
        _consent = State(initialValue: subscriber.consent ?? ConsentRecord(method: .manual, capturedAt: Date()))
    }

    private var stored: Subscriber? { model.workspace.subscribers.first { $0.id == subscriber.id } }
    private var isNew: Bool { stored == nil }
    private var normalizedEmail: String { EmailAddress.normalize(subscriber.email) }
    private var duplicate: Bool {
        model.workspace.subscribers.contains { $0.id != subscriber.id && EmailAddress.normalize($0.email) == normalizedEmail }
    }
    /// Moving a suppressed address back to subscribed needs the person's fresh consent.
    private var isResubscribing: Bool {
        guard let stored else { return false }
        return stored.status.isSuppressed && !subscriber.status.isSuppressed
    }
    private var canSave: Bool {
        EmailAddress.isValid(normalizedEmail) && !duplicate
            && (!isResubscribing || (resubscribeConfirmed && hasConsent && !consent.evidence.isBlank))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Subscriber") {
                    TextField("Email", text: $subscriber.email)
                    if !subscriber.email.isBlank && !EmailAddress.isValid(normalizedEmail) {
                        Text("That doesn't look like an email address.").font(.caption).foregroundStyle(.red)
                    }
                    if duplicate {
                        Text("This address is already on your list.").font(.caption).foregroundStyle(.red)
                    }
                    TextField("First name", text: $subscriber.firstName)
                    TextField("Last name", text: $subscriber.lastName)
                    TextField("Location", text: $subscriber.location)
                    TagsField(title: "Tags", values: $subscriber.tags)
                }
                Section("Status") {
                    Picker("Status", selection: $subscriber.status) {
                        ForEach(SubscriptionStatus.allCases) { Text($0.label).tag($0) }
                    }
                    if isResubscribing {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("This address was \(stored?.status.label.lowercased() ?? "suppressed"). Only resubscribe someone who has asked to hear from you again.",
                                  systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Toggle("They asked to be resubscribed", isOn: $resubscribeConfirmed)
                            Text("Record how they asked in the consent evidence below.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let changed = stored?.statusChangedAt {
                        LabeledContent("Status changed", value: changed.shortDateTime)
                    }
                    if let reason = stored?.statusReason, !reason.isBlank {
                        LabeledContent("Reason", value: reason)
                    }
                }
                Section("Signup and consent") {
                    TextField("Signup source (e.g. website form, merch table)", text: $subscriber.signupSource)
                    Toggle("Has a consent record", isOn: $hasConsent)
                    if hasConsent {
                        Picker("How they agreed", selection: $consent.method) {
                            ForEach(ConsentMethod.allCases) { Text($0.label).tag($0) }
                        }
                        TextField("Where (form name, event, page)", text: $consent.source)
                        OptionalDatePicker(title: "When", date: $consent.capturedAt)
                        TextField("Evidence (e.g. signup sheet photo, form submission ID)", text: $consent.evidence, axis: .vertical)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Subscriber" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 540, height: 680)
    }

    private func save() {
        var s = subscriber
        s.email = normalizedEmail
        s.consent = hasConsent ? consent : nil
        if let stored, stored.status != s.status {
            s.statusChangedAt = Date()
            s.statusReason = isResubscribing ? "Resubscribed at their request" : "Changed by you"
        }
        let saved = s
        model.perform(isNew ? "Added subscriber \(saved.email)" : "Updated subscriber \(saved.email)", showUndo: true) { ws in
            ws.upsert(saved, in: \.subscribers)
        }
        dismiss()
    }
}

// MARK: - Importing a list

private struct SubscriberImportSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var fileName = ""
    @State private var text = ""
    @State private var options = SubscriberImportOptions()
    @State private var preview: SubscriberImportPreview?

    private var hasStatusColumn: Bool {
        preview?.recognizedColumns.contains { SubscriberImporter.statusKeys.contains($0) } ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import subscribers").font(.title2.weight(.semibold))
            Text("Choose a CSV from your email provider or a signup sheet. Status, consent and signup-date columns are read when present. Anyone unsubscribed, bounced or marked as spam here stays that way — an import can't re-subscribe them.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Choose CSV File…") { choose() }
                Text(fileName.isEmpty ? "No file chosen" : fileName).foregroundStyle(.secondary)
            }
            Form {
                TextField("Signup source for rows without one", text: $options.source)
                Picker("Status for rows without a status column", selection: $options.defaultStatus) {
                    ForEach([SubscriptionStatus.subscribed, .pending, .unsubscribed, .bounced]) { Text($0.label).tag($0) }
                }
                Picker("How these people agreed", selection: $options.consentMethod) {
                    ForEach(ConsentMethod.allCases) { Text($0.label).tag($0) }
                }
                TextField("Consent evidence for the whole file (optional)", text: $options.consentEvidence)
                TagsField(title: "Add tags", values: $options.tagsToAdd)
            }
            .formStyle(.grouped)
            .frame(height: 230)
            if let preview {
                previewSummary(preview)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(importTitle) {
                    if let preview { model.importSubscribers(preview, fileName: fileName) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!(preview?.hasChanges ?? false))
            }
        }
        .padding(20)
        .frame(width: 640, height: 760)
        .onChange(of: options) { _, _ in refresh() }
    }

    private var importTitle: String {
        guard let preview, preview.hasChanges else { return "Import" }
        return "Import \(preview.added.count + preview.updated.count) Address\(preview.added.count + preview.updated.count == 1 ? "" : "es")"
    }

    @ViewBuilder
    private func previewSummary(_ p: SubscriberImportPreview) -> some View {
        GroupBox("What will happen") {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(p.totalRows) rows read")
                    Label("\(p.added.count) new addresses", systemImage: "plus.circle")
                    Label("\(p.updated.count) existing addresses updated", systemImage: "arrow.triangle.merge")
                    if !hasStatusColumn && p.totalRows > 0 {
                        Label("No status column found, so every row is treated as “\(options.defaultStatus.label)”. If this is your provider's unsubscribed or cleaned export, change the status above.",
                              systemImage: "info.circle")
                            .foregroundStyle(.orange)
                    }
                    if p.missingConsent > 0 {
                        Label("\(p.missingConsent) new subscribed addresses have no consent date or evidence. Add evidence above if you have it.",
                              systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                    if !p.newlySuppressed.isEmpty {
                        listGroup("\(p.newlySuppressed.count) will be marked unsubscribed, bounced or complained", p.newlySuppressed)
                    }
                    if !p.suppressionsKept.isEmpty {
                        listGroup("\(p.suppressionsKept.count) stay unsubscribed or bounced (not re-subscribed)", p.suppressionsKept)
                    }
                    if !p.invalidRows.isEmpty {
                        listGroup("\(p.invalidRows.count) rows skipped", p.invalidRows)
                    }
                    if p.duplicateRowsInFile > 0 {
                        Text("\(p.duplicateRowsInFile) duplicate rows in the file were combined.").font(.callout)
                    }
                    if !p.recognizedColumns.isEmpty {
                        Text("Columns used: \(p.recognizedColumns.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                    }
                    if !p.unrecognizedColumns.isEmpty {
                        Text("Ignored columns: \(p.unrecognizedColumns.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
        }
    }

    private func listGroup(_ title: String, _ items: [String]) -> some View {
        DisclosureGroup(title) {
            ForEach(items.prefix(100), id: \.self) { Text($0).font(.caption.monospaced()) }
            if items.count > 100 { Text("and \(items.count - 100) more").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func choose() {
        guard let url = FilePanels.openFile(types: [.commaSeparatedText, .plainText], message: "Choose a subscriber CSV file") else { return }
        do {
            text = try FilePanels.readText(url)
            fileName = url.lastPathComponent
            if options.source.isBlank { options.source = url.deletingPathExtension().lastPathComponent }
            refresh()
        } catch {
            model.showError("Couldn't read \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func refresh() {
        guard !text.isEmpty else { preview = nil; return }
        preview = SubscriberImporter.preview(csv: text, existing: model.workspace.subscribers, options: options)
    }
}

// MARK: - Segments

private struct SegmentsPane: View {
    @EnvironmentObject var model: AppModel
    @State private var editing: Segment?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Segments pick part of your list by tag, source, location or signup date. Only subscribed addresses are ever counted as recipients.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button {
                    editing = Segment(name: "New segment")
                } label: {
                    Label("New Segment", systemImage: "plus")
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            if model.workspace.segments.isEmpty {
                EmptyStateView(title: "No segments", symbol: "line.3.horizontal.decrease.circle",
                               message: "For example: fans in your top city before a show, or everyone who signed up at the merch table.",
                               actionTitle: "New Segment", action: { editing = Segment(name: "New segment") })
            } else {
                List(model.workspace.segments) { segment in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(segment.name).fontWeight(.medium)
                            Text(segment.rules.summary).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(model.workspace.recipients(for: segment.id).count) subscribed").monospacedDigit()
                        Button("Edit") { editing = segment }.controlSize(.small)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .sheet(item: $editing) { segment in
            SegmentEditor(segment: segment).environmentObject(model)
        }
    }
}

extension SegmentRules {
    var summary: String {
        var parts: [String] = []
        if !anyTags.isEmpty { parts.append("tagged \(anyTags.joined(separator: " or "))") }
        if !sources.isEmpty { parts.append("from \(sources.joined(separator: " or "))") }
        if !locationContains.isBlank { parts.append("in “\(locationContains)”") }
        if let signedUpAfter { parts.append("joined on or after \(signedUpAfter.shortDate)") }
        if let signedUpBefore { parts.append("joined on or before \(signedUpBefore.shortDate)") }
        if requireConsentRecord { parts.append("with a consent record") }
        return parts.isEmpty ? "Everyone subscribed" : parts.joined(separator: ", ").capitalizedFirst
    }
}

private struct SegmentEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var segment: Segment

    private var exists: Bool { model.workspace.segments.contains { $0.id == segment.id } }
    private var matching: Int {
        model.workspace.subscribers.filter { $0.status.canReceiveCampaigns && segment.rules.matches($0) }.count
    }
    private var knownTags: [String] {
        Array(Set(model.workspace.subscribers.flatMap(\.tags))).sorted()
    }
    private var knownSources: [String] {
        Array(Set(model.workspace.subscribers.map(\.signupSource).filter { !$0.isBlank })).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $segment.name)
                Section("Who's in it") {
                    TagsField(title: "Has any of these tags", values: $segment.rules.anyTags)
                    if !knownTags.isEmpty {
                        Text("Tags on your list: \(knownTags.prefix(20).joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                    }
                    TagsField(title: "Signed up from", values: $segment.rules.sources)
                    if !knownSources.isEmpty {
                        Text("Sources on your list: \(knownSources.prefix(20).joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("Location contains", text: $segment.rules.locationContains)
                    OptionalDatePicker(title: "Joined on or after", date: $segment.rules.signedUpAfter)
                    OptionalDatePicker(title: "Joined on or before", date: $segment.rules.signedUpBefore)
                    Toggle("Only people with a consent record", isOn: $segment.rules.requireConsentRecord)
                }
                Section {
                    LabeledContent("Subscribed addresses matching", value: "\(matching)")
                }
                TextField("Notes", text: $segment.notes, axis: .vertical)
            }
            .formStyle(.grouped)
            HStack {
                if exists {
                    Button("Delete", role: .destructive) {
                        let s = segment
                        let used = model.workspace.campaigns.contains { $0.segmentID == s.id && ![.sent, .cancelled].contains($0.status) }
                        if used {
                            model.showError("A campaign that hasn't been sent uses this segment. Change its audience first.")
                            return
                        }
                        model.perform("Deleted segment: \(s.name)", showUndo: true) { $0.remove(s.id, from: \.segments) }
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    let s = segment
                    model.perform(exists ? "Updated segment: \(s.name)" : "Created segment: \(s.name)", showUndo: true) { $0.upsert(s, in: \.segments) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(segment.name.isBlank)
            }
            .padding()
        }
        .frame(width: 560, height: 620)
    }
}

// MARK: - Campaigns

private struct CampaignsPane: View {
    @EnvironmentObject var model: AppModel
    @State private var editing: EmailCampaign?
    @State private var markingSent: EmailCampaign?
    @State private var resultsFor: (campaign: EmailCampaign, result: CampaignResultsImport)?

    private var campaigns: [EmailCampaign] {
        model.workspace.campaigns.sorted { ($0.sentAt ?? $0.scheduledFor ?? $0.createdAt) > ($1.sentAt ?? $1.scheduledFor ?? $1.createdAt) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Draft here, approve, then export to your email provider and send from there.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(model.workspace.releases.filter { $0.stage != .archived }) { release in
                        Button("Announce “\(release.title)”") { editing = newCampaign(release: release) }
                    }
                    if !model.workspace.releases.isEmpty { Divider() }
                    Button("Blank Campaign") { editing = newCampaign(release: nil) }
                } label: {
                    Label("New Campaign", systemImage: "square.and.pencil")
                }
                .fixedSize()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            if campaigns.isEmpty {
                EmptyStateView(title: "No campaigns", symbol: "envelope.badge",
                               message: "Start with a release announcement. Every campaign needs your approval before it can be exported for sending.",
                               actionTitle: "New Campaign", action: { editing = newCampaign(release: nil) })
            } else {
                List(campaigns) { campaign in
                    CampaignRow(campaign: campaign,
                                onEdit: { editing = campaign },
                                onMarkSent: { markingSent = campaign },
                                onImportResults: { importResults(for: campaign) })
                }
            }
        }
        .sheet(item: $editing) { campaign in
            CampaignEditor(campaign: campaign).environmentObject(model)
        }
        .sheet(item: $markingSent) { campaign in
            MarkCampaignSentSheet(campaign: campaign).environmentObject(model)
        }
        .sheet(isPresented: Binding(get: { resultsFor != nil }, set: { if !$0 { resultsFor = nil } })) {
            if let pending = resultsFor {
                CampaignResultsSheet(campaign: pending.campaign, result: pending.result) {
                    model.applyCampaignResults(pending.result, to: pending.campaign.id)
                    resultsFor = nil
                } onCancel: {
                    resultsFor = nil
                }
            }
        }
        .onAppear {
            if let focus = model.focusedRecordID {
                if let c = model.workspace.campaigns.first(where: { $0.id == focus }) {
                    editing = c
                } else if let r = model.workspace.release(focus) {
                    editing = newCampaign(release: r)
                }
                model.focusedRecordID = nil
            }
        }
    }

    private func newCampaign(release: Release?) -> EmailCampaign {
        let draft = Drafting.emailAnnouncement(for: release, profile: model.workspace.profile)
        var c = EmailCampaign()
        c.name = release.map { "\($0.title) announcement" } ?? "Newsletter"
        c.subject = draft.subject
        c.preheader = draft.preheader
        c.body = draft.body
        c.releaseID = release?.id
        if let date = release?.releaseDate { c.scheduledFor = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: date) }
        return c
    }

    private func importResults(for campaign: EmailCampaign) {
        guard let url = FilePanels.openFile(types: [.commaSeparatedText, .plainText],
                                            message: "Choose the per-recipient report your email provider exported for this campaign") else { return }
        do {
            let text = try FilePanels.readText(url)
            let result = CampaignResultsImporter.read(csv: text, subscribers: model.workspace.subscribers, fileName: url.lastPathComponent)
            guard result.results.recipients > 0 else {
                model.showError("No email addresses were found in \(url.lastPathComponent).")
                return
            }
            resultsFor = (campaign, result)
        } catch {
            model.showError("Couldn't read \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

private struct CampaignRow: View {
    @EnvironmentObject var model: AppModel
    var campaign: EmailCampaign
    var onEdit: () -> Void
    var onMarkSent: () -> Void
    var onImportResults: () -> Void

    var body: some View {
        let audience = model.workspace.segment(campaign.segmentID)?.name ?? "All subscribed"
        let recipients = model.workspace.recipients(for: campaign.segmentID).count
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "envelope").foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(campaign.subject.isBlank ? "No subject" : campaign.subject).fontWeight(.medium)
                Text([campaign.name, "\(audience) (\(recipients))",
                      campaign.sentAt.map { "sent \($0.shortDate)" } ?? campaign.scheduledFor.map { "planned \($0.shortDateTime)" } ?? ""]
                    .filter { !$0.isBlank }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if let r = campaign.results {
                    Text(resultsText(r)).font(.caption).foregroundStyle(.secondary)
                }
                if campaign.status == .approved || campaign.status == .exported, campaign.approvedRecipientCount > 0,
                   campaign.approvedRecipientCount != recipients {
                    Label("\(recipients) recipients now match; you approved it for \(campaign.approvedRecipientCount).", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            campaign.status.badge
            HStack(spacing: 6) {
                switch campaign.status {
                case .draft:
                    Button("Edit…", action: onEdit)
                case .awaitingApproval:
                    Button("Review") { model.selection = .approvals }
                case .approved, .exported:
                    Button("Export for Provider…") {
                        if let folder = FilePanels.chooseFolder(message: "Choose a folder for the campaign files", prompt: "Export Here") {
                            model.exportCampaign(campaign.id, to: folder)
                        }
                    }
                    Button("Mark Sent…", action: onMarkSent)
                case .sent:
                    Button("Import Results…", action: onImportResults)
                        .help("Read your provider's per-recipient report to record delivery and apply bounces and unsubscribes.")
                case .cancelled:
                    EmptyView()
                }
                Menu {
                    Button(campaign.status == .draft ? "Edit…" : "View or Edit…", action: onEdit)
                    Button("Duplicate as New Draft") { duplicate() }
                    Button("Copy Text") { Clipboard.copy(CampaignExport.plainText(campaign, profile: model.workspace.profile)) }
                    if ![.sent, .cancelled].contains(campaign.status) {
                        Divider()
                        Button("Cancel Campaign") { model.cancelCampaign(campaign.id) }
                    }
                    if campaign.status == .draft || campaign.status == .cancelled {
                        Button("Delete", role: .destructive) {
                            let id = campaign.id
                            model.perform("Deleted email: \(campaign.subject)", showUndo: true) { ws in
                                ws.remove(id, from: \.campaigns)
                                ApprovalService.clearApprovalAfterEdit(subjectID: id, in: &ws)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
                .accessibilityLabel("More actions for \(campaign.subject)")
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private func resultsText(_ r: CampaignResults) -> String {
        func pct(_ n: Int) -> String {
            guard r.delivered > 0 else { return "" }
            return " (\(Int((Double(n) / Double(r.delivered) * 100).rounded()))%)"
        }
        return "\(r.delivered) delivered · \(r.opens) opens\(pct(r.opens)) · \(r.clicks) clicks\(pct(r.clicks)) · \(r.bounces) bounced · \(r.unsubscribes) unsubscribed · \(r.complaints) complaints"
    }

    private func duplicate() {
        var copy = campaign
        copy.id = UUID()
        copy.name = campaign.name.isBlank ? "Copy" : "\(campaign.name) (copy)"
        copy.status = .draft
        copy.createdAt = Date()
        copy.createdBy = .artist
        copy.approvedAt = nil
        copy.approvedRecipientCount = 0
        copy.exportedAt = nil
        copy.sentAt = nil
        copy.results = nil
        let c = copy
        model.perform("Duplicated email: \(c.subject)", kind: .draftMaterials, status: .drafted, showUndo: true) { $0.upsert(c, in: \.campaigns) }
    }
}

private struct CampaignEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var campaign: EmailCampaign

    private var checks: [CampaignCheck] { CampaignLint.check(campaign, workspace: model.workspace) }
    private var stored: EmailCampaign? { model.workspace.campaigns.first { $0.id == campaign.id } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Form {
                    Section("Campaign") {
                        TextField("Internal name", text: $campaign.name)
                        Picker("Audience", selection: $campaign.segmentID) {
                            Text("Everyone subscribed").tag(UUID?.none)
                            ForEach(model.workspace.segments) { Text($0.name).tag(Optional($0.id)) }
                        }
                        ReleasePicker(selection: $campaign.releaseID)
                        OptionalDatePicker(title: "Planned send", date: $campaign.scheduledFor, components: [.date, .hourAndMinute])
                        Text("A planned date goes on your calendar. You send it from your email provider.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Email") {
                        TextField("Subject", text: $campaign.subject)
                        TextField("Preview text", text: $campaign.preheader)
                        TextEditor(text: $campaign.body).frame(minHeight: 240).font(.body).accessibilityLabel("Email body")
                        Button("Redraft From Template") {
                            let draft = Drafting.emailAnnouncement(for: model.workspace.release(campaign.releaseID), profile: model.workspace.profile)
                            campaign.subject = draft.subject
                            campaign.preheader = draft.preheader
                            campaign.body = draft.body
                        }
                    }
                    Section("Footer your provider should keep") {
                        Text(CampaignExport.footer(model.workspace.profile)).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                .formStyle(.grouped)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Checks").font(.headline)
                    ForEach(checks) { check in
                        Label {
                            Text(check.message).font(.callout).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: check.level == .error ? "xmark.octagon" : (check.level == .warning ? "exclamationmark.triangle" : "checkmark.circle"))
                                .foregroundStyle(check.level == .error ? Color.red : (check.level == .warning ? Color.orange : Color.green))
                        }
                        .accessibilityLabel("\(check.level == .error ? "Must fix" : (check.level == .warning ? "Warning" : "OK")): \(check.message)")
                    }
                    Spacer()
                    if let stored, stored.status != .draft {
                        Text("Status: \(stored.status.label)").font(.caption).foregroundStyle(.secondary)
                        Text("Changing the subject, text or audience sends it back for approval.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(width: 260, alignment: .topLeading)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Draft") {
                    model.saveCampaign(campaign, requestApproval: false)
                    dismiss()
                }
                .disabled(campaign.subject.isBlank && campaign.body.isBlank)
                Button("Save and Ask for Approval") {
                    model.saveCampaign(campaign, requestApproval: true)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(CampaignLint.hasErrors(checks))
            }
            .padding()
        }
        .frame(width: 860, height: 720)
    }
}

private struct MarkCampaignSentSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var campaign: EmailCampaign
    @State private var date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Record “\(campaign.subject)” as sent").font(.title3.weight(.semibold))
            Text("Confirm you sent this from your email provider. Manager doesn't send email.").foregroundStyle(.secondary)
            DatePicker("Sent", selection: $date, in: ...Date())
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Record as Sent") {
                    model.markCampaignSent(campaign.id, on: date)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

private struct CampaignResultsSheet: View {
    var campaign: EmailCampaign
    var result: CampaignResultsImport
    var onApply: () -> Void
    var onCancel: () -> Void

    var body: some View {
        let r = result.results
        let byStatus = Dictionary(grouping: result.statusUpdates.values, by: { $0 }).mapValues(\.count)
        VStack(alignment: .leading, spacing: 12) {
            Text("Results for “\(campaign.subject)”").font(.title3.weight(.semibold))
            Text("From \(r.sourceFile)").foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow { Text("Recipients in report"); Text("\(r.recipients)").monospacedDigit() }
                GridRow { Text("Delivered"); Text("\(r.delivered)").monospacedDigit() }
                GridRow { Text("Opens"); Text("\(r.opens)").monospacedDigit() }
                GridRow { Text("Clicks"); Text("\(r.clicks)").monospacedDigit() }
                GridRow { Text("Bounces"); Text("\(r.bounces)").monospacedDigit() }
                GridRow { Text("Unsubscribes"); Text("\(r.unsubscribes)").monospacedDigit() }
                GridRow { Text("Spam complaints"); Text("\(r.complaints)").monospacedDigit() }
            }
            Divider()
            Text("Subscriber changes").font(.headline)
            if byStatus.isEmpty {
                Text("No one will change status.").foregroundStyle(.secondary)
            }
            ForEach(SubscriptionStatus.allCases.filter { byStatus[$0] != nil }) { status in
                Text("\(byStatus[status] ?? 0) will be marked \(status.label.lowercased())")
            }
            Text("Soft bounces are counted but not suppressed. Nobody is re-subscribed by a report.").font(.caption).foregroundStyle(.secondary)
            if result.unknownAddresses > 0 {
                Text("\(result.unknownAddresses) addresses in the report aren't on your list here and are ignored.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Apply Results", action: onApply)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
