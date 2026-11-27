import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CalendarView: View {
    @EnvironmentObject var model: AppModel
    @State private var month = Date().startOfMonth
    @State private var selectedDay = Date().startOfDay
    @State private var editingEvent: CalendarEvent?
    @State private var editingTask: TaskItem?

    private var ws: Workspace { model.workspace }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader("Calendar", subtitle: "Shows, sessions, release days, deadlines and planned emails in one place.") {
                HStack {
                    Button {
                        editingEvent = newEvent(on: selectedDay)
                    } label: {
                        Label("New Event", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    Menu {
                        Button("Import .ics File…") {
                            if let url = FilePanels.openFile(types: [.ics, .calendarEvent], message: "Choose a calendar file (.ics) exported from Calendar, Google Calendar or Outlook") {
                                model.importCalendar(from: url)
                            }
                        }
                        Button("Export Calendar as .ics…") {
                            let name = ws.profile.artistName.isBlank ? "Manager" : ws.profile.artistName
                            model.exportText(ICalendar.export(ws.events, calendarName: name), suggestedName: "\(model.safeFileName(name)) calendar.ics",
                                             types: [.ics], logTitle: "Exported calendar (.ics)")
                        }
                        .disabled(ws.events.isEmpty)
                    } label: {
                        Label("Import & Export", systemImage: "arrow.up.arrow.down")
                    }
                    .fixedSize()
                }
            }
            .padding([.horizontal, .top], 24)
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 8) {
                    monthHeader
                    MonthGrid(month: month, selectedDay: $selectedDay, items: monthItems)
                }
                .frame(minWidth: 460)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        dayAgenda
                        conflictsCard
                    }
                }
                .frame(width: 320)
            }
            .padding(24)
        }
        .sheet(item: $editingEvent) { event in
            EventEditor(event: event).environmentObject(model)
        }
        .sheet(item: $editingTask) { task in
            TaskEditor(task: task).environmentObject(model)
        }
    }

    private var monthItems: [AgendaItem] {
        let start = month.startOfMonth.adding(days: -7)
        let end = month.startOfMonth.addingMonths(1).adding(days: 14)
        return CalendarService.agenda(in: ws, from: start, to: end)
    }

    private var monthHeader: some View {
        HStack {
            Text(month.formatted(.dateTime.month(.wide).year())).font(.title2.weight(.semibold))
            Spacer()
            Button {
                month = month.addingMonths(-1)
            } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous month")
            Button("Today") {
                month = Date().startOfMonth
                selectedDay = Date().startOfDay
            }
            Button {
                month = month.addingMonths(1)
            } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next month")
        }
    }

    private var dayAgenda: some View {
        let items = CalendarService.agenda(in: ws, from: selectedDay, to: selectedDay.adding(days: 1))
        return Card(selectedDay.formatted(date: .complete, time: .omitted), symbol: "calendar") {
            if ws.profile.availability.isBlackedOut(selectedDay) {
                Label("You marked this day unavailable.", systemImage: "moon.zzz").foregroundStyle(.secondary)
            } else if !ws.profile.availability.workDays.isEmpty && !ws.profile.availability.workDays.contains(selectedDay.weekday) {
                Label("Not one of your usual work days.", systemImage: "cup.and.saucer").font(.caption).foregroundStyle(.secondary)
            }
            if items.isEmpty {
                Text("Nothing scheduled.").foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                Button {
                    open(item)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.symbol).frame(width: 18).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).foregroundStyle(.primary).multilineTextAlignment(.leading)
                            Text((item.isAllDay ? "All day" : item.date.formatted(date: .omitted, time: .shortened)) + " · " + item.subtitle)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens this item")
            }
            Button("Add Event on This Day") { editingEvent = newEvent(on: selectedDay) }.buttonStyle(.link)
        }
    }

    private var conflictsCard: some View {
        let conflicts = CalendarService.conflicts(in: ws)
        return Card("Conflicts and checks", symbol: "exclamationmark.triangle") {
            if conflicts.isEmpty {
                Label("No conflicts in the next four months.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
            ForEach(conflicts.prefix(12)) { conflict in
                Button {
                    selectedDay = conflict.date.startOfDay
                    month = conflict.date.startOfMonth
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conflict.title).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        Text("\(conflict.date.shortDate) · \(conflict.detail)").font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
            if conflicts.count > 12 {
                Text("and \(conflicts.count - 12) more").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func open(_ item: AgendaItem) {
        switch item.source {
        case .event(let id):
            if let event = ws.events.first(where: { $0.id == id }) { editingEvent = event }
        case .task(let id):
            if let task = ws.tasks.first(where: { $0.id == id }) { editingTask = task }
        case .release(let id):
            model.open(.releases, record: id)
        case .campaign(let id):
            model.open(.email, record: id)
        case .followUp(let id):
            model.open(.contacts, record: id)
        }
    }

    private func newEvent(on day: Date) -> CalendarEvent {
        let start = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: day) ?? day
        return CalendarEvent(title: "", kind: .show, start: start, end: start.adding(hours: 2))
    }
}

// MARK: - Month grid

private struct MonthGrid: View {
    var month: Date
    @Binding var selectedDay: Date
    var items: [AgendaItem]

    private var days: [Date] {
        let calendar = Calendar.current
        let first = month.startOfMonth
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let gridStart = first.adding(days: -leading)
        return (0..<42).map { gridStart.adding(days: $0) }
    }

    private var weekdaySymbols: [String] {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let shift = Calendar.current.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    var body: some View {
        let byDay = Dictionary(grouping: items, by: { $0.date.startOfDay })
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        VStack(spacing: 4) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption.weight(.medium)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                ForEach(days, id: \.self) { day in
                    DayCell(day: day, inMonth: Calendar.current.isDate(day, equalTo: month, toGranularity: .month),
                            isSelected: day.isSameDay(as: selectedDay), items: byDay[day.startOfDay] ?? []) {
                        selectedDay = day.startOfDay
                    }
                }
            }
        }
    }
}

private struct DayCell: View {
    var day: Date
    var inMonth: Bool
    var isSelected: Bool
    var items: [AgendaItem]
    var action: () -> Void

    private var isToday: Bool { day.isSameDay(as: Date()) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.formatted(.dateTime.day()))
                    .font(.callout.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.accentColor : (inMonth ? Color.primary : Color.secondary))
                ForEach(items.prefix(3)) { item in
                    HStack(spacing: 3) {
                        Image(systemName: item.symbol).imageScale(.small)
                        Text(item.title).lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                if items.count > 3 {
                    Text("+\(items.count - 3) more").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(5)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isSelected ? Color.accentColor : Color(nsColor: .separatorColor)))
            .opacity(inMonth ? 1 : 0.6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityText: String {
        let date = day.formatted(date: .complete, time: .omitted)
        guard !items.isEmpty else { return date }
        return "\(date), \(items.count) item\(items.count == 1 ? "" : "s"): " + items.prefix(3).map(\.title).joined(separator: ", ")
    }
}

// MARK: - Event editor

private struct EventEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var event: CalendarEvent
    @State private var confirmDelete = false
    @State private var contactSearch = ""

    private var exists: Bool { model.workspace.events.contains { $0.id == event.id } }

    private var conflicts: [ScheduleConflict] {
        var ws = model.workspace
        ws.upsert(event, in: \.events)
        return CalendarService.conflicts(in: ws, from: event.start.startOfDay.adding(days: -1), days: 3)
            .filter { $0.eventIDs.contains(event.id) }
    }

    private var people: [Contact] {
        model.workspace.contacts
            .filter { contactSearch.isBlank || $0.displayName.localizedCaseInsensitiveContains(contactSearch) || event.contactIDs.contains($0.id) }
            .sorted { a, b in
                let aIn = event.contactIDs.contains(a.id), bIn = event.contactIDs.contains(b.id)
                if aIn != bIn { return aIn }
                if a.isTeamMember != b.isTeamMember { return a.isTeamMember }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Event") {
                    TextField("Title", text: $event.title)
                    Picker("Kind", selection: $event.kind) {
                        ForEach(EventKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    Toggle("All day", isOn: $event.isAllDay)
                    DatePicker("Starts", selection: $event.start, displayedComponents: event.isAllDay ? [.date] : [.date, .hourAndMinute])
                    DatePicker("Ends", selection: $event.end, in: event.start..., displayedComponents: event.isAllDay ? [.date] : [.date, .hourAndMinute])
                    TextField("Location", text: $event.location)
                    ReleasePicker(selection: $event.releaseID)
                    TextField("Notes", text: $event.notes, axis: .vertical).lineLimit(2...6)
                }
                if !conflicts.isEmpty {
                    Section("Heads up") {
                        ForEach(conflicts) { c in
                            Label(c.title, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        }
                    }
                }
                Section {
                    TextField("Find a contact", text: $contactSearch)
                    if model.workspace.contacts.isEmpty {
                        Text("Add people in Contacts to attach them to events.").foregroundStyle(.secondary)
                    }
                    ForEach(people.prefix(25)) { contact in
                        Toggle(isOn: Binding(
                            get: { event.contactIDs.contains(contact.id) },
                            set: { on in
                                if on { if !event.contactIDs.contains(contact.id) { event.contactIDs.append(contact.id) } }
                                else { event.contactIDs.removeAll { $0 == contact.id } }
                            })) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(contact.displayName)
                                Text([contact.role.label, contact.email].filter { !$0.isBlank }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("People")
                } footer: {
                    Text("For shows, rehearsals, sessions and meetings, Manager can prepare reminder drafts to these people \(model.workspace.settings.reminderLeadDays) days ahead, following your reminder permission. You send them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                if exists {
                    Button("Delete", role: .destructive) { confirmDelete = true }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(event.title.isBlank)
            }
            .padding()
        }
        .frame(width: 560, height: 700)
        .onChange(of: event.start) { old, new in
            // Keep the length when the start moves.
            let length = event.end.timeIntervalSince(old)
            event.end = new.addingTimeInterval(max(length, 0))
        }
        .confirmationDialog("Delete “\(event.title)”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                let e = event
                model.perform("Deleted event: \(e.title)", kind: .updateCalendar, showUndo: true) { $0.remove(e.id, from: \.events) }
                dismiss()
            }
        } message: {
            Text("You can undo this from the activity log.")
        }
    }

    private func save() {
        var e = event
        if e.end < e.start { e.end = e.start }
        let saved = e
        model.perform(exists ? "Updated event: \(saved.title)" : "Added event: \(saved.title)", kind: .updateCalendar, showUndo: true) { ws in
            ws.upsert(saved, in: \.events)
        }
        dismiss()
    }
}

// MARK: - Date helpers

extension Date {
    var startOfMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self)) ?? startOfDay
    }

    func addingMonths(_ months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: self) ?? self
    }
}
