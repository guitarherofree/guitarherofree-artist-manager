import AppKit
import Foundation

/// A target being added or edited, with what Manager found on its website. Nothing is saved until the artist saves.
struct TargetDraft: Identifiable {
    var target: Target
    var findings = Targets.PageFindings()
    var problem: String? = nil
    var id: UUID { target.id }
}

extension AppModel {
    var targetsDueCount: Int {
        let today = Date().startOfDay
        return workspace.targets.filter { Targets.isDue($0, today: today) }.count
    }

    func newTargetDraft(kind: TargetKind = .publication) -> TargetDraft {
        var t = Target(kind: kind)
        t.createdAt = Date()
        return TargetDraft(target: t)
    }

    /// Reads a target's website: name, what it is, and any submission page or address. Nothing is saved.
    func lookUpTarget(_ link: String, now: Date = Date()) async -> TargetDraft {
        var typed = link.trimmed
        if !typed.lowercased().hasPrefix("http") { typed = "https://" + typed }
        do {
            let page = try await LinkFetcher.fetch(typed)
            guard page.isHTML else {
                var t = Target(website: Targets.siteRoot(typed))
                t.name = LinkReader.outletName(fromURL: typed)
                return TargetDraft(target: t, problem: "That link is a file, not a web page.")
            }
            let data = page.data, type = page.contentType, address = page.finalURL
            let (meta, findings) = await Task.detached(priority: .userInitiated) { () -> (LinkMetadata, Targets.PageFindings) in
                let html = LinkReader.decodeText(data, contentType: type)
                return (LinkReader.parse(html: html, url: address), Targets.findings(html: html, baseURL: address))
            }.value
            return TargetDraft(target: Targets.target(from: meta, findings: findings, now: now), findings: findings)
        } catch {
            var t = Target(website: Targets.siteRoot(typed))
            t.name = LinkReader.outletName(fromURL: typed)
            t.createdAt = now
            return TargetDraft(target: t, problem: error.localizedDescription)
        }
    }

    @discardableResult
    func saveTarget(_ t: Target) -> Target {
        var target = t
        if target.createdAt == nil { target.createdAt = Date() }
        let exists = workspace.targets.contains { $0.id == target.id }
        let saved = target
        perform(exists ? "Updated target: \(saved.displayName)" : "Added target: \(saved.displayName)", showUndo: true) { ws in
            ws.upsert(saved, in: \.targets)
        }
        return saved
    }

    func deleteTarget(_ t: Target) {
        perform("Removed target: \(t.displayName)", showUndo: true) { $0.remove(t.id, from: \.targets) }
    }

    func setTargetStatus(_ id: UUID, to status: TargetStatus) {
        guard let t = workspace.targets.first(where: { $0.id == id }) else { return }
        perform("\(t.displayName): \(status.label(for: t.kind))", showUndo: true) { ws in
            if let i = ws.targets.firstIndex(where: { $0.id == id }) { ws.targets[i].status = status }
        }
    }

    /// Records that the artist looked at a target today, and when to look again (nil for no reminder).
    func markTargetChecked(_ id: UUID, lookAgainInDays days: Int?, now: Date = Date()) {
        guard let t = workspace.targets.first(where: { $0.id == id }) else { return }
        let next = days.map { now.startOfDay.adding(days: $0) }
        perform("Checked on \(t.displayName)", detail: next.map { "Look again \($0.shortDate)." } ?? "No reminder set.", showUndo: true) { ws in
            guard let i = ws.targets.firstIndex(where: { $0.id == id }) else { return }
            ws.targets[i].lastChecked = now
            ws.targets[i].nextCheck = next
        }
    }

    func addTargets(_ targets: [Target], title: String) {
        guard !targets.isEmpty else { return }
        let now = Date()
        perform(title, kind: .organizeData, detail: targets.prefix(5).map(\.displayName).joined(separator: ", "), showUndo: true) { ws in
            for var t in targets {
                if t.createdAt == nil { t.createdAt = now }
                ws.upsert(t, in: \.targets)
            }
        }
    }

    func importTargets(_ preview: TargetImportPreview, fileName: String) {
        guard preview.hasChanges else {
            showInfo(preview.duplicates.isEmpty ? "Nothing to import from \(fileName)." : "Everything in \(fileName) is already on your list.")
            return
        }
        var detail = "\(preview.added.count) added"
        if !preview.duplicates.isEmpty { detail += ", \(preview.duplicates.count) already on your list" }
        if !preview.skipped.isEmpty { detail += ", \(preview.skipped.count) skipped" }
        perform("Imported targets from \(fileName)", kind: .importData, actor: .importer, detail: detail + ".", showUndo: true) { ws in
            ws.targets.append(contentsOf: preview.added)
        }
    }

    /// Turns a target's submission address into a contact, so pitches can be drafted to it.
    @discardableResult
    func addSubmissionContact(for id: UUID) -> UUID? {
        guard let t = workspace.targets.first(where: { $0.id == id }), !t.submissionEmail.isBlank else { return nil }
        if let existing = workspace.contacts.first(where: { $0.email.caseInsensitiveCompare(t.submissionEmail) == .orderedSame }) {
            if !t.contactIDs.contains(existing.id) {
                perform("Linked \(existing.displayName) to \(t.displayName)", showUndo: true) { ws in
                    if let i = ws.targets.firstIndex(where: { $0.id == id }) { ws.targets[i].contactIDs.append(existing.id) }
                }
            }
            return existing.id
        }
        var contact = Contact(name: "", organization: t.name, role: t.kind.contactRole, email: t.submissionEmail)
        contact.website = t.website
        contact.location = t.location
        contact.tags = ["Submissions"]
        contact.notes = t.guidelines
        let c = contact
        perform("Added \(t.displayName)'s submission address as a contact", showUndo: true) { ws in
            ws.contacts.append(c)
            if let i = ws.targets.firstIndex(where: { $0.id == id }) { ws.targets[i].contactIDs.append(c.id) }
        }
        return c.id
    }

    func exportTargetsCSV() -> String { TargetCSV.export(workspace.targets) }
}
