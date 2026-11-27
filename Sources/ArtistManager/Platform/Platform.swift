import AppKit
import Foundation
import UniformTypeIdentifiers
import UserNotifications

// MARK: - Notifications

/// Local notifications to the artist. Only used when the app runs as a bundled .app
/// (UserNotifications requires a bundle identifier).
@MainActor
final class Notifier {
    static let shared = Notifier()
    private var authorized = false
    private var requested = false

    private var isAvailable: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") }

    func requestAuthorizationIfNeeded() {
        guard isAvailable, !requested else { return }
        requested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in Notifier.shared.authorized = granted }
        }
    }

    func notify(title: String, body: String) {
        guard isAvailable, authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func dailySummary(for ws: Workspace) {
        let prefs = ws.profile.communication
        var parts: [String] = []
        let pending = ws.pendingApprovals.count
        if prefs.notifyForApprovals && pending > 0 { parts.append("\(pending) approval\(pending == 1 ? "" : "s") waiting") }
        if prefs.notifyForDeadlines {
            let horizon = Date().startOfDay.adding(days: max(prefs.deadlineWarningDays, 0) + 1)
            let due = ws.tasks.filter { $0.isOpen && ($0.due ?? .distantFuture) < horizon }.count
            if due > 0 { parts.append("\(due) task\(due == 1 ? "" : "s") due soon") }
        }
        guard !parts.isEmpty else { return }
        notify(title: "Today in Manager", body: parts.joined(separator: " · "))
    }
}

// MARK: - Open and save panels

@MainActor
enum FilePanels {
    static func openFile(types: [UTType], message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func openFiles(types: [UTType], message: String) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = message
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func openImages() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Choose press photos"
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func saveFile(name: String, types: [UTType], message: String = "") -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = types
        panel.canCreateDirectories = true
        if !message.isEmpty { panel.message = message }
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseFolder(message: String, prompt: String = "Choose") -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
}

extension UTType {
    static let ics = UTType(filenameExtension: "ics") ?? .data
    static let csvFile = UTType.commaSeparatedText
}

// MARK: - Mail drafts and clipboard

enum MailDraft {
    /// Opens a new message in the artist's default mail app. Nothing is sent: the artist reviews and presses Send.
    @discardableResult
    static func open(to: String, subject: String, body: String) -> Bool {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = to
        components.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        guard let url = components.url else { return false }
        return NSWorkspace.shared.open(url)
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func text() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}

