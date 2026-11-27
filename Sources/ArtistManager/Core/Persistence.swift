import Foundation

/// Stores the workspace as JSON in Application Support, with daily backups and an atomic write on every change.
final class Persistence {
    let rootURL: URL
    var workspaceURL: URL { rootURL.appendingPathComponent("workspace.json") }
    var backupsURL: URL { rootURL.appendingPathComponent("Backups", isDirectory: true) }
    var mediaURL: URL { rootURL.appendingPathComponent("Media", isDirectory: true) }
    var updatesURL: URL { rootURL.appendingPathComponent("Updates", isDirectory: true) }

    static let maxBackups = 14

    static let folderName = "Manager"
    /// The app's first name. Data saved there moves to the new folder on first launch.
    static let legacyFolderName = "Artist Manager"

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            let current = support.appendingPathComponent(Persistence.folderName, isDirectory: true)
            Persistence.migrate(from: support.appendingPathComponent(Persistence.legacyFolderName, isDirectory: true), to: current)
            self.rootURL = current
        }
        for url in [self.rootURL, backupsURL, mediaURL, updatesURL] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Moves data from the old folder name, without ever overwriting anything in the new one.
    static func migrate(from legacy: URL, to current: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacy.path),
              !fm.fileExists(atPath: current.appendingPathComponent("workspace.json").path) else { return }
        if !fm.fileExists(atPath: current.path) {
            try? fm.moveItem(at: legacy, to: current)
            return
        }
        let items = (try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)) ?? []
        for item in items {
            let target = current.appendingPathComponent(item.lastPathComponent)
            if fm.fileExists(atPath: target.path) {
                // Merge folders such as Backups and Media file by file.
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    migrate(contentsOf: item, into: target)
                }
            } else {
                try? fm.moveItem(at: item, to: target)
            }
        }
    }

    private static func migrate(contentsOf folder: URL, into target: URL) {
        let fm = FileManager.default
        for item in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            let destination = target.appendingPathComponent(item.lastPathComponent)
            if !fm.fileExists(atPath: destination.path) { try? fm.moveItem(at: item, to: destination) }
        }
    }

    enum LoadResult {
        case fresh(Workspace)
        case loaded(Workspace)
        /// The file existed but couldn't be read. It has been set aside, not deleted.
        case recovered(Workspace, movedTo: URL, error: String)
    }

    func load() -> LoadResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: workspaceURL.path) else { return .fresh(Workspace()) }
        do {
            let data = try Data(contentsOf: workspaceURL)
            let workspace = try TolerantDecoding.decodeWorkspace(data)
            return .loaded(workspace)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let moved = rootURL.appendingPathComponent("workspace-unreadable-\(stamp).json")
            try? fm.moveItem(at: workspaceURL, to: moved)
            // Fall back to the newest readable backup.
            for backup in backupFiles() {
                if let data = try? Data(contentsOf: backup), let ws = try? TolerantDecoding.decodeWorkspace(data) {
                    return .recovered(ws, movedTo: moved, error: error.localizedDescription)
                }
            }
            return .recovered(Workspace(), movedTo: moved, error: error.localizedDescription)
        }
    }

    func save(_ workspace: Workspace) throws {
        let data = try JSONCoding.prettyEncoder.encode(workspace)
        try data.write(to: workspaceURL, options: [.atomic])
    }

    /// Keeps one copy per day for the last `maxBackups` days.
    func makeDailyBackupIfNeeded(now: Date = Date()) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: workspaceURL.path) else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let target = backupsURL.appendingPathComponent("workspace-\(formatter.string(from: now)).json")
        if !fm.fileExists(atPath: target.path) {
            try? fm.copyItem(at: workspaceURL, to: target)
        }
        let files = backupFiles()
        if files.count > Persistence.maxBackups {
            for old in files.suffix(from: Persistence.maxBackups) { try? fm.removeItem(at: old) }
        }
    }

    /// Backups, newest first.
    func backupFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: backupsURL, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    // MARK: Media

    /// Copies an image into the Media folder and returns its stored file name.
    func importMedia(from source: URL) throws -> String {
        let ext = source.pathExtension.isEmpty ? "jpg" : source.pathExtension.lowercased()
        let name = "\(UUID().uuidString).\(ext)"
        try FileManager.default.copyItem(at: source, to: mediaURL.appendingPathComponent(name))
        return name
    }

    func mediaFile(_ name: String) -> URL { mediaURL.appendingPathComponent(name) }

    // MARK: Coverage files

    /// Saved pages and attachments for coverage live in Media/Coverage. They are never deleted when a
    /// coverage record is removed, so undoing the removal brings everything back.
    var coverageFilesURL: URL { mediaURL.appendingPathComponent("Coverage", isDirectory: true) }

    /// Stores a saved copy of a coverage page and returns its path inside the media folder.
    func saveCoverageCopy(_ html: String, for id: UUID) throws -> String {
        try FileManager.default.createDirectory(at: coverageFilesURL, withIntermediateDirectories: true)
        let name = "Coverage/\(id.uuidString)-page.html"
        try Data(html.utf8).write(to: mediaFile(name), options: [.atomic])
        return name
    }

    /// Copies a file (PDF, scan, screenshot, audio clip) to keep with a piece of coverage.
    func importCoverageAttachment(from source: URL) throws -> CoverageAttachment {
        try FileManager.default.createDirectory(at: coverageFilesURL, withIntermediateDirectories: true)
        let ext = source.pathExtension.lowercased()
        let name = "Coverage/\(UUID().uuidString)\(ext.isEmpty ? "" : "." + ext)"
        try FileManager.default.copyItem(at: source, to: mediaFile(name))
        return CoverageAttachment(fileName: name, originalName: source.lastPathComponent)
    }

    /// Keeps a downloaded file (a PDF the link pointed to) with a piece of coverage.
    func saveCoverageAttachment(_ data: Data, originalName: String) throws -> CoverageAttachment {
        try FileManager.default.createDirectory(at: coverageFilesURL, withIntermediateDirectories: true)
        let ext = (originalName as NSString).pathExtension.lowercased()
        let name = "Coverage/\(UUID().uuidString)\(ext.isEmpty ? "" : "." + ext)"
        try data.write(to: mediaFile(name), options: [.atomic])
        return CoverageAttachment(fileName: name, originalName: originalName)
    }

    func mediaFileExists(_ name: String) -> Bool {
        !name.isBlank && FileManager.default.fileExists(atPath: mediaFile(name).path)
    }

    static func mimeType(for fileName: String) -> String {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        default: return "image/jpeg"
        }
    }
}
