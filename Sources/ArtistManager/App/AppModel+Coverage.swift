import AppKit
import Foundation

/// A file the coverage link itself pointed to, such as a PDF of a print feature.
struct CoverageDocument {
    var data: Data
    var name: String
}

/// Coverage being added or edited, with whatever Manager found at the link. Nothing is saved until the artist saves.
struct CoverageDraft: Identifiable {
    var coverage: Coverage
    /// A copy of the page, ready to keep.
    var snapshot: String? = nil
    var document: CoverageDocument? = nil
    /// Why the page couldn't be read. The record is still usable; the artist fills in the rest.
    var problem: String? = nil
    var keepCopy = true
    var id: UUID { coverage.id }
}

struct CoverageLinkCheck {
    var checked = 0
    var working = 0
    var broken: [String] = []
    var unreachable: [String] = []
}

extension AppModel {
    private static let linkShorteners: Set<String> = ["bit.ly", "t.co", "lnkd.in", "ow.ly", "buff.ly", "tinyurl.com", "spoti.fi",
                                                      "apple.co", "fb.me", "trib.al", "dlvr.it", "smarturl.it", "found.ee", "g.co"]

    func newCoverageDraft(kind: CoverageKind = .review) -> CoverageDraft {
        var c = Coverage(date: Date().startOfDay, kind: kind)
        c.includeInPressKit = kind != .mention && kind != .playlistAdd
        c.addedAt = Date()
        return CoverageDraft(coverage: c, keepCopy: false)
    }

    /// Reads a link and returns a filled-in draft. Nothing is saved.
    func lookUpCoverage(_ link: String, now: Date = Date()) async -> CoverageDraft {
        var typed = link.trimmed
        if !typed.lowercased().hasPrefix("http") { typed = "https://" + typed }
        do {
            let page = try await LinkFetcher.fetch(typed)
            var host = URL(string: typed)?.host?.lowercased() ?? ""
            if host.hasPrefix("www.") { host.removeFirst(4) }
            let address = Self.linkShorteners.contains(host) ? page.finalURL : typed
            var c: Coverage
            var draft: CoverageDraft
            if page.isHTML {
                // Reading a large page takes a moment; keep it off the main thread so the window stays responsive.
                let data = page.data, type = page.contentType
                let (meta, snapshot) = await Task.detached(priority: .userInitiated) { () -> (LinkMetadata, String) in
                    let html = LinkReader.decodeText(data, contentType: type)
                    return (LinkReader.parse(html: html, url: address), CoverageArchive.snapshot(html: html, url: address, savedAt: now))
                }.value
                c = CoverageLinks.coverage(from: meta, now: now)
                draft = CoverageDraft(coverage: c, snapshot: snapshot)
            } else {
                c = Coverage()
                c.url = address
                c.outlet = LinkReader.outletName(fromURL: address)
                c.kind = CoverageLinks.guessKind(url: address, title: "")
                c.verified = true
                c.linkCheckedAt = now
                c.addedAt = now
                let last = URL(string: page.finalURL)?.lastPathComponent ?? ""
                let name = last.contains(".") ? last : "\(c.outlet.isBlank ? "Coverage" : c.outlet).\(page.contentType.contains("pdf") ? "pdf" : "dat")"
                c.title = (name as NSString).deletingPathExtension.replacingOccurrences(of: "-", with: " ")
                draft = CoverageDraft(coverage: c, document: CoverageDocument(data: page.data, name: name))
            }
            CoverageLinks.suggestLinks(for: &draft.coverage, releases: workspace.releases, contacts: workspace.contacts, outreach: workspace.outreach)
            return draft
        } catch {
            var c = Coverage()
            c.url = typed
            c.outlet = LinkReader.outletName(fromURL: typed)
            c.kind = CoverageLinks.guessKind(url: typed, title: "")
            c.includeInPressKit = c.kind != .mention && c.kind != .playlistAdd
            c.addedAt = now
            if let fetchError = error as? LinkFetcher.FetchError, fetchError.meansLinkIsBroken {
                c.linkIssue = fetchError.localizedDescription
                c.linkCheckedAt = now
            }
            CoverageLinks.suggestLinks(for: &c, releases: workspace.releases, contacts: workspace.contacts, outreach: workspace.outreach)
            return CoverageDraft(coverage: c, problem: error.localizedDescription, keepCopy: false)
        }
    }

    /// Writes the copy and any downloaded file, then saves the record (logged and undoable).
    @discardableResult
    func saveCoverage(_ draft: CoverageDraft) -> Coverage {
        var c = draft.coverage
        var failed: [String] = []
        if draft.keepCopy, c.savedCopy == nil, let snapshot = draft.snapshot {
            do { c.savedCopy = try persistence.saveCoverageCopy(snapshot, for: c.id) } catch { failed.append("a copy of the page") }
        }
        if let doc = draft.document, !c.attachments.contains(where: { $0.originalName == doc.name }) {
            do { c.attachments.append(try persistence.saveCoverageAttachment(doc.data, originalName: doc.name)) } catch { failed.append(doc.name) }
        }
        let exists = workspace.coverage.contains { $0.id == c.id }
        perform(exists ? "Updated coverage: \(c.headline)" : "Saved coverage: \(c.headline)", showUndo: true) { ws in
            ws.upsert(c, in: \.coverage)
            ws.markPitchCovered(by: c)
        }
        if !failed.isEmpty { showError("Saved \(c.headline), but couldn't keep \(failed.joined(separator: " or ")).") }
        return c
    }

    func saveCoverageBatch(_ drafts: [CoverageDraft]) {
        guard !drafts.isEmpty else { return }
        var saved: [Coverage] = []
        var failed = 0
        for draft in drafts {
            var c = draft.coverage
            if draft.keepCopy, let snapshot = draft.snapshot {
                if let name = try? persistence.saveCoverageCopy(snapshot, for: c.id) { c.savedCopy = name } else { failed += 1 }
            }
            if let doc = draft.document {
                if let a = try? persistence.saveCoverageAttachment(doc.data, originalName: doc.name) { c.attachments.append(a) } else { failed += 1 }
            }
            saved.append(c)
        }
        let unread = drafts.filter { $0.problem != nil }.count
        perform("Added \(saved.count) piece\(saved.count == 1 ? "" : "s") of coverage", kind: .importData,
                detail: unread == 0 ? "" : "\(unread) couldn't be read and need details filled in.", showUndo: true) { ws in
            for c in saved {
                ws.upsert(c, in: \.coverage)
                ws.markPitchCovered(by: c)
            }
        }
        if failed > 0 { showError("Added the coverage, but \(failed) saved cop\(failed == 1 ? "y" : "ies") couldn't be written.") }
    }

    func importCoverage(_ preview: CoverageImportPreview, fileName: String) {
        guard preview.hasChanges else {
            showInfo(preview.duplicates.isEmpty ? "Nothing to import from \(fileName)." : "Everything in \(fileName) is already saved.")
            return
        }
        var detail = "\(preview.added.count) added"
        if !preview.duplicates.isEmpty { detail += ", \(preview.duplicates.count) already saved" }
        if !preview.skipped.isEmpty { detail += ", \(preview.skipped.count) skipped" }
        perform("Imported coverage from \(fileName)", kind: .importData, actor: .importer, detail: detail + ".", showUndo: true) { ws in
            ws.coverage.append(contentsOf: preview.added)
        }
    }

    func addCoverageAttachments(from urls: [URL], to coverage: inout Coverage) {
        var failed: [String] = []
        for url in urls {
            do { coverage.attachments.append(try persistence.importCoverageAttachment(from: url)) } catch { failed.append(url.lastPathComponent) }
        }
        if !failed.isEmpty { showError("Couldn't copy \(failed.joined(separator: ", ")).") }
    }

    func openCoverageFile(_ name: String) {
        let url = persistence.mediaFile(name)
        guard persistence.mediaFileExists(name) else {
            showError("That file is missing from Manager's media folder.")
            return
        }
        NSWorkspace.shared.open(url)
    }

    func revealCoverageFile(_ name: String) {
        guard persistence.mediaFileExists(name) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([persistence.mediaFile(name)])
    }

    /// Opens each link once and records whether the page is still there. Reads only; nothing is sent or posted.
    func checkCoverageLinks(_ ids: [UUID], now: Date = Date()) async -> CoverageLinkCheck {
        var result = CoverageLinkCheck()
        var updates: [UUID: (ok: Bool, issue: String)] = [:]
        for id in ids {
            guard let c = workspace.coverage.first(where: { $0.id == id }), !c.url.isBlank else { continue }
            result.checked += 1
            do {
                _ = try await LinkFetcher.fetch(c.url)
                result.working += 1
                updates[id] = (true, "")
            } catch let error as LinkFetcher.FetchError where error.meansLinkIsBroken {
                result.broken.append(c.headline)
                updates[id] = (false, error.localizedDescription)
            } catch {
                result.unreachable.append(c.headline)
            }
        }
        guard !updates.isEmpty else { return result }
        var detail = "\(result.working) working"
        if !result.broken.isEmpty { detail += ", \(result.broken.count) not found" }
        if !result.unreachable.isEmpty { detail += ", \(result.unreachable.count) couldn't be checked" }
        perform(result.checked == 1 ? "Checked a coverage link" : "Checked \(result.checked) coverage links",
                kind: .organizeData, detail: detail + ".") { ws in
            for (id, outcome) in updates {
                guard let i = ws.coverage.firstIndex(where: { $0.id == id }) else { continue }
                ws.coverage[i].linkCheckedAt = now
                ws.coverage[i].linkIssue = outcome.issue
                ws.coverage[i].verified = outcome.ok
            }
        }
        return result
    }

    func exportCoverageCSV() -> String {
        CoverageCSV.export(workspace.coverage, releases: workspace.releases)
    }
}
