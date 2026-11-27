import AppKit
import Foundation

/// Imports, media and log exports. Each change goes through `perform`, so it is logged and undoable.
extension AppModel {
    // MARK: Imports

    func importSubscribers(_ preview: SubscriberImportPreview, fileName: String) {
        guard preview.hasChanges else {
            showInfo("Nothing to import: every address in \(fileName) is already up to date.")
            return
        }
        var detail = "\(preview.added.count) added, \(preview.updated.count) updated"
        if !preview.suppressionsKept.isEmpty {
            detail += ", \(preview.suppressionsKept.count) kept unsubscribed or bounced"
        }
        if !preview.newlySuppressed.isEmpty {
            detail += ", \(preview.newlySuppressed.count) newly unsubscribed or bounced"
        }
        perform("Imported subscribers from \(fileName)", kind: .importData, actor: .importer,
                detail: detail + ".", showUndo: true) { ws in
            SubscriberImporter.apply(preview, to: &ws.subscribers)
        }
    }

    func importContacts(_ preview: ContactImportPreview, fileName: String) {
        guard preview.hasChanges else {
            showInfo("Nothing to import from \(fileName).")
            return
        }
        perform("Imported contacts from \(fileName)", kind: .importData, actor: .importer,
                detail: "\(preview.added.count) added, \(preview.updated.count) filled in. Existing details were not overwritten.",
                showUndo: true) { ws in
            ContactCSV.apply(preview, to: &ws.contacts)
        }
    }

    /// Reads an .ics file and adds events that aren't already here (matched by their calendar UID).
    func importCalendar(from url: URL) {
        do {
            let text = try FilePanels.readText(url)
            let parsed = ICalendar.parse(text)
            let events = ICalendar.calendarEvents(from: parsed, existing: workspace.events)
            guard !events.isEmpty else {
                showInfo(parsed.isEmpty ? "No events found in \(url.lastPathComponent)." : "All \(parsed.count) events in \(url.lastPathComponent) are already on your calendar.")
                return
            }
            perform("Imported \(events.count) calendar event\(events.count == 1 ? "" : "s") from \(url.lastPathComponent)",
                    kind: .importData, actor: .importer, detail: "\(parsed.count - events.count) already here and skipped.", showUndo: true) { ws in
                ws.events.append(contentsOf: events)
            }
        } catch {
            showError("Couldn't read \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Applies a provider's per-recipient report: delivery stats on the campaign, and bounces,
    /// unsubscribes and complaints on subscribers. Never re-subscribes anyone.
    func applyCampaignResults(_ result: CampaignResultsImport, to campaignID: UUID) {
        guard let campaign = workspace.campaigns.first(where: { $0.id == campaignID }) else { return }
        let name = campaign.name.isBlank ? campaign.subject : campaign.name
        let suppressions = result.statusUpdates.count
        perform("Imported results for “\(name)”", kind: .importData, actor: .importer,
                detail: "\(result.results.delivered) delivered, \(result.results.bounces) bounced, \(result.results.unsubscribes) unsubscribed. \(suppressions) subscriber status change\(suppressions == 1 ? "" : "s").",
                showUndo: true) { ws in
            if let i = ws.campaigns.firstIndex(where: { $0.id == campaignID }) {
                ws.campaigns[i].results = result.results
            }
            CampaignResultsImporter.apply(result, to: &ws.subscribers, campaignName: name)
        }
    }

    // MARK: Press photos

    /// Copies chosen images into Manager's media folder. Returns the new photo records.
    func copyPressPhotos(from urls: [URL]) -> [PressPhoto] {
        var photos: [PressPhoto] = []
        var failed: [String] = []
        for url in urls {
            do {
                let name = try persistence.importMedia(from: url)
                photos.append(PressPhoto(fileName: name))
            } catch {
                failed.append(url.lastPathComponent)
            }
        }
        if !failed.isEmpty {
            showError("Couldn't copy \(failed.joined(separator: ", ")).")
        }
        return photos
    }

    func photoData(_ photo: PressPhoto) -> (data: Data, mime: String)? {
        guard let data = try? Data(contentsOf: persistence.mediaFile(photo.fileName)) else { return nil }
        return (data, Persistence.mimeType(for: photo.fileName))
    }

    /// Writes the press kit to a temporary file and opens it in the default browser.
    func previewPressKit() {
        let html = PressKitRenderer.htmlDocument(workspace: workspace, photoData: { self.photoData($0) })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeFileName(workspace.profile.displayName)) Press Kit Preview.html")
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
        } catch {
            showError("Couldn't open the preview: \(error.localizedDescription)")
        }
    }

    // MARK: Activity log

    func activityLogCSV() -> String {
        let formatter = ISO8601DateFormatter()
        let rows = workspace.actionLog.reversed().map { record -> [String] in
            [formatter.string(from: record.date), record.title, record.detail, record.actor.label, record.status.label,
             record.kind.label, String(record.changes.count), record.undoneBy == nil ? "" : "yes"]
        }
        return CSV.write(headers: ["date", "action", "detail", "by", "status", "type", "records_changed", "undone"], rows: rows)
    }
}
