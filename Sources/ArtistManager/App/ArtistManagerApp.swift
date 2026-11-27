import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Lets the app show a normal window and Dock icon when launched with `swift run` too.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct ArtistManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @State private var updates = UpdateController()

    var body: some Scene {
        WindowGroup("Manager", id: "main") {
            RootView()
                .safeAreaInset(edge: .top, spacing: 0) { UpdateBanner() }
                .environmentObject(model)
                .environment(updates)
                .frame(minWidth: 980, minHeight: 640)
                .task {
                    Notifier.shared.requestAuthorizationIfNeeded()
                    model.startAutomation()
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton()
                    .environment(updates)
            }
            CommandGroup(after: .undoRedo) {
                Button("Undo Last Manager Action") {
                    if let record = model.lastUndoableRecord { model.undo(record.id) }
                }
                .keyboardShortcut("z", modifiers: [.command, .option])
                .disabled(model.lastUndoableRecord == nil)
            }
            CommandMenu("Manager") {
                Button("Run Routine Work Now") { model.runAutomation() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Refresh Career Plan") { model.refreshPlanNow() }
                Divider()
                Button("Review Approvals") { model.selection = .approvals }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                Button("Edit Profile and Onboarding Answers…") { model.showOnboarding = true }
            }
            CommandGroup(replacing: .newItem) {}
        }

        Window("Software Update", id: "updates") {
            UpdateWindowView()
                .environment(updates)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(model)
                .environment(updates)
        }
    }
}
