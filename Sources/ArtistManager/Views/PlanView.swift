import SwiftUI

struct PlanView: View {
    @EnvironmentObject var model: AppModel
    @State private var editingGoal: CareerGoal?
    @State private var filter: RecommendationFilter = .open

    enum RecommendationFilter: String, CaseIterable, Identifiable {
        case open, accepted, closed
        var id: String { rawValue }
        var label: String {
            switch self {
            case .open: return "Open"
            case .accepted: return "In tasks"
            case .closed: return "Done & dismissed"
            }
        }
    }

    private var ws: Workspace { model.workspace }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader("Career Plan", subtitle: "Goals, milestones and the next steps that move them forward.") {
                    Button {
                        model.refreshPlanNow()
                    } label: {
                        Label("Refresh Plan", systemImage: "arrow.clockwise")
                    }
                }
                positioning
                goals
                milestones
                recommendations
            }
            .padding(24)
        }
        .sheet(item: $editingGoal) { goal in
            GoalEditor(goal: goal).environmentObject(model)
        }
    }

    private var positioning: some View {
        Card("Positioning", symbol: "scope") {
            if ws.profile.positioning.isBlank && ws.profile.audience.description.isBlank {
                Text("Add your positioning and audience in Profile & Brand so the plan and drafts reflect them.").foregroundStyle(.secondary)
            } else {
                LabeledText(label: "Positioning", value: ws.profile.positioning)
                LabeledText(label: "Core audience", value: ws.profile.audience.description)
                LabeledText(label: "Top markets", value: ws.profile.audience.topMarkets)
            }
            Button("Edit in Profile") { model.selection = .profile }.buttonStyle(.link)
        }
    }

    private var goals: some View {
        Card("Goals", symbol: "flag") {
            if ws.goals.isEmpty {
                Text("No goals yet. Goals let the plan rank what matters most.").foregroundStyle(.secondary)
            }
            ForEach(ws.goals) { goal in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: goal.category.symbol).foregroundStyle(.secondary).frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.title).fontWeight(.medium)
                        Text([goal.category.label, goal.metric, goal.targetDate.map { "by \($0.shortDate)" } ?? ""]
                            .filter { !$0.isBlank }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: goal.status.label, tone: goal.status == .achieved ? .success : (goal.status == .inProgress ? .info : .neutral))
                    Button("Edit") { editingGoal = goal }.controlSize(.small)
                }
                .accessibilityElement(children: .contain)
            }
            Button {
                editingGoal = CareerGoal()
            } label: {
                Label("Add Goal", systemImage: "plus")
            }
        }
    }

    private var milestones: some View {
        let items = PlanGenerator.milestones(for: ws)
        return Card("Milestones", symbol: "point.topleft.down.curvedto.point.bottomright.up") {
            if items.isEmpty {
                Text("Milestones appear here from goal dates, release days and key campaign steps.").foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isComplete ? Color.green : Color.secondary)
                        .accessibilityLabel(item.isComplete ? "Complete" : "Not complete")
                    Text(item.date?.shortDate ?? "No date").font(.callout.monospacedDigit()).frame(width: 110, alignment: .leading)
                        .foregroundStyle(.secondary)
                    Text(item.title).strikethrough(item.isComplete)
                    Spacer()
                    Text(item.area.label).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var recommendations: some View {
        let list = ws.recommendations.filter { rec in
            switch filter {
            case .open: return rec.status == .open
            case .accepted: return rec.status == .accepted
            case .closed: return [.done, .dismissed, .resolved].contains(rec.status)
            }
        }.sorted { a, b in
            a.priority != b.priority ? a.priority > b.priority : (a.suggestedDue ?? .distantFuture) < (b.suggestedDue ?? .distantFuture)
        }
        return Card("Recommended next steps", symbol: "lightbulb") {
            Picker("Show", selection: $filter) {
                ForEach(RecommendationFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("Recommendations are suggestions based on your goals and data. They don't do anything until you act on them.")
                .font(.caption).foregroundStyle(.secondary)
            if list.isEmpty {
                Text(filter == .open ? "Nothing open. Refresh the plan after adding releases, goals or contacts." : "Nothing here yet.")
                    .foregroundStyle(.secondary).padding(.vertical, 8)
            }
            ForEach(list) { rec in
                RecommendationRow(rec: rec)
                Divider()
            }
        }
    }
}

struct GoalEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var goal: CareerGoal
    @State private var confirmDelete = false

    private var isNew: Bool { !model.workspace.goals.contains { $0.id == goal.id } }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Goal", text: $goal.title)
                Picker("Area", selection: $goal.category) {
                    ForEach(GoalCategory.allCases) { Text($0.label).tag($0) }
                }
                TextField("How you'll measure it", text: $goal.metric)
                OptionalDatePicker(title: "Target date", date: $goal.targetDate)
                Picker("Status", selection: $goal.status) {
                    ForEach(GoalStatus.allCases) { Text($0.label).tag($0) }
                }
                TextField("Notes", text: $goal.notes, axis: .vertical).lineLimit(3...6)
            }
            .formStyle(.grouped)
            HStack {
                if !isNew {
                    Button("Delete Goal", role: .destructive) { confirmDelete = true }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    let g = goal
                    model.perform(isNew ? "Added goal: \(g.title)" : "Updated goal: \(g.title)", showUndo: true) { $0.upsert(g, in: \.goals) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(goal.title.isBlank)
            }
            .padding()
        }
        .frame(width: 520, height: 420)
        .confirmationDialog("Delete this goal?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                let g = goal
                model.perform("Deleted goal: \(g.title)", showUndo: true) { $0.remove(g.id, from: \.goals) }
                dismiss()
            }
        } message: {
            Text("You can undo this from the activity log.")
        }
    }
}
