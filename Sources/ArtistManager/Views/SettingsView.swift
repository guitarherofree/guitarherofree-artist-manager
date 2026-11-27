import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            UpdateSettingsView().tabItem { Label("Updates", systemImage: "arrow.down.circle") }
            PermissionsSettingsView().tabItem { Label("Permissions", systemImage: "checkmark.shield") }
            DataSettingsView().tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 620, height: 520)
    }
}

struct DataSettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmRestore = false
    @State private var restoreURL: URL?

    var body: some View {
        Form {
            Section("Your data") {
                Text("Everything is stored on this Mac in a single file, with a backup each day for the last two weeks.")
                    .foregroundStyle(.secondary)
                LabeledContent("Location", value: model.persistence.rootURL.path)
                HStack {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.persistence.workspaceURL]) }
                    Button("Export Backup…") {
                        if let url = FilePanels.saveFile(name: "Manager Backup.json", types: [.json]) { model.exportBackup(to: url) }
                    }
                    Button("Restore from Backup…") {
                        if let url = FilePanels.openFile(types: [.json], message: "Choose a Manager backup") {
                            restoreURL = url
                            confirmRestore = true
                        }
                    }
                }
            }
            Section("Routine work") {
                Toggle("Let Manager do routine work you've allowed", isOn: Binding(
                    get: { model.workspace.settings.automationEnabled },
                    set: { on in model.perform(on ? "Turned on routine work" : "Turned off routine work") { $0.settings.automationEnabled = on } }))
                Stepper("Draft follow-ups after \(model.workspace.settings.followUpAfterDays) days without a reply",
                        value: Binding(get: { model.workspace.settings.followUpAfterDays },
                                       set: { v in model.perform("Changed follow-up timing") { $0.settings.followUpAfterDays = v } }),
                        in: 2...30)
                Stepper("Prepare event reminders \(model.workspace.settings.reminderLeadDays) days ahead",
                        value: Binding(get: { model.workspace.settings.reminderLeadDays },
                                       set: { v in model.perform("Changed reminder timing") { $0.settings.reminderLeadDays = v } }),
                        in: 1...14)
                Stepper("Suggest team check-ins after \(model.workspace.settings.teamCheckInDays) days",
                        value: Binding(get: { model.workspace.settings.teamCheckInDays },
                                       set: { v in model.perform("Changed team check-in timing") { $0.settings.teamCheckInDays = v } }),
                        in: 7...90, step: 7)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Replace your current data with this backup?", isPresented: $confirmRestore) {
            Button("Restore") { if let url = restoreURL { model.restoreBackup(from: url) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can undo this from the activity log.")
        }
    }
}
