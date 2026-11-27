import Foundation

/// One piece of routine work the app could do on its own.
struct AutomationItem: Equatable {
    var kind: ActionKind
    var dedupeKey: String
    var title: String
    var detail: String
    var proposal: Proposal
}

/// Works out routine work from the current data. It never changes anything itself: the app applies
/// each item automatically or turns it into an approval request, depending on the artist's permissions.
enum AutomationEngine {
    static func plan(for ws: Workspace, now: Date = Date()) -> [AutomationItem] {
        var items: [AutomationItem] = []
        let policy = ws.permissions
        let today = now.startOfDay

        // 0. Housekeeping on existing records.
        let organize = Organizer.operations(for: ws, now: now)
        if !organize.isEmpty {
            let released = Organizer.releasesToMarkReleased(in: ws, now: now).map { "“\($0.title)”" }
            var detail: [String] = []
            if !released.isEmpty { detail.append("Mark \(released.joined(separator: ", ")) as released (the date has passed and it was delivered).") }
            if organize.contains(.tidyContactTags) { detail.append("Tidy contact tags.") }
            if organize.contains(.tidySubscriberTags) { detail.append("Tidy subscriber tags.") }
            items.append(AutomationItem(
                kind: .organizeData,
                dedupeKey: "organize:" + organize.map { op -> String in
                    if case .markReleased(let id) = op { return id.uuidString }
                    return op.label
                }.sorted().joined(separator: ",") + ":\(today.timeIntervalSince1970)",
                title: "Organize records",
                detail: detail.joined(separator: " "),
                proposal: Proposal(organize: organize)))
        }

        // 1. Release campaign timelines and release-day calendar entries.
        for release in ws.releases where release.stage.isActive {
            guard let date = release.releaseDate, date >= today.adding(days: -7) else { continue }
            let missing = ReleaseTimeline.missingTasks(for: release, existing: ws.tasks, actor: .automation)
            if !missing.isEmpty {
                items.append(AutomationItem(
                    kind: .createTasks, dedupeKey: "timeline:\(release.id):\(date.timeIntervalSince1970)",
                    title: "Create the campaign timeline for “\(release.title)”",
                    detail: "\(missing.count) dated tasks from masters through the 30-day review, based on a \(date.formatted(date: .abbreviated, time: .omitted)) release.",
                    proposal: Proposal(tasks: missing)))
            }
            if let event = ReleaseTimeline.releaseDayEvent(for: release, actor: .automation),
               !ws.events.contains(where: { $0.sourceKey == event.sourceKey }) {
                items.append(AutomationItem(
                    kind: .updateCalendar, dedupeKey: "release-day:\(release.id):\(date.timeIntervalSince1970)",
                    title: "Add “\(release.title)” release day to the calendar",
                    detail: date.formatted(date: .complete, time: .omitted),
                    proposal: Proposal(events: [event])))
            }
        }

        // 2. Follow-up drafts for pitches that got no reply.
        let followUpDays = max(ws.settings.followUpAfterDays, 1)
        let existingFollowUps = Set(ws.outreach.compactMap(\.parentID))
        var followUps: [Outreach] = []
        for item in ws.outreach where item.status == .sent && item.kind.isEmail && item.kind != .followUp && item.kind != .reminder {
            guard let sent = item.sentAt, Date.daysBetween(sent, today) >= followUpDays, !existingFollowUps.contains(item.id) else { continue }
            followUps.append(Drafting.followUp(for: item, contact: ws.contact(item.contactID), release: ws.release(item.releaseID),
                                               profile: ws.profile, pressKit: ws.pressKit, now: now))
        }
        if !followUps.isEmpty {
            let names = followUps.compactMap { ws.contact($0.contactID)?.displayName }.prefix(3).joined(separator: ", ")
            items.append(AutomationItem(
                kind: .draftMaterials, dedupeKey: "followups:" + followUps.compactMap(\.parentID).map(\.uuidString).sorted().joined(separator: ","),
                title: "Draft \(followUps.count) follow-up\(followUps.count == 1 ? "" : "s") for unanswered pitches",
                detail: (names.isEmpty ? "" : "To \(names). ") + "Drafts only — each needs your approval before it can be sent.",
                proposal: Proposal(outreach: followUps)))
        }

        // 3. Tasks for contact follow-up dates the artist set.
        var followUpTasks: [TaskItem] = []
        let taskKeys = Set(ws.tasks.compactMap(\.templateKey))
        for contact in ws.contacts {
            guard let date = contact.nextFollowUp, date <= today.adding(days: 7) else { continue }
            let key = "contact-followup:\(contact.id):\(date.startOfDay.timeIntervalSince1970)"
            guard !taskKeys.contains(key) else { continue }
            followUpTasks.append(TaskItem(title: "Follow up with \(contact.displayName)", notes: contact.followUpReason,
                                          due: date, area: .team, priority: .normal, contactID: contact.id,
                                          createdBy: .automation, templateKey: key, estimatedHours: 0.5))
        }
        if !followUpTasks.isEmpty {
            items.append(AutomationItem(
                kind: .createTasks, dedupeKey: "contact-followups:" + followUpTasks.compactMap(\.templateKey).sorted().joined(separator: ","),
                title: "Add \(followUpTasks.count) contact follow-up task\(followUpTasks.count == 1 ? "" : "s")",
                detail: followUpTasks.map(\.title).prefix(3).joined(separator: "; "),
                proposal: Proposal(tasks: followUpTasks)))
        }

        // 4. Reminders to people attached to upcoming shows, rehearsals, sessions and meetings.
        let lead = max(ws.settings.reminderLeadDays, 1)
        let reminderMode = policy.mode(for: .sendPreApprovedReminders)
        let reminderKeys = Set(ws.outreach.compactMap(\.templateKey))
        var reminders: [Outreach] = []
        for event in ws.events where [EventKind.show, .rehearsal, .studio, .meeting].contains(event.kind) {
            let days = Date.daysBetween(today, event.start)
            guard days >= 0, days <= lead else { continue }
            for contactID in event.contactIDs {
                guard let contact = ws.contact(contactID), !contact.email.isBlank else { continue }
                let key = "reminder:\(event.id):\(contactID)"
                guard !reminderKeys.contains(key) else { continue }
                let draft = Drafting.eventReminder(for: event, contact: contact, profile: ws.profile)
                var outreach = Outreach(kind: .reminder, contactID: contactID, releaseID: event.releaseID,
                                        subject: draft.subject, body: draft.body, status: .draft,
                                        createdAt: now, createdBy: .automation, templateKey: key)
                if reminderMode == .automatic {
                    outreach.status = .approved
                    outreach.approvedAt = now
                    outreach.approvedByRule = "Event reminder template (\(lead) day\(lead == 1 ? "" : "s") before)"
                }
                reminders.append(outreach)
            }
        }
        if !reminders.isEmpty && reminderMode != .off {
            items.append(AutomationItem(
                kind: .sendPreApprovedReminders, dedupeKey: "reminders:" + reminders.compactMap(\.templateKey).sorted().joined(separator: ","),
                title: "Prepare \(reminders.count) event reminder\(reminders.count == 1 ? "" : "s")",
                detail: reminderMode == .automatic
                    ? "Marked approved by your reminder template. You still send them — Manager can't send email for you yet."
                    : "Approve to mark them ready to send. You still send them.",
                proposal: Proposal(outreach: reminders)))
        }

        // 5. Plan refresh.
        let output = PlanGenerator.generate(for: ws, includeBudget: policy.mode(for: .trackBudget) != .off, now: now)
        let refresh = PlanGenerator.proposal(merging: output, into: ws.recommendations, now: now)
        if !refresh.isEmpty {
            let added = refresh.recommendations.filter { r in !ws.recommendations.contains { $0.ruleKey == r.ruleKey } }.count
            var parts: [String] = []
            if added > 0 { parts.append("\(added) new") }
            let updated = refresh.recommendations.count - added
            if updated > 0 { parts.append("\(updated) updated") }
            if !refresh.resolvedRuleKeys.isEmpty { parts.append("\(refresh.resolvedRuleKeys.count) no longer needed") }
            items.append(AutomationItem(
                kind: .refreshPlan, dedupeKey: "plan:" + output.activeRuleKeys.sorted().joined(separator: ","),
                title: "Refresh career plan recommendations",
                detail: parts.joined(separator: ", ").capitalizedFirst,
                proposal: refresh))
        }
        return items
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

// MARK: - Approvals

enum ApprovalService {
    /// Builds an approval request for sending a piece of outreach, and marks the outreach as waiting.
    static func requestForOutreach(_ item: Outreach, in ws: inout Workspace) -> ApprovalRequest {
        let contact = ws.contact(item.contactID)
        let title: String
        let preview: String
        if item.kind == .spotifyEditorial {
            let pitch = item.editorial ?? EditorialPitch()
            let release = ws.release(item.releaseID)
            title = "Submit “\(pitch.trackTitle.isBlank ? item.subject : pitch.trackTitle)” to Spotify's editors"
            var text = "Where: Spotify for Artists › Music › Upcoming › Pitch a song (you submit it)\n"
            if let date = release?.releaseDate { text += "Release: \(date.formatted(date: .abbreviated, time: .omitted))\n" }
            preview = text + "\n" + pitch.formText
        } else {
            let to = contact.map { "\($0.displayName) <\($0.email.isBlank ? "no email on file" : $0.email)>" } ?? "No recipient selected"
            title = "Send \(item.kind.label.lowercased()) to \(contact?.displayName ?? "recipient")"
            preview = "To: \(to)\nSubject: \(item.subject)\n\n\(item.body)"
        }
        let request = ApprovalRequest(
            kind: item.kind.permission,
            title: title,
            summary: item.subject,
            preview: preview,
            subjectKind: .outreach, subjectID: item.id, requestedBy: item.createdBy == .automation ? .automation : .artist)
        if let index = ws.outreach.firstIndex(where: { $0.id == item.id }) {
            ws.outreach[index].status = .awaitingApproval
        }
        supersedePending(subjectID: item.id, in: &ws)
        ws.approvals.append(request)
        return request
    }

    static func requestForCampaign(_ campaign: EmailCampaign, in ws: inout Workspace) -> ApprovalRequest {
        let recipients = ws.recipients(for: campaign.segmentID)
        let audience = ws.segment(campaign.segmentID)?.name ?? "All subscribed"
        let checks = CampaignLint.check(campaign, workspace: ws).filter { $0.level == .warning }
        var preview = "Audience: \(audience) — \(recipients.count) subscribed recipient\(recipients.count == 1 ? "" : "s")\n"
        if let date = campaign.scheduledFor { preview += "Planned send: \(date.formatted(date: .abbreviated, time: .shortened))\n" }
        preview += "Subject: \(campaign.subject)\n"
        if !campaign.preheader.isBlank { preview += "Preview text: \(campaign.preheader)\n" }
        preview += "\n\(campaign.body)"
        if !checks.isEmpty { preview += "\n\n— Checks —\n" + checks.map { "• \($0.message)" }.joined(separator: "\n") }
        let request = ApprovalRequest(
            kind: .sendEmailCampaign,
            title: "Send email “\(campaign.subject)” to \(recipients.count) subscriber\(recipients.count == 1 ? "" : "s")",
            summary: audience, preview: preview, subjectKind: .campaigns, subjectID: campaign.id, requestedBy: .artist)
        if let index = ws.campaigns.firstIndex(where: { $0.id == campaign.id }) {
            ws.campaigns[index].status = .awaitingApproval
        }
        supersedePending(subjectID: campaign.id, in: &ws)
        ws.approvals.append(request)
        return request
    }

    static func requestForSpend(_ line: BudgetLine, currency: String, in ws: inout Workspace) -> ApprovalRequest {
        let amount = Money.format(max(line.planned, line.actual), currency: currency)
        let release = ws.release(line.releaseID)
        let request = ApprovalRequest(
            kind: .spendMoney,
            title: "Spend \(amount) on \(line.title.isBlank ? line.category.label : line.title)",
            summary: [line.vendor, release?.title ?? ""].filter { !$0.isBlank }.joined(separator: " · "),
            preview: "Amount: \(amount)\nCategory: \(line.category.label)\nVendor: \(line.vendor.isBlank ? "—" : line.vendor)\(release.map { "\nRelease: \($0.title)" } ?? "")\n\n\(line.notes)",
            subjectKind: .budgetLines, subjectID: line.id, requestedBy: .artist)
        if let index = ws.budgetLines.firstIndex(where: { $0.id == line.id }) {
            ws.budgetLines[index].status = .awaitingApproval
        }
        supersedePending(subjectID: line.id, in: &ws)
        ws.approvals.append(request)
        return request
    }

    static func requestForAutomation(_ item: AutomationItem) -> ApprovalRequest {
        var preview = item.detail + "\n\n"
        preview += item.proposal.tasks.map { t in "• Task: \(t.title)\(t.due.map { " — due \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")" }.joined(separator: "\n")
        preview += item.proposal.events.map { "\n• Event: \($0.title) — \($0.start.formatted(date: .abbreviated, time: .omitted))" }.joined()
        if item.kind == .sendPreApprovedReminders {
            // Approving these marks them ready to send, so show exactly what each one says.
            preview += item.proposal.outreach.map { "\n\n— Reminder —\nSubject: \($0.subject)\n\n\($0.body)" }.joined()
        } else {
            preview += item.proposal.outreach.map { "\n• Draft: \($0.subject)" }.joined()
        }
        preview += item.proposal.recommendations.map { "\n• Recommendation: \($0.title)" }.joined()
        preview += (item.proposal.organize ?? []).map { "\n• \($0.label)" }.joined()
        return ApprovalRequest(kind: item.kind, title: item.title, summary: item.proposal.summary, preview: preview.trimmed,
                               proposal: item.proposal, requestedBy: .automation, dedupeKey: item.dedupeKey)
    }

    private static func supersedePending(subjectID: UUID, in ws: inout Workspace) {
        for i in ws.approvals.indices where ws.approvals[i].subjectID == subjectID && ws.approvals[i].state == .pending {
            ws.approvals[i].state = .superseded
            ws.approvals[i].decidedAt = Date()
        }
    }

    /// Applies the artist's approval. Nothing is sent from here: the subject moves to "approved — not sent".
    static func approve(_ id: UUID, note: String = "", in ws: inout Workspace, now: Date = Date()) {
        guard let index = ws.approvals.firstIndex(where: { $0.id == id }), ws.approvals[index].state == .pending else { return }
        let request = ws.approvals[index]
        ws.approvals[index].state = .approved
        ws.approvals[index].decidedAt = now
        ws.approvals[index].decisionNote = note
        if let proposal = request.proposal {
            proposal.apply(to: &ws, now: now)
            // Approving a reminder suggestion approves the reminders it showed, so they're ready to send.
            if request.kind == .sendPreApprovedReminders {
                let ids = Set(proposal.outreach.map(\.id))
                for i in ws.outreach.indices where ids.contains(ws.outreach[i].id) && ws.outreach[i].status == .draft {
                    ws.outreach[i].status = .approved
                    ws.outreach[i].approvedAt = now
                    ws.outreach[i].approvedByRule = "Approved by you in Approvals"
                }
            }
        }
        guard let subjectID = request.subjectID else { return }
        switch request.subjectKind {
        case .outreach?:
            if let i = ws.outreach.firstIndex(where: { $0.id == subjectID }) {
                ws.outreach[i].status = .approved
                ws.outreach[i].approvedAt = now
            }
        case .campaigns?:
            if let i = ws.campaigns.firstIndex(where: { $0.id == subjectID }) {
                ws.campaigns[i].status = .approved
                ws.campaigns[i].approvedAt = now
                ws.campaigns[i].approvedRecipientCount = ws.recipients(for: ws.campaigns[i].segmentID).count
            }
        case .budgetLines?:
            if let i = ws.budgetLines.firstIndex(where: { $0.id == subjectID }) {
                ws.budgetLines[i].status = .approved
            }
        default:
            break
        }
    }

    /// Approves several pending requests together. Each is still recorded as its own decision.
    static func approveAll(_ ids: [UUID], note: String = "", in ws: inout Workspace, now: Date = Date()) {
        for id in ids { approve(id, note: note, in: &ws, now: now) }
    }

    static func decline(_ id: UUID, note: String = "", in ws: inout Workspace, now: Date = Date()) {
        guard let index = ws.approvals.firstIndex(where: { $0.id == id }), ws.approvals[index].state == .pending else { return }
        let request = ws.approvals[index]
        ws.approvals[index].state = .declined
        ws.approvals[index].decidedAt = now
        ws.approvals[index].decisionNote = note
        guard let subjectID = request.subjectID else { return }
        switch request.subjectKind {
        case .outreach?:
            if let i = ws.outreach.firstIndex(where: { $0.id == subjectID }) { ws.outreach[i].status = .draft }
        case .campaigns?:
            if let i = ws.campaigns.firstIndex(where: { $0.id == subjectID }) { ws.campaigns[i].status = .draft }
        case .budgetLines?:
            if let i = ws.budgetLines.firstIndex(where: { $0.id == subjectID }) { ws.budgetLines[i].status = .planned }
        default:
            break
        }
    }

    /// When an approved item is edited, its approval no longer covers what will be sent.
    static func clearApprovalAfterEdit(subjectID: UUID, in ws: inout Workspace) {
        supersedePending(subjectID: subjectID, in: &ws)
    }
}
