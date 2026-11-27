import AppKit
import Foundation
import UniformTypeIdentifiers

/// Actions shared by several screens. Each goes through `perform`, so it is logged and undoable.
extension AppModel {
    // MARK: Outreach (pitches, follow-ups, reminders)

    /// Saves a draft. If an approved or waiting message is edited, its approval no longer covers what
    /// would go out, so it goes back to draft and any pending request is withdrawn.
    func saveOutreach(_ draft: Outreach, requestApproval: Bool) {
        var item = draft
        let previous = workspace.outreach.first { $0.id == item.id }
        var approvalReset = false
        if let p = previous, p.status == .approved || p.status == .awaitingApproval {
            let changed = p.subject != item.subject || p.body != item.body || p.contactID != item.contactID || p.kind != item.kind
                || p.editorial != item.editorial
            if changed {
                item.status = .draft
                item.approvedAt = nil
                item.approvedByRule = nil
                approvalReset = true
            }
        }
        if requestApproval {
            self.requestApproval(forOutreach: item)
            return
        }
        let final = item
        perform(previous == nil ? "Drafted: \(final.subject)" : "Saved draft: \(final.subject)", kind: .draftMaterials,
                status: .drafted, detail: approvalReset ? "Edited after approval, so it needs approval again." : "", showUndo: true) { ws in
            ws.upsert(final, in: \.outreach)
            if approvalReset { ApprovalService.clearApprovalAfterEdit(subjectID: final.id, in: &ws) }
        }
        if approvalReset {
            showInfo("You edited an approved message, so it needs your approval again before it can be sent.")
        }
    }

    /// Opens an approved message in the artist's mail app. Nothing is sent from Manager.
    func openInMail(_ item: Outreach) {
        guard item.kind.isEmail else {
            NSWorkspace.shared.open(EditorialPitch.submitURL)
            return
        }
        guard item.status == .approved || item.status == .sent else {
            showError("Approve this message before opening it to send.")
            return
        }
        let email = workspace.contact(item.contactID)?.email ?? ""
        guard !email.isBlank else {
            showError("This contact has no email address. Add one in Contacts.")
            return
        }
        if MailDraft.open(to: email, subject: item.subject, body: item.body) {
            log("Opened “\(item.subject)” in your mail app", kind: item.kind.permission, status: .approved,
                detail: "Not sent by Manager. Mark it sent after you press Send.")
        } else {
            showError("Couldn't open your mail app. Copy the message instead.")
        }
    }

    /// The artist confirms they sent an approved message themselves.
    func markOutreachSent(_ id: UUID, on date: Date = Date()) {
        guard let item = workspace.outreach.first(where: { $0.id == id }), item.status == .approved else {
            showError("Only approved messages can be marked as sent.")
            return
        }
        let followUpDays = max(workspace.settings.followUpAfterDays, 1)
        let what = item.kind == .spotifyEditorial ? "Recorded as submitted to Spotify" : "Recorded as sent"
        perform("\(what): \(item.subject)", kind: item.kind.permission, detail: "You did this yourself.", showUndo: true) { ws in
            guard let i = ws.outreach.firstIndex(where: { $0.id == id }) else { return }
            ws.outreach[i].status = .sent
            ws.outreach[i].sentAt = date
            if ws.outreach[i].kind.isEmail && ws.outreach[i].kind != .reminder && ws.outreach[i].kind != .followUp {
                ws.outreach[i].followUpDue = date.adding(days: followUpDays)
            }
            if let contactID = item.contactID, let c = ws.contacts.firstIndex(where: { $0.id == contactID }) {
                ws.contacts[c].interactions.append(Interaction(date: date, channel: .email, summary: "Sent: \(item.subject)"))
            }
            // A follow-up that's been sent answers for its parent too.
            if let parent = item.parentID, let p = ws.outreach.firstIndex(where: { $0.id == parent }) {
                ws.outreach[p].followUpDue = nil
            }
        }
    }

    func recordOutreachResponse(_ id: UUID, status: OutreachStatus, notes: String) {
        guard let item = workspace.outreach.first(where: { $0.id == id }) else { return }
        perform("Recorded response: \(item.subject) — \(status.label)", showUndo: true) { ws in
            guard let i = ws.outreach.firstIndex(where: { $0.id == id }) else { return }
            ws.outreach[i].status = status
            ws.outreach[i].followUpDue = nil
            if !notes.isBlank { ws.outreach[i].responseNotes = notes }
            if (status == .replied || status == .covered), let contactID = item.contactID,
               let c = ws.contacts.firstIndex(where: { $0.id == contactID }) {
                ws.contacts[c].interactions.append(Interaction(date: Date(), channel: .email,
                                                               summary: "\(status.label): \(item.subject)\(notes.isBlank ? "" : " — \(notes)")"))
            }
        }
    }

    /// Adds one draft per contact, optionally asking for approval of all of them at once.
    func createPitchBatch(_ drafts: [Outreach], kind: OutreachKind, askForApproval: Bool) {
        guard !drafts.isEmpty else { return }
        let title = "Drafted \(drafts.count) \(kind.label.lowercased())\(drafts.count == 1 ? "" : "s")"
        perform(title, kind: askForApproval ? kind.permission : .draftMaterials,
                status: askForApproval ? .awaitingApproval : .drafted,
                detail: askForApproval ? "Each one is waiting for your approval in Approvals." : "Saved as drafts.", showUndo: true) { ws in
            for draft in drafts {
                ws.upsert(draft, in: \.outreach)
                if askForApproval { _ = ApprovalService.requestForOutreach(draft, in: &ws) }
            }
        }
    }

    func draftFollowUp(for id: UUID) {
        guard let original = workspace.outreach.first(where: { $0.id == id }) else { return }
        guard original.kind.isEmail else { return }
        if workspace.outreach.contains(where: { $0.parentID == id }) {
            showInfo("There's already a follow-up for this message.")
            return
        }
        var followUp = Drafting.followUp(for: original, contact: workspace.contact(original.contactID),
                                         release: workspace.release(original.releaseID),
                                         profile: workspace.profile, pressKit: workspace.pressKit)
        followUp.createdBy = .artist
        let draft = followUp
        perform("Drafted follow-up: \(draft.subject)", kind: .draftMaterials, status: .drafted, showUndo: true) { ws in
            ws.upsert(draft, in: \.outreach)
        }
    }

    func deleteOutreach(_ id: UUID) {
        guard let item = workspace.outreach.first(where: { $0.id == id }) else { return }
        perform("Deleted message: \(item.subject)", showUndo: true) { ws in
            ws.remove(id, from: \.outreach)
            ApprovalService.clearApprovalAfterEdit(subjectID: id, in: &ws)
        }
    }

    // MARK: Email campaigns

    func saveCampaign(_ draft: EmailCampaign, requestApproval: Bool) {
        var campaign = draft
        let previous = workspace.campaigns.first { $0.id == campaign.id }
        var approvalReset = false
        if let p = previous, [.approved, .awaitingApproval, .exported].contains(p.status) {
            let changed = p.subject != campaign.subject || p.preheader != campaign.preheader || p.body != campaign.body
                || p.segmentID != campaign.segmentID
            if changed {
                campaign.status = .draft
                campaign.approvedAt = nil
                campaign.approvedRecipientCount = 0
                campaign.exportedAt = nil
                approvalReset = true
            }
        }
        if requestApproval {
            self.requestApproval(forCampaign: campaign)
            return
        }
        let final = campaign
        perform(previous == nil ? "Drafted email: \(final.subject)" : "Saved email draft: \(final.subject)", kind: .draftMaterials,
                status: .drafted, detail: approvalReset ? "Edited after approval, so it needs approval again." : "", showUndo: true) { ws in
            ws.upsert(final, in: \.campaigns)
            if approvalReset { ApprovalService.clearApprovalAfterEdit(subjectID: final.id, in: &ws) }
        }
        if approvalReset {
            showInfo("You edited an approved email, so it needs your approval again before you send it.")
        }
    }

    /// Writes the approved campaign's content and recipients into a folder for the artist's email provider.
    func exportCampaign(_ id: UUID, to folder: URL) {
        guard let campaign = workspace.campaigns.first(where: { $0.id == id }),
              campaign.status == .approved || campaign.status == .exported else {
            showError("Approve the campaign before exporting it for sending.")
            return
        }
        let recipients = workspace.recipients(for: campaign.segmentID)
        let base = safeFileName(campaign.name.isBlank ? campaign.subject : campaign.name)
        do {
            try SubscriberExporter.sendableCSV(recipients).write(to: folder.appendingPathComponent("\(base) — recipients.csv"), atomically: true, encoding: .utf8)
            try SubscriberExporter.suppressionCSV(workspace.subscribers).write(to: folder.appendingPathComponent("\(base) — do not send.csv"), atomically: true, encoding: .utf8)
            try CampaignExport.html(campaign, profile: workspace.profile).write(to: folder.appendingPathComponent("\(base).html"), atomically: true, encoding: .utf8)
            try CampaignExport.plainText(campaign, profile: workspace.profile).write(to: folder.appendingPathComponent("\(base).txt"), atomically: true, encoding: .utf8)
        } catch {
            showError("Couldn't export the campaign: \(error.localizedDescription)")
            return
        }
        perform("Exported email “\(campaign.subject)” for your provider", kind: .exportData,
                detail: "\(recipients.count) recipients. Not sent — send it from your email provider.") { ws in
            if let i = ws.campaigns.firstIndex(where: { $0.id == id }), ws.campaigns[i].status == .approved {
                ws.campaigns[i].status = .exported
                ws.campaigns[i].exportedAt = Date()
            }
        }
        if campaign.approvedRecipientCount > 0 && recipients.count != campaign.approvedRecipientCount {
            showInfo("Exported to \(folder.lastPathComponent). Heads up: \(recipients.count) recipients now match, compared with \(campaign.approvedRecipientCount) when you approved it.")
        } else {
            showInfo("Exported to \(folder.lastPathComponent). Upload the recipients and suppression files to your provider, then send it there.")
        }
    }

    func markCampaignSent(_ id: UUID, on date: Date) {
        guard let campaign = workspace.campaigns.first(where: { $0.id == id }),
              campaign.status == .approved || campaign.status == .exported else {
            showError("Only approved campaigns can be recorded as sent.")
            return
        }
        perform("Recorded email as sent: \(campaign.subject)", kind: .sendEmailCampaign, detail: "Sent by you from your email provider.", showUndo: true) { ws in
            if let i = ws.campaigns.firstIndex(where: { $0.id == id }) {
                ws.campaigns[i].status = .sent
                ws.campaigns[i].sentAt = date
            }
        }
    }

    func cancelCampaign(_ id: UUID) {
        guard let campaign = workspace.campaigns.first(where: { $0.id == id }) else { return }
        perform("Cancelled email: \(campaign.subject)", showUndo: true) { ws in
            if let i = ws.campaigns.firstIndex(where: { $0.id == id }) { ws.campaigns[i].status = .cancelled }
            ApprovalService.clearApprovalAfterEdit(subjectID: id, in: &ws)
        }
    }

    // MARK: Files

    func safeFileName(_ raw: String) -> String {
        let cleaned = raw.map { ":/\\?%*|\"<>".contains($0) ? "-" : $0 }
        let name = String(cleaned).trimmed
        return name.isEmpty ? "Untitled" : String(name.prefix(80))
    }

    /// Asks where to save, then writes text and logs the export.
    func exportText(_ text: String, suggestedName: String, types: [UTType], logTitle: String) {
        guard let url = FilePanels.saveFile(name: suggestedName, types: types) else { return }
        writeText(text, to: url, logTitle: logTitle)
    }
}
