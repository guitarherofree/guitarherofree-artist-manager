import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    enum Step: Int, CaseIterable {
        case welcome, music, audience, goals, team, budget, communication, approvals, review
        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .music: return "Music & brand"
            case .audience: return "Audience"
            case .goals: return "Goals"
            case .team: return "Team"
            case .budget: return "Budget & time"
            case .communication: return "Communication"
            case .approvals: return "Approval rules"
            case .review: return "Review"
            }
        }
    }

    @State private var step: Step = .welcome
    @State private var profile: ArtistProfile
    @State private var goals: [CareerGoal]
    @State private var team: [Contact]
    @State private var permissions: PermissionPolicy
    private let isEditing: Bool

    init(existing: Workspace) {
        _profile = State(initialValue: existing.profile)
        let existingGoals = existing.goals
        _goals = State(initialValue: existingGoals.isEmpty ? [CareerGoal(title: "", category: .audience)] : existingGoals)
        _team = State(initialValue: existing.teamMembers)
        _permissions = State(initialValue: existing.permissions)
        isEditing = existing.profile.onboardingCompleted
    }

    var body: some View {
        VStack(spacing: 0) {
            stepper
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .padding(28)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            Divider()
            footer
        }
    }

    private var stepper: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Button {
                    step = s
                } label: {
                    Text(s.title)
                        .font(.caption.weight(s == step ? .semibold : .regular))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(s == step ? Color.accentColor.opacity(0.15) : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Step \(s.rawValue + 1) of \(Step.allCases.count): \(s.title)")
                .accessibilityAddTraits(s == step ? .isSelected : [])
            }
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            if isEditing || step != .welcome {
                Button(isEditing ? "Cancel" : "Finish Later") { dismiss() }
                    .help("Your answers aren't saved until you finish. You can come back from the Manager menu.")
            }
            Spacer()
            if step != .welcome {
                Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
            }
            if step == .review {
                Button(isEditing ? "Save Changes" : "Create My Plan") {
                    model.completeOnboarding(profile: profile, goals: goals, team: team, permissions: permissions)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(profile.artistName.isBlank)
            } else {
                Button(step == .welcome ? "Get Started" : "Continue") { step = Step(rawValue: step.rawValue + 1) ?? .review }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: welcome
        case .music: music
        case .audience: audience
        case .goals: goalsStep
        case .team: teamStep
        case .budget: budgetStep
        case .communication: communicationStep
        case .approvals: approvalsStep
        case .review: review
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your career, organized").font(.largeTitle.weight(.semibold))
            Text("Manager keeps your plan, releases, press kit, email list, calendar and contacts in one place, and does the routine work you allow.")
                .font(.title3)
            VStack(alignment: .leading, spacing: 10) {
                Label("You stay in charge: nothing is sent, published, accepted, spent or signed without your approval.", systemImage: "checkmark.shield")
                Label("Every action is logged, and reversible changes can be undone.", systemImage: "arrow.uturn.backward")
                Label("Your data stays on this Mac.", systemImage: "lock")
                Label("About 10 minutes. You can skip anything and fill it in later.", systemImage: "clock")
            }
            .padding(.top, 8)
        }
    }

    private var music: some View {
        Form {
            Section("Who you are") {
                TextField("Artist or project name", text: $profile.artistName)
                TextField("Legal name (for contracts and registrations)", text: $profile.legalName)
                TextField("Pronouns", text: $profile.pronouns)
                TextField("Based in (city, region)", text: $profile.location)
                TextField("Country", text: $profile.country)
            }
            Section("Your music") {
                TagsField(title: "Genres", values: $profile.genres)
                TextField("What it sounds like", text: $profile.soundDescription, axis: .vertical).lineLimit(2...5)
                TextField("Influences", text: $profile.influences)
            }
            Section("Brand") {
                TextField("Positioning: what makes you distinct, in a sentence", text: $profile.positioning, axis: .vertical).lineLimit(2...4)
                TextField("Visual identity (colors, mood, references)", text: $profile.visualIdentity, axis: .vertical).lineLimit(2...4)
                TextField("Short bio (2–3 sentences)", text: $profile.bioShort, axis: .vertical).lineLimit(3...6)
            }
            Section("Links") {
                TextField("Website", text: $profile.links.website)
                TextField("Spotify", text: $profile.links.spotify)
                TextField("Apple Music", text: $profile.links.appleMusic)
                TextField("Bandcamp", text: $profile.links.bandcamp)
                TextField("YouTube", text: $profile.links.youtube)
                TextField("Instagram", text: $profile.links.instagram)
            }
        }
        .formStyle(.grouped)
    }

    private var audience: some View {
        Form {
            Section("Who listens") {
                TextField("Describe your core fans", text: $profile.audience.description, axis: .vertical).lineLimit(2...5)
                TextField("Top cities or regions", text: $profile.audience.topMarkets)
                TextField("Age range", text: $profile.audience.ageRange)
                TextField("Where they discover music", text: $profile.audience.discoveryChannels)
                TextField("Artists your fans also like", text: $profile.audience.comparableArtists)
            }
        }
        .formStyle(.grouped)
    }

    private var goalsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What do you want the next 12 months to deliver?").font(.title2.weight(.semibold))
            Text("One to three measurable goals work best. The plan ranks recommendations against them.").foregroundStyle(.secondary)
            ForEach($goals) { $goal in
                GroupBox {
                    VStack(alignment: .leading) {
                        HStack {
                            TextField("Goal, e.g. “Reach 1,000 email subscribers”", text: $goal.title)
                            Button(role: .destructive) {
                                goals.removeAll { $0.id == goal.id }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove goal")
                        }
                        HStack {
                            Picker("Area", selection: $goal.category) {
                                ForEach(GoalCategory.allCases) { Text($0.label).tag($0) }
                            }
                            .frame(maxWidth: 260)
                            TextField("How you'll measure it", text: $goal.metric)
                        }
                        OptionalDatePicker(title: "Target date", date: $goal.targetDate)
                    }
                    .padding(4)
                }
            }
            Button("Add Goal") { goals.append(CareerGoal(title: "", category: .streaming)) }
        }
    }

    private var teamStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Who's on your team?").font(.title2.weight(.semibold))
            Text("Anyone you work with regularly: booking agent, attorney, accountant, publicist, producer, distributor rep. Leave it empty if it's just you for now.")
                .foregroundStyle(.secondary)
            ForEach($team) { $member in
                GroupBox {
                    VStack(alignment: .leading) {
                        HStack {
                            TextField("Name", text: $member.name)
                            Picker("Role", selection: $member.role) {
                                ForEach(ContactRole.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 200)
                            Button(role: .destructive) {
                                team.removeAll { $0.id == member.id }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove team member")
                        }
                        HStack {
                            TextField("Email", text: $member.email)
                            TextField("Company", text: $member.organization)
                        }
                        TextField("What they handle for you", text: $member.responsibilities)
                    }
                    .padding(4)
                }
            }
            Button("Add Team Member") { team.append(Contact(role: .bookingAgent, isTeamMember: true)) }
        }
    }

    private var budgetStep: some View {
        Form {
            Section("Budget") {
                TextField("Currency code", text: $profile.budget.currency)
                MoneyField(title: "Monthly marketing budget", value: $profile.budget.monthlyMarketingBudget, currency: profile.budget.currency)
                MoneyField(title: "Annual career budget", value: $profile.budget.annualBudget, currency: profile.budget.currency)
                TextField("Notes (e.g. grants, savings, label advances)", text: $profile.budget.notes, axis: .vertical)
            }
            Section("Time") {
                Stepper("Hours a week for career work: \(Int(profile.availability.hoursPerWeek))",
                        value: $profile.availability.hoursPerWeek, in: 1...80)
                WeekdayPicker(days: $profile.availability.workDays)
                BlackoutEditor(ranges: $profile.availability.blackoutDates)
            }
        }
        .formStyle(.grouped)
    }

    private var communicationStep: some View {
        Form {
            Section("How drafts should sound") {
                Picker("Tone", selection: $profile.communication.draftTone) {
                    ForEach(DraftTone.allCases) { Text($0.label).tag($0) }
                }
                TextField("Sign-off (e.g. “Thanks, Sam”)", text: $profile.communication.signOff)
                TextField("Reply-to email", text: $profile.communication.replyEmail)
            }
            Section("Email list compliance") {
                TextField("Mailing address for email footers", text: $profile.communication.mailingAddress, axis: .vertical)
                Text("Commercial email in the US must include a valid postal address (a P.O. box or registered mailbox is fine).")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Notifications") {
                Toggle("Notify me when something needs my approval", isOn: $profile.communication.notifyForApprovals)
                Toggle("Notify me about upcoming deadlines", isOn: $profile.communication.notifyForDeadlines)
                Stepper("Warn me \(profile.communication.deadlineWarningDays) days before deadlines",
                        value: $profile.communication.deadlineWarningDays, in: 0...14)
            }
        }
        .formStyle(.grouped)
    }

    private var approvalsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What ca Manager do without asking?").font(.title2.weight(.semibold))
            Text("Routine work only. Anything that goes out, gets published, accepts an offer, spends money or commits you always needs your approval.")
                .foregroundStyle(.secondary)
            PermissionsEditor(policy: $permissions)
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ready to build your plan").font(.title2.weight(.semibold))
            if profile.artistName.isBlank {
                Label("Add your artist name on the Music & brand step to continue.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Card("You") {
                LabeledText(label: "Artist", value: profile.artistName)
                LabeledText(label: "Genres", value: profile.genres.commaJoined)
                LabeledText(label: "Based in", value: profile.location)
            }
            Card("Goals") {
                let named = goals.filter { !$0.title.isBlank }
                if named.isEmpty { Text("No goals yet — you can add them on the Career Plan page.").foregroundStyle(.secondary) }
                ForEach(named) { goal in
                    Label(goal.title + (goal.targetDate.map { " — by \($0.shortDate)" } ?? ""), systemImage: goal.category.symbol)
                }
            }
            Card("Team") {
                let named = team.filter { !$0.name.isBlank }
                if named.isEmpty { Text("Just you for now.").foregroundStyle(.secondary) }
                ForEach(named) { member in Text("\(member.name) — \(member.role.label)") }
            }
            Text("Next, Manager will draft your career plan with recommended next steps. Recommendations are suggestions — nothing happens until you act on them.")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Shared editors

struct WeekdayPicker: View {
    @Binding var days: [Int]
    private let symbols = Calendar.current.shortWeekdaySymbols

    var body: some View {
        HStack {
            Text("Days you work on your career")
            Spacer()
            ForEach(1...7, id: \.self) { day in
                Toggle(symbols[day - 1], isOn: Binding(
                    get: { days.contains(day) },
                    set: { on in
                        if on { if !days.contains(day) { days.append(day); days.sort() } }
                        else { days.removeAll { $0 == day } }
                    }))
                .toggleStyle(.button)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
            }
        }
    }
}

struct BlackoutEditor: View {
    @Binding var ranges: [DateRange]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Dates you're unavailable")
            ForEach($ranges) { $range in
                HStack {
                    DatePicker("From", selection: $range.start, displayedComponents: .date).labelsHidden()
                    Text("to")
                    DatePicker("To", selection: $range.end, in: range.start..., displayedComponents: .date).labelsHidden()
                    TextField("Reason (optional)", text: $range.reason)
                    Button {
                        ranges.removeAll { $0.id == range.id }
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove unavailable dates")
                }
            }
            Button("Add Unavailable Dates") {
                let start = Date().startOfDay
                ranges.append(DateRange(start: start, end: start.adding(days: 2)))
            }
        }
    }
}

struct PermissionsEditor: View {
    @Binding var policy: PermissionPolicy

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Always asks you first") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(ActionKind.allCases.filter(\.alwaysRequiresApproval)) { kind in
                        Label(kind.label, systemImage: "lock.fill")
                            .accessibilityLabel("\(kind.label): always asks first, can't be changed")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
            GroupBox("Routine work") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ActionKind.allCases.filter(\.isConfigurable)) { kind in
                        VStack(alignment: .leading, spacing: 2) {
                            Picker(kind.label, selection: Binding(
                                get: { policy.mode(for: kind) },
                                set: { policy.set($0, for: kind) })) {
                                ForEach(PermissionMode.allCases) { Text($0.label).tag($0) }
                            }
                            Text(kind.explanation).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(4)
            }
        }
    }
}

struct PermissionsSettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            PermissionsEditor(policy: Binding(
                get: { model.workspace.permissions },
                set: { newValue in model.perform("Changed permissions", kind: .editRecord, showUndo: true) { $0.permissions = newValue } }))
            .padding(20)
        }
    }
}
