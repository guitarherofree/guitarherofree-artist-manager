import AppKit
import SwiftUI

/// Who looks after the music if the artist can't, where everything is, and what they want done with it.
struct LegacyView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft = LegacyPlan()
    @State private var loaded = false
    @State private var section: LegacySection = .overview

    private var hasChanges: Bool { loaded && draft != model.workspace.legacy }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader("Legacy", subtitle: "Who would look after your music if you couldn't, where everything is, and what you want done with it.") {
                HStack {
                    Button("Revert") { draft = model.workspace.legacy }.disabled(!hasChanges)
                    Button("Save Changes") { save() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(!hasChanges)
                }
            }
            .padding([.horizontal, .top], 24)
            SectionPicker(options: LegacySection.allCases, selection: $section, label: \.label)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            Group {
                switch section {
                case .overview: LegacyOverview(draft: $draft, hasChanges: hasChanges, go: { section = $0 }, save: save)
                case .people: LegacyPeopleForm(plan: $draft)
                case .documents: LegacyDocumentsForm(plan: $draft)
                case .accounts: LegacyAccountsForm(plan: $draft)
                case .archive: LegacyArchiveForm(plan: $draft)
                case .wishes: LegacyWishesForm(wishes: $draft.wishes)
                }
            }
            .formStyle(.grouped)
        }
        .onAppear {
            if !loaded { draft = model.workspace.legacy; loaded = true }
        }
        .onChange(of: model.workspace.legacy) { _, newValue in
            // An undo or restore changed the plan; show it unless there are edits in progress.
            if !hasChanges { draft = newValue }
        }
        .onDisappear {
            if hasChanges { save() }
        }
    }

    private func save() {
        model.saveLegacyPlan(draft)
    }
}

// MARK: - Overview

private struct LegacyOverview: View {
    @EnvironmentObject var model: AppModel
    @Binding var draft: LegacyPlan
    var hasChanges: Bool
    var go: (LegacySection) -> Void
    var save: () -> Void

    var body: some View {
        var ws = model.workspace
        ws.legacy = draft
        let checks = LegacyReadiness.checks(for: ws)
        let done = checks.filter(\.done).count
        let released = LegacyReadiness.releasedReleases(ws)
        let tracks = released.flatMap(\.tracks).filter { !$0.title.isBlank }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card("How ready it is", symbol: "checklist") {
                    ProgressView(value: LegacyReadiness.score(checks)) {
                        Text("\(done) of \(checks.count) done")
                    }
                    ForEach(checks) { check in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: check.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(check.done ? Color.green : Color.secondary)
                                .accessibilityLabel(check.done ? "Done" : "Not done")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.title).fontWeight(.medium)
                                Text(check.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if !check.done {
                                Button("Go") {
                                    if let destination = check.destination {
                                        model.open(destination)
                                    } else if check.id == "reviewed" {
                                        markReviewed()
                                    } else {
                                        go(check.section)
                                    }
                                }
                                .controlSize(.small)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Card("Your catalog at a glance", symbol: "opticaldisc") {
                    if released.isEmpty {
                        Text("Nothing released yet. Released music in Releases shows up here and in the letter.").foregroundStyle(.secondary)
                    } else {
                        LabeledText(label: "Released", value: "\(released.count) release\(released.count == 1 ? "" : "s"), \(tracks.count) song\(tracks.count == 1 ? "" : "s")")
                        LabeledText(label: "Missing ISRC", value: count(tracks.filter { $0.isrc.isBlank }.count))
                        LabeledText(label: "Missing ISWC", value: count(tracks.filter { $0.iswc.isBlank }.count))
                        LabeledText(label: "Splits not at 100%", value: count(tracks.filter { abs($0.splitTotal - 100) > 0.01 }.count))
                        Text("These codes and splits are how royalties find whoever inherits your music.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Open Releases") { model.open(.releases) }.controlSize(.small)
                    }
                }

                Card("The letter", symbol: "envelope.open") {
                    Text("A summary for your executor or attorney: the people, documents and where they are, your releases with their codes and splits, where royalties are collected, your accounts and where each sign-in is kept, where your recordings are, and your wishes. It never includes passwords.")
                        .fixedSize(horizontal: false, vertical: true)
                    if hasChanges {
                        Label("Save your changes first so the letter includes them.", systemImage: "info.circle").foregroundStyle(.orange).font(.callout)
                    }
                    HStack {
                        Button("Preview and Print…") { model.previewLegacyLetter() }
                        Button("Export as Web Page…") { model.exportLegacyLetter(markdown: false) }
                        Button("Export as Text…") { model.exportLegacyLetter(markdown: true) }
                    }
                    .disabled(hasChanges)
                }

                Card("Review", symbol: "calendar.badge.clock") {
                    LabeledText(label: "Last reviewed", value: draft.lastReviewed?.shortDate ?? "Not yet")
                    Stepper("Remind me every \(draft.reviewEveryMonths) month\(draft.reviewEveryMonths == 1 ? "" : "s")",
                            value: $draft.reviewEveryMonths, in: 3...36, step: 3)
                    Button("Mark Reviewed Today") { markReviewed() }
                }

                Card("Good to know", symbol: "info.circle") {
                    VStack(alignment: .leading, spacing: 8) {
                        fact("In the US, copyright in songs and recordings you own generally lasts for your lifetime plus 70 years, so your catalog can keep earning for a long time.")
                        fact("Royalties go to whoever your will or trust names for them. If nothing names them, they pass with the rest of your estate — or by your state's default rules if there's no will.")
                        fact("US termination rights — the right to take back rights you signed away, 35 years after the deal — pass by law to your spouse, children or grandchildren, whatever your will says.")
                        fact("Some services have their own settings for this: Apple's Legacy Contact, Google's Inactive Account Manager, and DistroKid's Leave a Legacy, which keeps a release in stores if the membership stops being paid.")
                        fact("Rights in your name, image and voice after death depend on where you live.")
                        Text("This page organizes things; it isn't legal advice. An estate attorney can turn it into a will or trust that counts, and tell you how the rules apply where you live.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    private func count(_ n: Int) -> String { n == 0 ? "None" : "\(n)" }

    private func fact(_ text: String) -> some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "circle.fill").font(.system(size: 5)) }
    }

    private func markReviewed() {
        draft.lastReviewed = Date()
        save()
    }
}

// MARK: - People

private struct LegacyPeopleForm: View {
    @Binding var plan: LegacyPlan

    var body: some View {
        Form {
            Section {
                ContactPicker(title: "Looks after my music", selection: $plan.executorID)
                ContactPicker(title: "If they can't", selection: $plan.backupExecutorID)
            } header: {
                Text("Your music executor")
            } footer: {
                Text("Someone who would handle releases, licensing requests and royalties — sometimes called a music or creative executor. They can be different from the executor of the rest of your estate. Name them in your will or trust too: choosing them here doesn't make it official. Add people in Team or Contacts first.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Advisers") {
                ContactPicker(title: "Attorney", selection: $plan.attorneyID, roles: [.attorney])
                ContactPicker(title: "Accountant", selection: $plan.accountantID, roles: [.accountant, .businessManager])
            }
            Section {
                TextField("Who has this plan", text: $plan.whoKnows,
                          prompt: Text("e.g. My sister has a printed copy; my attorney has the letter with my will"), axis: .vertical)
                    .lineLimit(1...3)
            } footer: {
                Text("A plan only helps if someone knows it exists. Export the letter from the Overview and give it to them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Documents

private struct LegacyDocumentsForm: View {
    @Binding var plan: LegacyPlan

    var body: some View {
        Form {
            Section {
                Text("Note what you have and where to find it. Keep the documents themselves somewhere safe — Manager only stores where they are.")
                    .foregroundStyle(.secondary)
            }
            ForEach($plan.documents) { $doc in
                Section {
                    if doc.kind == .other {
                        TextField("Document", text: $doc.title)
                    }
                    Picker("Status", selection: $doc.status) {
                        ForEach(LegacyDocumentStatus.allCases) { Text($0.label).tag($0) }
                    }
                    TextField("Where it is", text: $doc.location, prompt: Text("e.g. Fireproof box at home; attorney's office; Dropbox › Legal"))
                    OptionalDatePicker(title: "Last reviewed", date: $doc.lastReviewed)
                    TextField("Notes", text: $doc.notes, axis: .vertical).lineLimit(1...3)
                    Button("Remove", role: .destructive) { plan.documents.removeAll { $0.id == doc.id } }
                        .controlSize(.small)
                } header: {
                    Text(doc.displayTitle)
                } footer: {
                    if !doc.kind.explanation.isEmpty {
                        Text(doc.kind.explanation).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Menu("Add a Document") {
                    ForEach(LegacyDocumentKind.allCases.filter { kind in kind == .other || !plan.documents.contains { $0.kind == kind } }) { kind in
                        Button(kind.label) { plan.documents.append(LegacyDocument(kind: kind)) }
                    }
                }
                .fixedSize()
            }
        }
    }
}

// MARK: - Accounts

private struct LegacyAccountsForm: View {
    @EnvironmentObject var model: AppModel
    @Binding var plan: LegacyPlan

    private var suggestions: [AccountSuggestion] {
        var ws = model.workspace
        ws.legacy = plan
        return LegacyAccounts.suggestions(for: ws)
    }

    var body: some View {
        Form {
            Section {
                Label("Don't type passwords here. Write where each one is kept — for example a password manager. Its emergency-access feature, or a service's own legacy contact setting, is the safer way to pass sign-ins on.",
                      systemImage: "lock.shield")
                    .fixedSize(horizontal: false, vertical: true)
                if !suggestions.isEmpty {
                    HStack {
                        Text("Suggested: " + suggestions.prefix(6).map(\.service).joined(separator: ", ") + (suggestions.count > 6 ? "…" : ""))
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Add \(suggestions.count) Suggested") {
                            plan.accounts.append(contentsOf: suggestions.map { s in
                                LegacyAccount(service: s.service, controls: s.controls, notes: s.legacyHint)
                            })
                        }
                    }
                }
            }
            ForEach($plan.accounts) { $account in
                Section(account.service.isBlank ? "Account" : account.service) {
                    TextField("Service", text: $account.service)
                    TextField("What it controls", text: $account.controls)
                    TextField("Where the sign-in is kept", text: $account.accessKeptAt, prompt: Text("e.g. 1Password › Music vault"))
                    Picker("Legacy contact", selection: $account.legacyOption) {
                        ForEach(AccountLegacyOption.allCases) { Text($0.label).tag($0) }
                    }
                    TextField("Notes", text: $account.notes, axis: .vertical).lineLimit(1...4)
                    if LegacyAccounts.looksLikeSecret(account.accessKeptAt) || LegacyAccounts.looksLikeSecret(account.notes) {
                        Label("This looks like a password or code. Remove it and write where it's kept instead.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.callout)
                    }
                    Button("Remove", role: .destructive) { plan.accounts.removeAll { $0.id == account.id } }
                        .controlSize(.small)
                }
            }
            Section {
                Button("Add an Account") { plan.accounts.append(LegacyAccount()) }
            }
        }
    }
}

// MARK: - Recordings and files

private struct LegacyArchiveForm: View {
    @Binding var plan: LegacyPlan

    static let common = ["Masters", "Stems and multitracks", "Session files", "Unreleased songs and demos",
                         "Artwork and photos", "Lyrics and notebooks", "Videos"]

    var body: some View {
        Form {
            Section {
                Text("Store releases can be re-downloaded; masters, stems, session files and unreleased material can't. Write down where each is, and where the second copy is.")
                    .foregroundStyle(.secondary)
                let missing = Self.common.filter { name in !plan.archive.contains { $0.what.caseInsensitiveCompare(name) == .orderedSame } }
                if !missing.isEmpty {
                    HStack {
                        ForEach(missing.prefix(4), id: \.self) { name in
                            Button(name) { plan.archive.append(ArchiveLocation(what: name)) }.controlSize(.small)
                        }
                        if missing.count > 4 {
                            Menu("More") {
                                ForEach(Array(missing.dropFirst(4)), id: \.self) { name in
                                    Button(name) { plan.archive.append(ArchiveLocation(what: name)) }
                                }
                            }
                            .controlSize(.small)
                            .fixedSize()
                        }
                    }
                }
            }
            ForEach($plan.archive) { $item in
                Section(item.what.isBlank ? "Files" : item.what) {
                    TextField("What", text: $item.what)
                    TextField("Where", text: $item.location, prompt: Text("e.g. Studio drive “Masters 2026”; Dropbox › Music"))
                    TextField("Second copy", text: $item.backupLocation, prompt: Text("e.g. Backblaze; drive at my parents' house"))
                    TextField("Notes", text: $item.notes, prompt: Text("Format, folder names, who engineered it"), axis: .vertical)
                        .lineLimit(1...3)
                    if !item.location.isBlank && item.backupLocation.isBlank {
                        Label("Only one copy written down.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
                    }
                    Button("Remove", role: .destructive) { plan.archive.removeAll { $0.id == item.id } }
                        .controlSize(.small)
                }
            }
            Section {
                Button("Add Something Else") { plan.archive.append(ArchiveLocation()) }
            }
        }
    }
}

// MARK: - Wishes

private struct LegacyWishesForm: View {
    @Binding var wishes: LegacyWishes

    var body: some View {
        Form {
            Section {
                Text("In your own words. These guide your executor; your will or trust is what makes them binding.")
                    .foregroundStyle(.secondary)
            }
            wish("Your catalog", "Keep everything in stores? Who decides on reissues, remasters or a sale?", text: $wishes.catalog)
            wish("Unreleased music", "Which demos and sessions may be finished or released, by whom — and which must never be?", text: $wishes.unreleased)
            wish("Licensing", "Uses you'd welcome (films, causes, samples) and ones never to approve.", text: $wishes.licensing)
            wish("Your name, image and voice", "Photos, merch, documentaries, tributes — and AI voice models or recreations of you.", text: $wishes.nameAndLikeness)
            wish("Instruments, notebooks and memorabilia", "Keep, give to someone, donate to an archive or sell?", text: $wishes.archive)
            wish("Anything else", "Messages for your team or fans, causes royalties could support.", text: $wishes.other)
        }
    }

    private func wish(_ title: String, _ prompt: String, text: Binding<String>) -> some View {
        Section(title) {
            TextField(title, text: text, prompt: Text(prompt), axis: .vertical)
                .lineLimit(3...10)
                .labelsHidden()
        }
    }
}
