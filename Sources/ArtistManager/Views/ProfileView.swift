import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft = ArtistProfile()
    @State private var loaded = false
    @State private var section: ProfilePage = .identity

    enum ProfilePage: String, CaseIterable, Identifiable {
        case identity, brand, audience, rights, budget, communication
        var id: String { rawValue }
        var label: String {
            switch self {
            case .identity: return "Artist"
            case .brand: return "Brand & bio"
            case .audience: return "Audience"
            case .rights: return "Rights"
            case .budget: return "Budget & time"
            case .communication: return "Communication"
            }
        }
    }

    private var hasChanges: Bool { loaded && draft != model.workspace.profile }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader("Profile & Brand", subtitle: "Everything Manager drafts starts from here.") {
                HStack {
                    Button("Revert") { draft = model.workspace.profile }.disabled(!hasChanges)
                    Button("Save Changes") { save() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(!hasChanges)
                }
            }
            .padding([.horizontal, .top], 24)
            Picker("Section", selection: $section) {
                ForEach(ProfilePage.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            Group {
                switch section {
                case .identity: IdentityForm(profile: $draft)
                case .brand: BrandForm(profile: $draft)
                case .audience: AudienceForm(profile: $draft)
                case .rights: RightsForm(profile: $draft)
                case .budget: BudgetTimeForm(profile: $draft)
                case .communication: CommunicationForm(profile: $draft)
                }
            }
            .formStyle(.grouped)
        }
        .onAppear {
            if !loaded { draft = model.workspace.profile; loaded = true }
        }
        .onChange(of: model.workspace.profile) { _, newValue in
            // Pick up changes made elsewhere (onboarding, undo) when there are no local edits.
            if !hasChanges { draft = newValue }
        }
        .onDisappear {
            if hasChanges { save() }
        }
    }

    private func save() {
        var p = draft
        p.updatedAt = Date()
        model.perform("Updated your profile", kind: .editRecord, showUndo: true) { $0.profile = p }
        draft = model.workspace.profile
    }
}

private struct IdentityForm: View {
    @Binding var profile: ArtistProfile
    var body: some View {
        Form {
            Section("Artist") {
                TextField("Artist or project name", text: $profile.artistName)
                TextField("Legal name", text: $profile.legalName)
                TextField("Pronouns", text: $profile.pronouns)
                TextField("Based in", text: $profile.location)
                TextField("Country", text: $profile.country)
                TagsField(title: "Genres", values: $profile.genres)
            }
            Section("Links") {
                TextField("Website", text: $profile.links.website)
                TextField("Spotify", text: $profile.links.spotify)
                TextField("Apple Music", text: $profile.links.appleMusic)
                TextField("Bandcamp", text: $profile.links.bandcamp)
                TextField("YouTube", text: $profile.links.youtube)
                TextField("SoundCloud", text: $profile.links.soundcloud)
                TextField("Instagram", text: $profile.links.instagram)
                TextField("TikTok", text: $profile.links.tiktok)
                TextField("Other", text: $profile.links.other)
            }
        }
    }
}

private struct BrandForm: View {
    @Binding var profile: ArtistProfile
    var body: some View {
        Form {
            Section("Sound and positioning") {
                TextField("What it sounds like", text: $profile.soundDescription, axis: .vertical).lineLimit(2...6)
                TextField("Influences", text: $profile.influences, axis: .vertical)
                TextField("Positioning", text: $profile.positioning, axis: .vertical).lineLimit(2...5)
                TextField("Visual identity", text: $profile.visualIdentity, axis: .vertical).lineLimit(2...5)
            }
            Section("Bio") {
                VStack(alignment: .leading) {
                    Text("Short bio — used in pitches and press releases").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $profile.bioShort).frame(minHeight: 70).font(.body)
                        .accessibilityLabel("Short bio")
                }
                VStack(alignment: .leading) {
                    Text("Full bio — used in the press kit").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $profile.bioLong).frame(minHeight: 180).font(.body)
                        .accessibilityLabel("Full bio")
                }
            }
        }
    }
}

private struct AudienceForm: View {
    @Binding var profile: ArtistProfile
    var body: some View {
        Form {
            Section("Audience") {
                TextField("Core fans", text: $profile.audience.description, axis: .vertical).lineLimit(2...6)
                TextField("Top cities or regions", text: $profile.audience.topMarkets)
                TextField("Age range", text: $profile.audience.ageRange)
                TextField("Where they discover music", text: $profile.audience.discoveryChannels)
                TextField("Comparable artists", text: $profile.audience.comparableArtists)
            }
        }
    }
}

private struct RightsForm: View {
    @Binding var profile: ArtistProfile
    var body: some View {
        Form {
            Section {
                Text("Record the organizations that collect your royalties. Manager tracks status only — it doesn't register anything for you.")
                    .foregroundStyle(.secondary)
                ForEach($profile.rightsMemberships) { $membership in
                    VStack(alignment: .leading) {
                        HStack {
                            TextField("Organization (e.g. BMI, The MLC, SoundExchange)", text: $membership.organization)
                            Button(role: .destructive) {
                                profile.rightsMemberships.removeAll { $0.id == membership.id }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove organization")
                        }
                        HStack {
                            Picker("Type", selection: $membership.type) {
                                ForEach(RightsOrgType.allCases) { Text($0.label).tag($0) }
                            }
                            Picker("Status", selection: $membership.status) {
                                ForEach(RegistrationStatus.allCases) { Text($0.label).tag($0) }
                            }
                        }
                        TextField("Notes (member number, login hint, renewal date)", text: $membership.notes)
                    }
                    .padding(.vertical, 4)
                }
                Button("Add Organization") { profile.rightsMemberships.append(RightsMembership()) }
            } header: {
                Text("Royalty and rights organizations")
            }
        }
    }
}

private struct BudgetTimeForm: View {
    @Binding var profile: ArtistProfile
    var body: some View {
        Form {
            Section("Budget") {
                TextField("Currency code", text: $profile.budget.currency)
                MoneyField(title: "Monthly marketing budget", value: $profile.budget.monthlyMarketingBudget, currency: profile.budget.currency)
                MoneyField(title: "Annual career budget", value: $profile.budget.annualBudget, currency: profile.budget.currency)
                TextField("Notes", text: $profile.budget.notes, axis: .vertical)
            }
            Section("Availability") {
                Stepper("Hours a week for career work: \(Int(profile.availability.hoursPerWeek))",
                        value: $profile.availability.hoursPerWeek, in: 1...80)
                WeekdayPicker(days: $profile.availability.workDays)
                BlackoutEditor(ranges: $profile.availability.blackoutDates)
                TextField("Notes", text: $profile.availability.notes, axis: .vertical)
            }
        }
    }
}

private struct CommunicationForm: View {
    @Binding var profile: ArtistProfile
    var body: some View {
        Form {
            Section("Drafts") {
                Picker("Tone", selection: $profile.communication.draftTone) {
                    ForEach(DraftTone.allCases) { Text($0.label).tag($0) }
                }
                TextField("Sign-off", text: $profile.communication.signOff)
                TextField("Reply-to email", text: $profile.communication.replyEmail)
            }
            Section("Email list compliance") {
                TextField("Mailing address for email footers", text: $profile.communication.mailingAddress, axis: .vertical)
            }
            Section("Notifications") {
                Toggle("Approvals waiting", isOn: $profile.communication.notifyForApprovals)
                Toggle("Upcoming deadlines", isOn: $profile.communication.notifyForDeadlines)
                Stepper("Warn \(profile.communication.deadlineWarningDays) days ahead", value: $profile.communication.deadlineWarningDays, in: 0...14)
            }
        }
    }
}
