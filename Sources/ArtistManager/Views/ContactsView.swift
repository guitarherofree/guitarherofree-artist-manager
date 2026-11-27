import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Two pages share this view: Team (the people you work with) and Contacts (everyone else).
struct ContactsView: View {
    enum Audience { case team, contacts }

    @EnvironmentObject var model: AppModel
    var audience: Audience = .contacts
    @State private var selectedID: UUID?
    @State private var search = ""
    @State private var scope: Scope = .all
    @State private var editing: Contact?
    @State private var importing: ImportSource?

    enum ImportSource: String, Identifiable {
        case contactsApp, vCard, csv
        var id: String { rawValue }
    }

    enum Scope: String, CaseIterable, Identifiable {
        case all, checkIn, industry, media, live, followUp
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "Everyone"
            case .checkIn: return "Check-in due"
            case .industry: return "Industry"
            case .media: return "Press & curators"
            case .live: return "Live & booking"
            case .followUp: return "Follow-up due"
            }
        }
        static func options(for audience: Audience) -> [Scope] {
            audience == .team ? [.all, .checkIn, .followUp] : [.all, .industry, .media, .live, .followUp]
        }
        func includes(_ c: Contact, checkInDays: Int, now: Date = Date()) -> Bool {
            switch self {
            case .all: return true
            case .checkIn: return c.lastContacted.map { Date.daysBetween($0, now.startOfDay) > checkInDays } ?? true
            case .industry: return c.role.isIndustry && !c.role.isMedia
            case .media: return c.role.isMedia
            case .live: return [.bookingAgent, .promoter, .venue].contains(c.role)
            case .followUp: return (c.nextFollowUp ?? .distantFuture) <= now.startOfDay.adding(days: 7)
            }
        }
    }

    private var isTeam: Bool { audience == .team }

    /// Everyone on this page, before search and filters.
    private var people: [Contact] {
        model.workspace.contacts.filter { $0.isTeamMember == isTeam }
    }

    private var contacts: [Contact] {
        people
            .filter { scope.includes($0, checkInDays: model.workspace.settings.teamCheckInDays) }
            .filter { c in
                search.isBlank || c.displayName.localizedCaseInsensitiveContains(search) || c.organization.localizedCaseInsensitiveContains(search)
                    || c.email.localizedCaseInsensitiveContains(search) || c.tags.contains { $0.localizedCaseInsensitiveContains(search) }
                    || c.role.label.localizedCaseInsensitiveContains(search)
            }
            .sorted { a, b in
                if scope == .followUp { return (a.nextFollowUp ?? .distantFuture) < (b.nextFollowUp ?? .distantFuture) }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(isTeam ? "Team" : "Contacts").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button {
                            editing = newPerson()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .help(isTeam ? "Add a team member" : "New contact")
                        .accessibilityLabel(isTeam ? "Add a team member" : "New contact")
                    }
                    HStack {
                        if !isTeam { importMenu }
                        Button("Export CSV…") {
                            model.exportText(ContactCSV.export(people), suggestedName: isTeam ? "Team.csv" : "Contacts.csv",
                                             types: [.commaSeparatedText], logTitle: isTeam ? "Exported team" : "Exported contacts")
                        }
                        .disabled(people.isEmpty)
                    }
                    .controlSize(.small)
                    TextField("Search", text: $search).textFieldStyle(.roundedBorder)
                    Picker("Show", selection: $scope) {
                        ForEach(Scope.options(for: audience)) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                }
                .padding()
                List(selection: $selectedID) {
                    ForEach(contacts) { contact in
                        ContactListRow(contact: contact).tag(contact.id)
                    }
                }
            }
            .frame(width: 280)
            Divider()
            if let id = selectedID, let contact = people.first(where: { $0.id == id }) {
                ContactDetail(contact: contact, onEdit: { editing = contact })
                    .id(contact.id)
            } else if people.isEmpty && isTeam {
                ContentUnavailableView {
                    Label("No team yet", systemImage: "person.3")
                } description: {
                    Text("Add the people you work with — manager, booking agent, attorney, accountant, publicist, producer — with what each one handles. Manager reminds you to check in with them. Someone already in Contacts can be moved here by turning on “Part of my team”.")
                } actions: {
                    Button("Add Team Member") { editing = newPerson() }.buttonStyle(.borderedProminent)
                    Button("Open Contacts") { model.open(.contacts) }
                }
            } else if people.isEmpty {
                ContentUnavailableView {
                    Label("No contacts yet", systemImage: "person.crop.rectangle.stack")
                } description: {
                    Text("Add industry contacts — writers, curators, promoters, venues, labels, music supervisors — or bring them in from the Contacts app, a vCard or a CSV. Your own team lives on the Team page.")
                } actions: {
                    Button("Import from Contacts App…") { importing = .contactsApp }.buttonStyle(.borderedProminent)
                    Button("Add Contact") { editing = newPerson() }
                }
            } else {
                EmptyStateView(title: isTeam ? "Choose a team member" : "Choose a contact", symbol: "person.crop.circle",
                               message: "Select someone on the left.")
            }
        }
        .sheet(item: $editing) { contact in
            ContactEditor(contact: contact) { saved in
                // Turning “Part of my team” on or off moves the person to the other page; follow them there.
                if let person = model.workspace.contact(saved), person.isTeamMember != isTeam {
                    model.open(person.isTeamMember ? .team : .contacts, record: saved)
                } else {
                    selectedID = saved
                }
            }
            .environmentObject(model)
        }
        .sheet(item: $importing) { source in
            switch source {
            case .contactsApp: ContactsAppImportSheet().environmentObject(model)
            case .vCard: ContactImportSheet(title: "Import a vCard File", vCard: true).environmentObject(model)
            case .csv: ContactImportSheet(title: "Import a CSV File").environmentObject(model)
            }
        }
        .onAppear {
            if let focus = model.focusedRecordID, people.contains(where: { $0.id == focus }) {
                selectedID = focus
                model.focusedRecordID = nil
            } else if selectedID == nil {
                selectedID = contacts.first?.id
            }
        }
    }

    private func newPerson() -> Contact {
        var c = Contact()
        c.isTeamMember = isTeam
        return c
    }
}

extension ContactsView {
    fileprivate var importMenu: some View {
        Menu {
            Button("From the Contacts App…") { importing = .contactsApp }
            Button("From a vCard File (.vcf)…") { importing = .vCard }
            Button("From a CSV File…") { importing = .csv }
        } label: {
            Label("Import", systemImage: "square.and.arrow.down")
        }
        .fixedSize()
    }
}

// MARK: - Importing from the Contacts app

private struct ContactsAppImportSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    enum Phase: Equatable { case start, loading, loaded, denied, unavailable, failed(String) }
    @State private var phase: Phase = .start
    @State private var people: [Contact] = []
    @State private var selected = Set<UUID>()
    @State private var search = ""
    @State private var role: ContactRole = .other
    @State private var tags: [String] = ["From Contacts"]
    @State private var markAsTeam = false

    private var shown: [Contact] {
        people.filter { p in
            search.isBlank || p.displayName.localizedCaseInsensitiveContains(search) || p.organization.localizedCaseInsensitiveContains(search)
                || p.email.localizedCaseInsensitiveContains(search) || p.notes.localizedCaseInsensitiveContains(search)
        }
    }

    private var preview: ContactImportPreview {
        let chosen = people.filter { selected.contains($0.id) }
        return ContactImport.merge(chosen.map { (label: $0.displayName, contact: $0) }, existing: model.workspace.contacts,
                                   tagsToAdd: tags, markAsTeam: markAsTeam, defaultRole: role)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import from the Contacts app").font(.title2.weight(.semibold))
            Text("Pick the people to bring in. Manager only reads Contacts — it never changes anything there — and existing contacts here are only filled in, never overwritten.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            content
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(importTitle) {
                    model.importContacts(preview, fileName: "the Contacts app")
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(phase != .loaded || !preview.hasChanges)
            }
        }
        .padding(20)
        .frame(width: 680, height: 720)
    }

    private var importTitle: String {
        guard phase == .loaded, !selected.isEmpty else { return "Import" }
        return "Import \(selected.count) Contact\(selected.count == 1 ? "" : "s")"
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .start:
            VStack(alignment: .leading, spacing: 10) {
                Text("macOS will ask whether Manager can read your contacts.")
                Button("Allow Access and Show Contacts") { Task { await load() } }.buttonStyle(.borderedProminent)
            }
            Spacer()
        case .loading:
            ProgressView("Reading your contacts…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .denied:
            VStack(alignment: .leading, spacing: 10) {
                Label("Manager doesn't have access to Contacts.", systemImage: "lock")
                Text("Turn it on in System Settings › Privacy & Security › Contacts, then try again. Or export a vCard from Contacts (File › Export › Export vCard…) and import that instead.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Try Again") { Task { await load() } }
                }
            }
            Spacer()
        case .unavailable:
            Text("Reading the Contacts app works in the packaged app (build it with Scripts/build.sh). In the meantime, export a vCard from Contacts (File › Export › Export vCard…) and use Import › From a vCard File.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
        case .failed(let message):
            Label("Couldn't read your contacts: \(message)", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            Spacer()
        case .loaded:
            HStack {
                TextField("Search name, company, email or title", text: $search).textFieldStyle(.roundedBorder)
                Button("Select All Shown") { selected.formUnion(shown.map(\.id)) }
                Button("Select None") { selected.removeAll() }.disabled(selected.isEmpty)
            }
            List(shown) { person in
                Toggle(isOn: Binding(
                    get: { selected.contains(person.id) },
                    set: { on in if on { selected.insert(person.id) } else { selected.remove(person.id) } })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(person.displayName)
                        Text([person.organization, person.email, person.notes.replacingOccurrences(of: "Title: ", with: "")]
                            .filter { !$0.isBlank }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minHeight: 260)
            Form {
                Picker("Role when their job title doesn't say", selection: $role) {
                    ForEach(ContactRole.allCases) { Text($0.label).tag($0) }
                }
                TagsField(title: "Add tags", values: $tags)
                Toggle("Mark them as part of my team", isOn: $markAsTeam)
            }
            .formStyle(.grouped)
            .frame(height: 150)
            if !selected.isEmpty {
                Text("\(preview.added.count) new, \(preview.updated.count) existing filled in\(preview.skipped.isEmpty ? "" : ", \(preview.skipped.count) skipped")")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        if ContactsAccess.status == .unavailable { phase = .unavailable; return }
        let granted = await ContactsAccess.requestAccess()
        guard granted else { phase = .denied; return }
        phase = .loading
        do {
            people = try await ContactsAccess.fetchAll()
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

private struct ContactListRow: View {
    var contact: Contact

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(contact.displayName).fontWeight(.medium)
                if contact.isTeamMember {
                    Image(systemName: "star.fill").imageScale(.small).foregroundStyle(.yellow)
                        .accessibilityLabel("On your team")
                }
            }
            Text([contact.role.label, contact.organization].filter { !$0.isBlank }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            if let due = contact.nextFollowUp {
                Text("Follow up \(due.relativeDayText.lowercased())").font(.caption)
                    .foregroundStyle(due.startOfDay <= Date().startOfDay ? Color.orange : Color.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail

private struct ContactDetail: View {
    @EnvironmentObject var model: AppModel
    var contact: Contact
    var onEdit: () -> Void
    @State private var loggingInteraction = false
    @State private var prepText: String?
    @State private var prepPurpose = ""
    @State private var showPrepPrompt = false
    @State private var newOutreach: Outreach?

    private var openTasks: [TaskItem] {
        model.workspace.tasks.filter { $0.contactID == contact.id && $0.isOpen }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        detailsCard
                        followUpCard
                    }
                    VStack(spacing: 16) {
                        historyCard
                        if !openTasks.isEmpty { tasksCard }
                    }
                }
                Card("Messages and pitches", symbol: "paperplane") {
                    OutreachListView(contactID: contact.id)
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $loggingInteraction) {
            InteractionSheet(contact: contact).environmentObject(model)
        }
        .sheet(isPresented: Binding(get: { prepText != nil }, set: { if !$0 { prepText = nil } })) {
            TextDocumentSheet(title: "Conversation prep: \(contact.displayName)",
                              note: "Built from what Manager knows about this contact. Fill in the brackets before you talk.",
                              fileName: "Prep — \(model.safeFileName(contact.displayName)).txt", text: prepText ?? "")
                .environmentObject(model)
        }
        .sheet(item: $newOutreach) { item in
            OutreachEditor(item: item).environmentObject(model)
        }
        .alert("What's the conversation about?", isPresented: $showPrepPrompt) {
            TextField("e.g. renegotiating the booking fee", text: $prepPurpose)
            Button("Build Prep") {
                prepText = ConversationPrep.outline(for: contact, purpose: prepPurpose, workspace: model.workspace)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Manager will pull in your history with \(contact.displayName).")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(contact.displayName).font(.largeTitle.weight(.semibold))
                HStack(spacing: 8) {
                    Text([contact.role.label, contact.organization].filter { !$0.isBlank }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                    if contact.isTeamMember { StatusBadge(text: "On your team", tone: .info, symbol: "star") }
                }
            }
            Spacer()
            Menu {
                ForEach(suggestedKinds, id: \.self) { kind in
                    Button(kind.label) {
                        newOutreach = OutreachEditor.newDraft(kind: kind, contactID: contact.id, workspace: model.workspace)
                    }
                }
            } label: {
                Label("Draft Message", systemImage: "square.and.pencil")
            }
            .fixedSize()
            Button("Prepare for a Conversation…") {
                prepPurpose = contact.followUpReason
                showPrepPrompt = true
            }
            Button("Edit", action: onEdit)
        }
    }

    private var suggestedKinds: [OutreachKind] {
        switch contact.role {
        case .journalist: return [.review, .press, .general]
        case .playlistCurator: return [.playlist, .general]
        case .radio: return [.radio, .general]
        case .venue, .promoter, .bookingAgent: return [.booking, .general]
        case .musicSupervisor, .syncAgent: return [.sync, .general]
        case .brand: return [.partnership, .general]
        default: return [.general, .review, .press, .booking, .sync, .partnership]
        }
    }

    private var detailsCard: some View {
        Card("Details", symbol: "person.text.rectangle") {
            LabeledText(label: "Email", value: contact.email)
            LabeledText(label: "Phone", value: contact.phone)
            LabeledText(label: "Website", value: contact.website)
            LabeledText(label: "Location", value: contact.location)
            if contact.isTeamMember || !contact.responsibilities.isBlank {
                LabeledText(label: "Handles", value: contact.responsibilities)
            }
            if !contact.tags.isEmpty { ChipList(items: contact.tags) }
            if !contact.notes.isBlank {
                Text(contact.notes).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    private var followUpCard: some View {
        Card("Follow-up", symbol: "arrowshape.turn.up.right") {
            if let due = contact.nextFollowUp {
                Text("\(due.relativeDayText): \(contact.followUpReason.isBlank ? "follow up" : contact.followUpReason)")
                    .foregroundStyle(due.startOfDay <= Date().startOfDay ? Color.orange : Color.primary)
            } else {
                Text("No follow-up set.").foregroundStyle(.secondary)
            }
            HStack {
                Button("In 1 Week") { setFollowUp(days: 7) }
                Button("In 2 Weeks") { setFollowUp(days: 14) }
                Button("In 1 Month") { setFollowUp(days: 30) }
                if contact.nextFollowUp != nil {
                    Button("Clear") { setFollowUp(days: nil) }
                }
            }
            .controlSize(.small)
            Text("A dated follow-up becomes a task the week it's due (following your task permission).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var historyCard: some View {
        let interactions = contact.interactions.sorted { $0.date > $1.date }
        return Card("Conversation history", symbol: "text.bubble") {
            if interactions.isEmpty {
                Text("Nothing logged yet. Log calls, meetings and emails so you always know where things stand.")
                    .foregroundStyle(.secondary)
            }
            ForEach(interactions.prefix(8)) { interaction in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(interaction.date.shortDate) · \(interaction.channel.label)").font(.caption).foregroundStyle(.secondary)
                    Text(interaction.summary).textSelection(.enabled)
                }
            }
            if interactions.count > 8 {
                Text("and \(interactions.count - 8) earlier").font(.caption).foregroundStyle(.secondary)
            }
            Button {
                loggingInteraction = true
            } label: {
                Label("Log a Conversation", systemImage: "plus")
            }
        }
    }

    private var tasksCard: some View {
        Card("Open tasks", symbol: "checklist") {
            ForEach(openTasks) { task in TaskRow(task: task) }
        }
    }

    private func setFollowUp(days: Int?) {
        let id = contact.id
        let date = days.map { Date().startOfDay.adding(days: $0) }
        model.perform(date == nil ? "Cleared follow-up for \(contact.displayName)" : "Set follow-up with \(contact.displayName) for \(date!.shortDate)",
                      showUndo: true) { ws in
            if let i = ws.contacts.firstIndex(where: { $0.id == id }) { ws.contacts[i].nextFollowUp = date }
        }
    }
}

// MARK: - Logging a conversation

private struct InteractionSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var contact: Contact
    @State private var interaction = Interaction(channel: .call)
    @State private var followUp: Date?
    @State private var followUpReason = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                DatePicker("When", selection: $interaction.date, in: ...Date().adding(days: 1))
                Picker("How", selection: $interaction.channel) {
                    ForEach(InteractionChannel.allCases) { Text($0.label).tag($0) }
                }
                TextField("What was discussed or agreed", text: $interaction.summary, axis: .vertical).lineLimit(3...8)
                Section("Next step") {
                    OptionalDatePicker(title: "Follow up on", date: $followUp)
                    if followUp != nil {
                        TextField("About", text: $followUpReason)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Log It") {
                    let id = contact.id
                    let entry = interaction
                    let next = followUp
                    let reason = followUpReason
                    model.perform("Logged \(entry.channel.label.lowercased()) with \(contact.displayName)", showUndo: true) { ws in
                        guard let i = ws.contacts.firstIndex(where: { $0.id == id }) else { return }
                        ws.contacts[i].interactions.append(entry)
                        if let next {
                            ws.contacts[i].nextFollowUp = next
                            ws.contacts[i].followUpReason = reason
                        }
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(interaction.summary.isBlank)
            }
            .padding()
        }
        .frame(width: 500, height: 440)
        .onAppear {
            followUp = contact.nextFollowUp
            followUpReason = contact.followUpReason
        }
    }
}

// MARK: - Editing a contact

struct ContactEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var contact: Contact
    var onSaved: (UUID) -> Void
    @State private var confirmDelete = false

    private var exists: Bool { model.workspace.contacts.contains { $0.id == contact.id } }
    private var emailProblem: String? {
        let email = EmailAddress.normalize(contact.email)
        guard !email.isEmpty else { return nil }
        if !EmailAddress.isValid(email) { return "That doesn't look like an email address." }
        if model.workspace.contacts.contains(where: { $0.id != contact.id && EmailAddress.normalize($0.email) == email }) {
            return "Another contact already has this email."
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Who") {
                    TextField("Name", text: $contact.name)
                    TextField("Company, outlet, venue or playlist", text: $contact.organization)
                    Picker("Role", selection: $contact.role) {
                        ForEach(ContactRole.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Part of my team", isOn: $contact.isTeamMember)
                    if contact.isTeamMember {
                        TextField("What they handle for you", text: $contact.responsibilities)
                    }
                }
                Section("Reach them") {
                    TextField("Email", text: $contact.email)
                    if let emailProblem { Text(emailProblem).font(.caption).foregroundStyle(.orange) }
                    TextField("Phone", text: $contact.phone)
                    TextField("Website", text: $contact.website)
                    TextField("Location", text: $contact.location)
                }
                Section("Organize") {
                    TagsField(title: "Tags", values: $contact.tags)
                    OptionalDatePicker(title: "Follow up on", date: $contact.nextFollowUp)
                    if contact.nextFollowUp != nil {
                        TextField("Follow-up about", text: $contact.followUpReason)
                    }
                    TextField("Notes", text: $contact.notes, axis: .vertical).lineLimit(3...8)
                }
            }
            .formStyle(.grouped)
            HStack {
                if exists {
                    Button("Delete", role: .destructive) { confirmDelete = true }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    var c = contact
                    c.email = c.email.isBlank ? "" : EmailAddress.normalize(c.email)
                    let saved = c
                    model.perform(exists ? "Updated contact: \(saved.displayName)" : "Added contact: \(saved.displayName)", showUndo: true) { ws in
                        ws.upsert(saved, in: \.contacts)
                    }
                    onSaved(saved.id)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled((contact.name.isBlank && contact.organization.isBlank) || (emailProblem?.hasPrefix("That") ?? false))
            }
            .padding()
        }
        .frame(width: 540, height: 640)
        .confirmationDialog("Delete \(contact.displayName)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                let c = contact
                model.perform("Deleted contact: \(c.displayName)", showUndo: true) { $0.remove(c.id, from: \.contacts) }
                dismiss()
            }
        } message: {
            Text("Messages, tasks and events that mention them stay, unlinked. You can undo this from the activity log.")
        }
    }
}
