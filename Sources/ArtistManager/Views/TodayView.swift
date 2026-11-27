import SwiftUI

struct TodayView: View {
    @EnvironmentObject var model: AppModel

    private var ws: Workspace { model.workspace }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(greeting, subtitle: Date().formatted(date: .complete, time: .omitted)) {
                    Button {
                        model.runAutomation()
                    } label: {
                        Label("Run Routine Work", systemImage: "arrow.clockwise")
                    }
                    .help("Applies the routine work you've allowed and queues anything that needs approval.")
                }
                if !ws.profile.onboardingCompleted {
                    Card("Set up Manager", symbol: "sparkles") {
                        Text("Tell Manager about your music, goals, team, budget and approval rules to get a career plan.")
                        Button("Start Setup") { model.showOnboarding = true }.buttonStyle(.borderedProminent)
                    }
                }
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        needsAttention
                        nextSteps
                    }
                    VStack(spacing: 16) {
                        upcoming
                        snapshot
                    }
                    .frame(maxWidth: 360)
                }
            }
            .padding(24)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        return ws.profile.artistName.isBlank ? part : "\(part), \(ws.profile.artistName)"
    }

    // MARK: Needs attention

    private var needsAttention: some View {
        let pending = ws.pendingApprovals
        let overdue = ws.tasks.filter { $0.isOverdue() }.sorted { ($0.due ?? .distantPast) < ($1.due ?? .distantPast) }
        let conflicts = CalendarService.conflicts(in: ws, days: 30)
        let readyToSend = ws.outreach.filter { $0.status == .approved }
        let campaignsReady = ws.campaigns.filter { $0.status == .approved || $0.status == .exported }
        let total = pending.count + overdue.count + conflicts.count + readyToSend.count + campaignsReady.count

        return Card("Needs your attention", symbol: "exclamationmark.bubble") {
            if total == 0 {
                Label("You're all caught up.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
            if !pending.isEmpty {
                AttentionRow(symbol: "hourglass", tint: .orange,
                             title: "\(pending.count) waiting for your approval",
                             detail: pending.prefix(3).map(\.title).joined(separator: " · ")) {
                    model.selection = .approvals
                }
            }
            if !readyToSend.isEmpty {
                AttentionRow(symbol: "paperplane", tint: .blue,
                             title: "\(readyToSend.count) approved message\(readyToSend.count == 1 ? "" : "s") ready for you to send",
                             detail: "Approved, not sent yet. Send each one from your mail app (or Spotify for Artists for an editorial pitch), then mark it sent.") {
                    model.open(.press, tab: "outreach")
                }
            }
            if !campaignsReady.isEmpty {
                AttentionRow(symbol: "envelope.badge", tint: .blue,
                             title: "\(campaignsReady.count) approved email campaign\(campaignsReady.count == 1 ? "" : "s") not sent yet",
                             detail: "Export to your email provider, send it there, then record it as sent.") {
                    model.open(.email, tab: "campaigns")
                }
            }
            if !overdue.isEmpty {
                AttentionRow(symbol: "calendar.badge.exclamationmark", tint: .red,
                             title: "\(overdue.count) overdue task\(overdue.count == 1 ? "" : "s")",
                             detail: overdue.prefix(3).map(\.title).joined(separator: " · ")) {
                    model.selection = .tasks
                }
            }
            if !conflicts.isEmpty {
                AttentionRow(symbol: "exclamationmark.triangle", tint: .orange,
                             title: "\(conflicts.count) schedule conflict\(conflicts.count == 1 ? "" : "s")",
                             detail: conflicts.prefix(2).map(\.title).joined(separator: " · ")) {
                    model.selection = .calendar
                }
            }
        }
    }

    // MARK: Next steps

    private var nextSteps: some View {
        let open = ws.recommendations.filter { $0.status == .open }
            .sorted { $0.priority != $1.priority ? $0.priority > $1.priority : ($0.suggestedDue ?? .distantFuture) < ($1.suggestedDue ?? .distantFuture) }
        return Card("Recommended next steps", symbol: "lightbulb") {
            if open.isEmpty {
                Text(ws.profile.onboardingCompleted ? "No open recommendations. Refresh the plan after you add releases or goals." : "Finish setup to get recommendations.")
                    .foregroundStyle(.secondary)
            }
            ForEach(open.prefix(5)) { rec in
                RecommendationRow(rec: rec, compact: true)
                if rec.id != open.prefix(5).last?.id { Divider() }
            }
            if open.count > 5 {
                Button("See all \(open.count) in Career Plan") { model.selection = .plan }.buttonStyle(.link)
            }
        }
    }

    // MARK: Upcoming

    private var upcoming: some View {
        let items = CalendarService.agenda(in: ws, from: Date().startOfDay, to: Date().startOfDay.adding(days: 14))
        return Card("Next 14 days", symbol: "calendar") {
            if items.isEmpty {
                Text("Nothing scheduled.").foregroundStyle(.secondary)
            }
            ForEach(items.prefix(10)) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.symbol).frame(width: 18).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).lineLimit(2)
                        Text("\(item.date.relativeDayText)\(item.isAllDay ? "" : " · " + item.date.formatted(date: .omitted, time: .shortened)) · \(item.subtitle)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Button("Open Calendar") { model.selection = .calendar }.buttonStyle(.link)
        }
    }

    // MARK: Snapshot

    private var snapshot: some View {
        let subscribed = ws.subscribers.filter { $0.status == .subscribed }.count
        let nextRelease = ws.releases.filter { $0.stage.isActive && ($0.releaseDate ?? .distantPast) >= Date().startOfDay }
            .sorted { ($0.releaseDate ?? .distantFuture) < ($1.releaseDate ?? .distantFuture) }.first
        let epk = PressKitScore.evaluate(ws)
        let openTasks = ws.tasks.filter(\.isOpen).count
        return Card("Snapshot", symbol: "chart.bar") {
            LabeledText(label: "Next release", value: nextRelease.map { "\($0.title) — \($0.releaseDate!.shortDate)" } ?? "None scheduled")
            LabeledText(label: "Email subscribers", value: "\(subscribed)")
            LabeledText(label: "Press kit", value: "\(Int(epk.score * 100))% complete")
            LabeledText(label: "Open tasks", value: "\(openTasks)")
            LabeledText(label: "Contacts", value: "\(ws.contacts.count) (\(ws.teamMembers.count) on your team)")
        }
    }
}

struct AttentionRow: View {
    var symbol: String
    var tint: Color
    var title: String
    var detail: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol).foregroundStyle(tint).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.medium)
                    if !detail.isBlank { Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct RecommendationRow: View {
    @EnvironmentObject var model: AppModel
    var rec: Recommendation
    var compact = false
    @State private var showWhy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: rec.area.symbol).foregroundStyle(.secondary).frame(width: 18)
                Text(rec.title).fontWeight(.medium)
                Spacer()
                if rec.priority == .high { rec.priority.badge }
                StatusBadge(text: rec.status.label, tone: rec.status == .open ? .info : .neutral, symbol: rec.status == .open ? "lightbulb" : nil)
            }
            Text(rec.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if showWhy || !compact {
                Text("Why: \(rec.rationale)").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button("Go There") { model.open(rec.destination, record: rec.relatedID, tab: rec.destinationTab) }
                if rec.status == .open {
                    Button("Add to Tasks") { accept() }
                    Button("Mark Done") { setStatus(.done, title: "Marked done") }
                    Button("Dismiss") { setStatus(.dismissed, title: "Dismissed") }
                } else if rec.status != .resolved {
                    Button("Reopen") { setStatus(.open, title: "Reopened") }
                }
                if compact && !showWhy {
                    Button("Why?") { showWhy = true }.buttonStyle(.link)
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private func setStatus(_ status: RecommendationStatus, title: String) {
        model.perform("\(title): \(rec.title)", kind: .editRecord, showUndo: true) { ws in
            if let i = ws.recommendations.firstIndex(where: { $0.id == rec.id }) {
                ws.recommendations[i].status = status
                ws.recommendations[i].updatedAt = Date()
            }
        }
    }

    private func accept() {
        let task = TaskItem(title: rec.title, notes: rec.detail + "\n\nWhy: " + rec.rationale, due: rec.suggestedDue ?? Date().startOfDay.adding(days: 7),
                            area: rec.area, priority: rec.priority, releaseID: rec.destination == .releases ? rec.relatedID : nil,
                            createdBy: .artist, templateKey: "recommendation:\(rec.ruleKey)")
        model.perform("Added to tasks: \(rec.title)", kind: .createTasks, showUndo: true) { ws in
            if !ws.tasks.contains(where: { $0.templateKey == task.templateKey }) { ws.tasks.append(task) }
            if let i = ws.recommendations.firstIndex(where: { $0.id == rec.id }) {
                ws.recommendations[i].status = .accepted
                ws.recommendations[i].updatedAt = Date()
            }
        }
    }
}
