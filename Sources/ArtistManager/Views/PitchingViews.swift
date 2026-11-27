import AppKit
import SwiftUI

// MARK: - Spotify editorial pitch

/// The Spotify for Artists pitch form, filled in here, approved, then submitted by the artist in
/// Spotify for Artists (there's no public API for pitching).
struct SpotifyPitchEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var item: Outreach
    @State private var pitch: EditorialPitch
    @State private var confirmDelete = false

    static let moodSuggestions = ["Chill", "Dreamy", "Melancholic", "Romantic", "Upbeat", "Energetic", "Dark", "Empowering",
                                  "Nostalgic", "Peaceful", "Sad", "Happy", "Sensual", "Intense"]
    static let styleSuggestions = ["Acoustic", "Instrumental", "Live", "Cover", "Remix", "Lo-fi", "Experimental", "Orchestral"]

    init(item: Outreach) {
        _item = State(initialValue: item)
        _pitch = State(initialValue: item.editorial ?? EditorialPitch())
    }

    /// A new pitch for a release, filled in from the release and your profile.
    static func newPitch(for release: Release, workspace ws: Workspace) -> Outreach {
        let subscribed = ws.subscribers.filter { $0.status == .subscribed }.count
        let pitch = Drafting.editorialPitch(for: release, profile: ws.profile, subscriberCount: subscribed)
        var item = Outreach(kind: .spotifyEditorial, releaseID: release.id,
                            subject: "Spotify editorial pitch: “\(pitch.trackTitle)”", body: pitch.description)
        item.editorial = pitch
        return item
    }

    private var release: Release? { model.workspace.release(item.releaseID) }
    private var stored: Outreach? { model.workspace.outreach.first { $0.id == item.id } }
    private var issues: [EditorialPitch.Issue] { pitch.issues(releaseDate: release?.releaseDate) }
    private var hasErrors: Bool { issues.contains { $0.level == .error } }

    /// Spotify takes one pitched song at a time, until it's released.
    private var otherPending: Outreach? {
        model.workspace.outreach.first { other in
            guard other.id != item.id, other.kind == .spotifyEditorial, other.status == .sent,
                  let date = model.workspace.release(other.releaseID)?.releaseDate else { return false }
            return date.startOfDay > Date().startOfDay
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                form
                Divider()
                sidePanel
                    .padding()
                    .frame(width: 270, alignment: .topLeading)
            }
            HStack {
                if stored != nil {
                    Button("Delete", role: .destructive) { confirmDelete = true }
                }
                Button("Copy Fields") { Clipboard.copy(pitch.formText) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Draft") { save(requestApproval: false) }
                Button("Save and Ask for Approval") { save(requestApproval: true) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(hasErrors)
            }
            .padding()
        }
        .frame(width: 900, height: 740)
        .confirmationDialog("Delete this pitch?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                model.deleteOutreach(item.id)
                dismiss()
            }
        } message: {
            Text("You can undo this from the activity log.")
        }
    }

    private var form: some View {
        Form {
            Section("Song") {
                ReleasePicker(selection: $item.releaseID)
                if let release, !release.tracks.isEmpty {
                    Picker("Song to pitch", selection: Binding(
                        get: { pitch.trackID },
                        set: { id in
                            pitch.trackID = id
                            pitch.trackTitle = release.tracks.first { $0.id == id }?.title ?? pitch.trackTitle
                        })) {
                        ForEach(release.tracks) { track in
                            Text(track.title.isBlank ? "Untitled track" : track.title).tag(Optional(track.id))
                        }
                    }
                } else {
                    TextField("Song title", text: $pitch.trackTitle)
                }
                Text("Spotify takes one song per release, so pick the strongest one.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Describe the song") {
                TextField("Main genre", text: $pitch.primaryGenre)
                TagsField(title: "Subgenres (up to 3)", values: $pitch.subgenres)
                TagsField(title: "Moods", values: $pitch.moods)
                SuggestionChips(suggestions: Self.moodSuggestions, values: $pitch.moods)
                TagsField(title: "Styles", values: $pitch.styles)
                SuggestionChips(suggestions: Self.styleSuggestions, values: $pitch.styles)
                TagsField(title: "Instruments", values: $pitch.instruments, prompt: "e.g. acoustic guitar, synth, strings")
                TextField("Culture or scene (optional)", text: $pitch.culture)
                TextField("Language", text: $pitch.language)
            }
            Section("Where you're from") {
                TextField("Hometown", text: $pitch.hometown)
                TextField("Where you're based now", text: $pitch.currentLocation)
            }
            Section {
                TextEditor(text: $pitch.description)
                    .frame(minHeight: 130)
                    .font(.body)
                    .accessibilityLabel("Note to Spotify's editors")
                HStack {
                    Button("Redraft From Profile") {
                        let subscribed = model.workspace.subscribers.filter { $0.status == .subscribed }.count
                        let track = release?.tracks.first { $0.id == pitch.trackID }
                        pitch.description = Drafting.editorialDescription(release: release, profile: model.workspace.profile,
                                                                          subscriberCount: subscribed, track: track)
                    }
                    Spacer()
                    Text("\(pitch.description.count) / \(EditorialPitch.maxDescription)")
                        .monospacedDigit()
                        .foregroundStyle(pitch.description.count > EditorialPitch.maxDescription ? Color.red : Color.secondary)
                        .accessibilityLabel("\(pitch.description.count) of \(EditorialPitch.maxDescription) characters")
                }
            } header: {
                Text("Note to the editors")
            } footer: {
                Text("Be specific: what the song is about, how it sounds, who it's for, and what you're doing around the release (press, shows, video, ads).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Your release plan (for your reference)") {
                TextField("Press, shows, video, ads, email…", text: $pitch.marketingNotes, axis: .vertical).lineLimit(2...5)
            }
        }
        .formStyle(.grouped)
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Timing").font(.headline)
            if let date = release?.releaseDate {
                LabeledText(label: "Release day", value: date.shortDate)
                LabeledText(label: "Best by", value: EditorialPitch.recommendedDate(for: date).shortDate)
                LabeledText(label: "Release Radar cutoff", value: EditorialPitch.deadline(for: date).shortDate)
            } else {
                Text("Give the release a date in Releases.").foregroundStyle(.secondary)
            }
            if let other = otherPending {
                Label("Spotify takes one pitch at a time. “\(model.workspace.release(other.releaseID)?.title ?? other.subject)” is still pending until it's released.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Text("Checks").font(.headline)
            if issues.isEmpty {
                Label("Ready for your approval.", systemImage: "checkmark.circle").foregroundStyle(.green)
            }
            ForEach(issues) { issue in
                Label {
                    Text(issue.message).font(.callout).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: issue.level == .error ? "xmark.octagon" : "exclamationmark.triangle")
                        .foregroundStyle(issue.level == .error ? Color.red : Color.orange)
                }
                .accessibilityLabel("\(issue.level == .error ? "Must fix" : "Warning"): \(issue.message)")
            }
            Divider()
            Text("How it works").font(.headline)
            Text("Approve the pitch here, then submit it yourself in Spotify for Artists › Music › Upcoming. Paste each field with Copy Fields. You can still edit it there until release day.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Link("Open Spotify for Artists", destination: EditorialPitch.submitURL).font(.callout)
            Spacer()
        }
    }

    private func save(requestApproval: Bool) {
        var o = item
        o.kind = .spotifyEditorial
        o.editorial = pitch
        o.subject = "Spotify editorial pitch: “\(pitch.trackTitle.isBlank ? (release?.title ?? "Untitled") : pitch.trackTitle)”"
        o.body = pitch.description
        model.saveOutreach(o, requestApproval: requestApproval)
        dismiss()
    }
}

/// Buttons that add or remove common values from a tag list.
struct SuggestionChips: View {
    var suggestions: [String]
    @Binding var values: [String]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(suggestions, id: \.self) { suggestion in
                    let on = values.contains { $0.caseInsensitiveCompare(suggestion) == .orderedSame }
                    Button {
                        if on { values.removeAll { $0.caseInsensitiveCompare(suggestion) == .orderedSame } } else { values.append(suggestion) }
                    } label: {
                        Label(suggestion, systemImage: on ? "checkmark" : "plus")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(on ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(on ? "Remove \(suggestion)" : "Add \(suggestion)")
                }
            }
        }
    }
}

// MARK: - Pitching several contacts at once

/// Drafts one personal note per contact (review requests, curator pitches, press, booking, sync…).
/// Each draft is its own message, and each still needs approval before it can be sent.
struct BatchPitchSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind: OutreachKind
    @State private var releaseID: UUID?
    @State private var showEveryone = false
    @State private var search = ""
    @State private var tag = ""
    @State private var selected = Set<UUID>()
    @State private var askForApproval = true
    @State private var didSetUp = false
    private let presetRelease: UUID?
    /// Contacts to start with selected, e.g. everyone at a target. Shown whatever their role.
    private let presetContacts: [UUID]

    static let kinds: [OutreachKind] = [.review, .press, .playlist, .radio, .label, .booking, .sync, .partnership, .general]

    init(kind: OutreachKind, releaseID: UUID? = nil, contactIDs: [UUID] = []) {
        _kind = State(initialValue: kind)
        presetRelease = releaseID
        presetContacts = contactIDs
    }

    private var release: Release? { model.workspace.release(releaseID) }

    private func alreadyPitched(_ contact: Contact) -> Bool {
        model.workspace.outreach.contains { $0.contactID == contact.id && $0.kind == kind && $0.releaseID == releaseID }
    }

    private var candidates: [Contact] {
        let roles = kind.suggestedRoles
        return model.workspace.contacts
            .filter { showEveryone || roles.isEmpty || roles.contains($0.role) || presetContacts.contains($0.id) }
            .filter { tag.isBlank || $0.tags.contains { $0.localizedCaseInsensitiveContains(tag) } }
            .filter { search.isBlank || $0.displayName.localizedCaseInsensitiveContains(search) || $0.organization.localizedCaseInsensitiveContains(search) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var reachable: [Contact] { candidates.filter { !$0.email.isBlank && !alreadyPitched($0) } }
    private var chosen: [Contact] { model.workspace.contacts.filter { selected.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pitch several contacts").font(.title2.weight(.semibold))
            Text("Manager drafts a separate, personal note to each person. Nothing goes out until you approve each one and send it from your mail app.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Picker("Type", selection: $kind) {
                    ForEach(Self.kinds) { Text($0.label).tag($0) }
                }
                .frame(maxWidth: 280)
                ReleasePicker(selection: $releaseID)
                    .frame(maxWidth: 300)
            }
            HStack {
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                TextField("Tag", text: $tag).textFieldStyle(.roundedBorder).frame(maxWidth: 140)
                if !kind.suggestedRoles.isEmpty {
                    Toggle("Show all contacts", isOn: $showEveryone)
                }
                Spacer()
                Button("Select All") { selected.formUnion(reachable.map(\.id)) }.disabled(reachable.isEmpty)
                Button("Select None") { selected.removeAll() }.disabled(selected.isEmpty)
            }
            if candidates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(kind.suggestedRoles.isEmpty ? "No contacts match." : "No contacts with the role \(kind.suggestedRoles.map(\.label).joined(separator: " or ")) yet.")
                    Text("Import a media or curator list in Contacts, or turn on Show all contacts.").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
            } else {
                List(candidates) { contact in
                    let pitched = alreadyPitched(contact)
                    let noEmail = contact.email.isBlank
                    Toggle(isOn: Binding(
                        get: { selected.contains(contact.id) },
                        set: { on in if on { selected.insert(contact.id) } else { selected.remove(contact.id) } })) {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(contact.displayName)
                                Text([contact.role.label, contact.organization, contact.email].filter { !$0.isBlank }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if pitched { StatusBadge(text: "Already pitched", tone: .neutral, symbol: "checkmark") }
                            if noEmail { StatusBadge(text: "No email", tone: .warning, symbol: "envelope.badge") }
                        }
                    }
                    .disabled(pitched || noEmail)
                }
                .frame(minHeight: 220)
            }
            if let first = chosen.first {
                let preview = Drafting.pitch(kind: kind, contact: first, release: release,
                                             profile: model.workspace.profile, pressKit: model.workspace.pressKit)
                GroupBox("Preview for \(first.displayName)") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preview.subject).fontWeight(.medium)
                        Text(preview.body).font(.callout).foregroundStyle(.secondary).lineLimit(6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Toggle("Ask for my approval for all of them now", isOn: $askForApproval)
            Text("You can edit any draft before approving it. Approve them one by one or all together in Approvals.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(selected.isEmpty ? "Draft Pitches" : "Draft \(selected.count) Pitch\(selected.count == 1 ? "" : "es")") { create() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 760, height: 760)
        .onAppear {
            guard !didSetUp else { return }
            didSetUp = true
            releaseID = presetRelease ?? model.workspace.releases
                .filter { $0.stage.isActive && ($0.releaseDate ?? .distantPast) >= Date().startOfDay }
                .sorted { ($0.releaseDate ?? .distantFuture) < ($1.releaseDate ?? .distantFuture) }
                .first?.id
            let ready = Set(reachable.map(\.id))
            selected = Set(presetContacts.filter(ready.contains))
        }
        .onChange(of: kind) { _, _ in selected.removeAll() }
    }

    private func create() {
        let result = Drafting.batch(kind: kind, contacts: chosen.filter { !$0.email.isBlank }, release: release,
                                    existing: model.workspace.outreach, profile: model.workspace.profile, pressKit: model.workspace.pressKit)
        model.createPitchBatch(result.drafts, kind: kind, askForApproval: askForApproval)
        if !result.skipped.isEmpty {
            model.showInfo("Skipped \(result.skipped.count) contact\(result.skipped.count == 1 ? "" : "s") already pitched for this release.")
        }
        dismiss()
    }
}
