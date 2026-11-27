import SwiftUI

struct TasksView: View {
    @EnvironmentObject var model: AppModel
    @State private var filter: Filter = .open
    @State private var area: WorkArea?
    @State private var search = ""
    @State private var editing: TaskItem?

    enum Filter: String, CaseIterable, Identifiable {
        case open, thisWeek, overdue, done, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .open: return "Open"
            case .thisWeek: return "Due this week"
            case .overdue: return "Overdue"
            case .done: return "Done"
            case .all: return "All"
            }
        }
    }

    private var tasks: [TaskItem] {
        let week = Date().startOfDay.adding(days: 7)
        return model.workspace.tasks.filter { task in
            switch filter {
            case .open: if !task.isOpen { return false }
            case .thisWeek: if !task.isOpen || (task.due ?? .distantFuture) >= week { return false }
            case .overdue: if !task.isOverdue() { return false }
            case .done: if task.isOpen { return false }
            case .all: break
            }
            if let area, task.area != area { return false }
            if !search.isBlank && !task.title.localizedCaseInsensitiveContains(search) && !task.notes.localizedCaseInsensitiveContains(search) { return false }
            return true
        }
        .sorted { a, b in
            if a.isOpen != b.isOpen { return a.isOpen }
            if (a.due ?? .distantFuture) != (b.due ?? .distantFuture) { return (a.due ?? .distantFuture) < (b.due ?? .distantFuture) }
            return a.priority > b.priority
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader("Tasks", subtitle: workloadText) {
                Button {
                    editing = TaskItem(due: Date().startOfDay.adding(days: 1))
                } label: {
                    Label("New Task", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding([.horizontal, .top], 24)
            HStack {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 460)
                Picker("Area", selection: $area) {
                    Text("All areas").tag(WorkArea?.none)
                    ForEach(WorkArea.allCases) { Text($0.label).tag(Optional($0)) }
                }
                .frame(maxWidth: 200)
                TextField("Search tasks", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            if tasks.isEmpty {
                EmptyStateView(title: filter == .open ? "No open tasks" : "Nothing here", symbol: "checklist",
                               message: "Tasks come from release timelines, accepted recommendations, contact follow-ups, or you.",
                               actionTitle: "New Task", action: { editing = TaskItem(due: Date().startOfDay.adding(days: 1)) })
            } else {
                List {
                    ForEach(tasks) { task in
                        TaskRow(task: task) { editing = task }
                    }
                }
            }
        }
        .sheet(item: $editing) { task in
            TaskEditor(task: task).environmentObject(model)
        }
    }

    private var workloadText: String {
        let load = CalendarService.workload(in: model.workspace)
        return "About \(Int(load.hoursDue.rounded())) hours due in the next 7 days · \(Int(load.hoursAvailable)) hours a week available"
    }
}

struct TaskRow: View {
    @EnvironmentObject var model: AppModel
    var task: TaskItem
    var onEdit: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                toggle()
            } label: {
                Image(systemName: task.isOpen ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(task.isOpen ? Color.secondary : Color.green)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isOpen ? "Mark “\(task.title)” done" : "Mark “\(task.title)” not done")
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).strikethrough(!task.isOpen).fontWeight(task.priority == .high ? .semibold : .regular)
                HStack(spacing: 6) {
                    if let due = task.due {
                        Label(due.relativeDayText, systemImage: "calendar")
                            .foregroundStyle(task.isOverdue() ? Color.red : Color.secondary)
                    }
                    Label(task.area.label, systemImage: task.area.symbol).foregroundStyle(.secondary)
                    if let release = model.workspace.release(task.releaseID) {
                        Text("· \(release.title)").foregroundStyle(.secondary)
                    }
                    if task.createdBy == .automation {
                        Text("· added by Manager").foregroundStyle(.secondary)
                    }
                    if task.status == .waiting || task.status == .inProgress {
                        StatusBadge(text: task.status.label, tone: .info)
                    }
                }
                .font(.caption)
            }
            Spacer()
            if let onEdit {
                Button("Edit", action: onEdit).controlSize(.small)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
    }

    private func toggle() {
        let id = task.id
        let done = task.isOpen
        model.perform(done ? "Completed: \(task.title)" : "Reopened: \(task.title)", showUndo: true) { ws in
            if let i = ws.tasks.firstIndex(where: { $0.id == id }) {
                ws.tasks[i].status = done ? .done : .todo
                ws.tasks[i].completedAt = done ? Date() : nil
            }
        }
    }
}

struct TaskEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var task: TaskItem

    private var exists: Bool { model.workspace.tasks.contains { $0.id == task.id } }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Task", text: $task.title)
                OptionalDatePicker(title: "Due", date: $task.due)
                Picker("Status", selection: $task.status) {
                    ForEach(TaskStatus.allCases) { Text($0.label).tag($0) }
                }
                Picker("Area", selection: $task.area) {
                    ForEach(WorkArea.allCases) { Text($0.label).tag($0) }
                }
                Picker("Priority", selection: $task.priority) {
                    ForEach(Priority.allCases) { Text($0.label).tag($0) }
                }
                Stepper("Estimated time: \(task.estimatedHours.formatted(.number.precision(.fractionLength(0...1)))) h",
                        value: $task.estimatedHours, in: 0.5...40, step: 0.5)
                Picker("Release", selection: $task.releaseID) {
                    Text("None").tag(UUID?.none)
                    ForEach(model.workspace.releases) { Text($0.title).tag(Optional($0.id)) }
                }
                Picker("Contact", selection: $task.contactID) {
                    Text("None").tag(UUID?.none)
                    ForEach(model.workspace.contacts.sorted(by: { $0.displayName < $1.displayName })) { Text($0.displayName).tag(Optional($0.id)) }
                }
                TextField("Notes", text: $task.notes, axis: .vertical).lineLimit(3...10)
            }
            .formStyle(.grouped)
            HStack {
                if exists {
                    Button("Delete", role: .destructive) {
                        let t = task
                        model.perform("Deleted task: \(t.title)", showUndo: true) { $0.remove(t.id, from: \.tasks) }
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    var t = task
                    if t.status == .done && t.completedAt == nil { t.completedAt = Date() }
                    if t.status != .done { t.completedAt = nil }
                    let saved = t
                    model.perform(exists ? "Updated task: \(saved.title)" : "Added task: \(saved.title)", showUndo: true) { $0.upsert(saved, in: \.tasks) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(task.title.isBlank)
            }
            .padding()
        }
        .frame(width: 520, height: 560)
    }
}
