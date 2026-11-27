import Foundation

/// Turns the artist's goals and current data into next-step recommendations.
///
/// Rules are deterministic and each one explains itself, so the artist can see why something is
/// suggested. Recommendations are suggestions only; nothing here performs work.
enum PlanGenerator {
    struct Output {
        var recommendations: [Recommendation]
        var activeRuleKeys: Set<String>
    }

    static func generate(for ws: Workspace, includeBudget: Bool = true, now: Date = Date()) -> Output {
        var recs: [Recommendation] = []
        let today = now.startOfDay
        let profile = ws.profile
        let goalCategories = Set(ws.goals.filter { $0.status != .achieved && $0.status != .paused }.map(\.category))

        func add(_ key: String, _ title: String, _ detail: String, why: String, area: WorkArea, priority: Priority = .normal,
                 destination: AppDestination, tab: String? = nil, due: Date? = nil, related: UUID? = nil) {
            var rec = Recommendation(ruleKey: key, title: title, detail: detail, rationale: why, area: area,
                                     priority: priority, destination: destination, suggestedDue: due, relatedID: related)
            rec.destinationTab = tab
            recs.append(rec)
        }

        // Foundations
        if profile.artistName.isBlank || profile.bioShort.isBlank || profile.genres.isEmpty {
            add("profile-basics", "Finish your artist profile",
                "Add your artist name, genres and a short bio. Pitches, the press kit and email drafts all pull from it.",
                why: "Most of what Manager drafts for you starts from your profile.", area: .strategy, priority: .high,
                destination: .profile, due: today.adding(days: 3))
        }
        if ws.goals.isEmpty {
            add("set-goals", "Set one to three goals for the next 12 months",
                "Pick measurable goals (for example, “Reach 1,000 email subscribers by June”). Recommendations are ranked against them.",
                why: "Without goals, the plan can only suggest generic housekeeping.", area: .strategy, priority: .high,
                destination: .plan, due: today.adding(days: 3))
        }
        for goal in ws.goals where goal.status != .achieved && goal.status != .paused {
            guard let target = goal.targetDate else { continue }
            let days = Date.daysBetween(today, target)
            if days < 0 {
                add("goal-overdue-\(goal.id)", "Review your goal “\(goal.title)”",
                    "The target date has passed. Mark it achieved, set a new date, or pause it.",
                    why: "Goals past their date stop being useful for prioritizing.", area: .strategy, destination: .plan, related: goal.id)
            } else if days <= 30 && goal.status == .notStarted {
                add("goal-start-\(goal.id)", "Start on “\(goal.title)”",
                    "This goal is due in \(days) day\(days == 1 ? "" : "s") and hasn't been started.",
                    why: "It's close to its target date.", area: .strategy, priority: .high, destination: .plan, related: goal.id)
            }
        }

        // Press kit
        let epk = PressKitScore.evaluate(ws)
        if epk.score < 0.8 {
            add("epk-complete", "Complete your press kit (\(Int(epk.score * 100))% done)",
                "Missing: " + epk.missing.prefix(4).joined(separator: "; ") + (epk.missing.count > 4 ? "; and \(epk.missing.count - 4) more." : "."),
                why: "Press, curators, bookers and brands look for a complete EPK before they reply.", area: .press,
                priority: goalCategories.contains(.press) || goalCategories.contains(.live) ? .high : .normal,
                destination: .press, due: today.adding(days: 14))
        }

        // Releases
        let upcoming = ws.releases.filter { r in
            guard r.stage.isActive, let d = r.releaseDate else { return false }
            return d >= today
        }
        let wantsReleases = goalCategories.contains(.streaming) || goalCategories.contains(.audience) || goalCategories.contains(.creative)
        if wantsReleases && !upcoming.contains(where: { Date.daysBetween(today, $0.releaseDate!) <= 120 }) {
            let suggested = today.adding(days: 56).nextOccurrence(ofWeekday: 6)
            add("next-release", "Schedule your next release",
                "Nothing is scheduled in the next four months. A single on \(suggested.formatted(date: .abbreviated, time: .omitted)) leaves eight weeks for a full campaign.",
                why: "Steady releases support your streaming and audience goals.", area: .release, priority: .high,
                destination: .releases, due: today.adding(days: 7))
        }
        for release in upcoming {
            let date = release.releaseDate!
            let daysOut = Date.daysBetween(today, date)
            let hasTimeline = ReleaseTimeline.hasTimeline(release.id, tasks: ws.tasks)
            if !hasTimeline {
                add("timeline-\(release.id)", "Generate the campaign timeline for “\(release.title)”",
                    "Creates dated tasks from masters to release-day follow-ups, based on a \(release.type.label.lowercased()) campaign.",
                    why: "The release is \(daysOut) days out and has no campaign tasks yet.", area: .release, priority: .high,
                    destination: .releases, due: today, related: release.id)
            } else if let generatedFor = release.timelineGeneratedFor, !generatedFor.isSameDay(as: date) {
                add("reschedule-\(release.id)", "Update the campaign dates for “\(release.title)”",
                    "The release date changed since its timeline was made. Reschedule the open tasks to match.",
                    why: "Task due dates are based on the old release date.", area: .release, priority: .high,
                    destination: .releases, due: today, related: release.id)
            }
            let blocking = MetadataValidator.issues(for: release).filter { $0.severity == .blocking }
            if daysOut <= 49 && !blocking.isEmpty {
                add("metadata-\(release.id)", "Fix \(blocking.count) metadata issue\(blocking.count == 1 ? "" : "s") on “\(release.title)”",
                    blocking.prefix(3).map(\.message).joined(separator: " "),
                    why: "Distributors reject or delay releases with incomplete metadata, and errors are hard to fix after delivery.",
                    area: .release, priority: daysOut <= 35 ? .high : .normal, destination: .releases,
                    due: date.adding(days: -42), related: release.id)
            }
            let pitched = ws.outreach.contains { $0.kind == .spotifyEditorial && $0.releaseID == release.id && $0.status != .draft }
            if daysOut >= EditorialPitch.minimumLeadDays && daysOut <= 70 && !pitched {
                let deadline = EditorialPitch.deadline(for: date)
                add("spotify-pitch-\(release.id)", "Pitch “\(release.title)” to Spotify's editors",
                    "Fill in the Spotify for Artists pitch form here, approve it, then submit it in Spotify for Artists. Last day to reach your followers' Release Radar: \(deadline.formatted(date: .abbreviated, time: .omitted)).",
                    why: "Editorial playlists and Release Radar are the biggest free reach on Spotify, and pitches are only taken before release.",
                    area: .marketing, priority: daysOut <= 35 ? .high : .normal, destination: .press, tab: "playlists",
                    due: max(today, EditorialPitch.recommendedDate(for: date)), related: release.id)
            }
            let reviewPitches = ws.outreach.filter { $0.kind == .review && $0.releaseID == release.id }.count
            let critics = ws.contacts.filter { $0.role == .journalist }.count
            if daysOut <= 49 && daysOut >= 10 && reviewPitches == 0 && (goalCategories.contains(.press) || critics > 0) {
                add("review-pitches-\(release.id)", "Pitch “\(release.title)” for reviews",
                    critics > 0
                        ? "Draft review requests to the \(critics) writer\(critics == 1 ? "" : "s") in your contacts in one go. Each needs your approval before it goes out."
                        : "Import or add writers and outlets that review your genre, then draft review requests to them in one go.",
                    why: "Reviewers plan weeks ahead; four to six weeks before release gives them time to listen.",
                    area: .press, destination: .press, tab: "outreach",
                    due: max(today, date.adding(days: -35)), related: release.id)
            }
            if daysOut <= 30 && !ws.pressReleases.contains(where: { $0.releaseID == release.id }) {
                add("press-release-\(release.id)", "Draft a press release for “\(release.title)”",
                    "Generate a draft from the release and your bio, then edit it.",
                    why: "Press outreach usually starts three to four weeks before release.", area: .press,
                    destination: .press, tab: "releases", due: date.adding(days: -24), related: release.id)
            }
            if daysOut <= 21 && !ws.campaigns.contains(where: { $0.releaseID == release.id }) && !ws.subscribers.isEmpty {
                add("email-\(release.id)", "Draft an email announcement for “\(release.title)”",
                    "Your subscribers should hear about it first. The draft needs your approval before it can be sent.",
                    why: "Your email list is the audience you own.", area: .email,
                    destination: .email, due: date.adding(days: -10), related: release.id)
            }
            if includeBudget {
                let summary = BudgetMath.summary(for: release, lines: ws.budgetLines)
                if release.budget <= 0 && profile.budget.monthlyMarketingBudget > 0 {
                    add("budget-\(release.id)", "Set a budget for “\(release.title)”",
                        "Add a total and planned costs (mixing, mastering, artwork, ads, PR).",
                        why: "You have a marketing budget, but this release has no spending plan.", area: .finance,
                        destination: .releases, related: release.id)
                } else if summary.isOver {
                    add("over-budget-\(release.id)", "“\(release.title)” is over budget",
                        "Planned costs are \(Money.format(max(summary.planned, summary.committed), currency: profile.budget.currency)) against a budget of \(Money.format(release.budget, currency: profile.budget.currency)).",
                        why: "Spending past the plan is easier to fix before money is committed.", area: .finance, priority: .high,
                        destination: .releases, related: release.id)
                }
            }
        }
        if includeBudget && profile.budget.annualBudget > 0 {
            let annual = BudgetMath.annualSummary(lines: ws.budgetLines, annualBudget: profile.budget.annualBudget, now: now)
            if annual.isOver {
                add("annual-budget", "You're over your annual budget",
                    "Planned and committed spending in the last 12 months is \(Money.format(max(annual.planned, annual.committed), currency: profile.budget.currency)).",
                    why: "Your annual budget is \(Money.format(profile.budget.annualBudget, currency: profile.budget.currency)).",
                    area: .finance, priority: .high, destination: .releases)
            }
        }

        // Rights and royalties
        let memberships = profile.rightsMemberships
        func has(_ type: RightsOrgType) -> Bool { memberships.contains { $0.type == type && $0.status != .notStarted } }
        if !has(.performingRights) && !has(.publisherAdmin) {
            add("rights-pro", "Affiliate with a performing rights organization",
                profile.isUnitedStates
                    ? "As a songwriter in the US, that's ASCAP, BMI, SESAC (invite-only) or GMR (invite-only). Record it in Profile › Rights."
                    : "Join your country's PRO as a songwriter, then record it in Profile › Rights.",
                why: "Performance royalties for your songs can't be paid to you until you're a member and your songs are registered.",
                area: .rights, priority: ws.releases.isEmpty ? .normal : .high, destination: .profile)
        }
        if !has(.mechanical) && !has(.publisherAdmin) {
            add("rights-mechanical", "Set up mechanical royalty collection",
                profile.isUnitedStates
                    ? "In the US, streaming mechanicals are collected by The MLC. Self-published songwriters can register directly or through a publishing administrator."
                    : "Register with your country's mechanical rights society or a publishing administrator.",
                why: "Streaming services pay mechanical royalties for compositions separately from performance royalties.",
                area: .rights, destination: .profile)
        }
        if !has(.neighboringRights) {
            add("rights-neighboring", "Register your recordings for digital performance royalties",
                profile.isUnitedStates
                    ? "In the US that's SoundExchange (for non-interactive streams like satellite and internet radio)."
                    : "Register with your country's neighboring rights organization.",
                why: "These royalties go to recording artists and rights owners and aren't collected by your distributor.",
                area: .rights, destination: .profile)
        }

        // Team
        let roles = Set(ws.contacts.filter(\.isTeamMember).map(\.role))
        if (goalCategories.contains(.deals) || goalCategories.contains(.revenue)) && !roles.contains(.attorney) {
            add("team-attorney", "Find an entertainment attorney before signing agreements",
                "Add one on the Team page, even if you only use them per agreement.",
                why: "Your goals include deals or income, which usually means contracts.", area: .team, destination: .team)
        }
        if goalCategories.contains(.live) {
            let bookers = ws.contacts.filter { [.venue, .promoter, .bookingAgent].contains($0.role) }.count
            if bookers < 5 {
                add("live-targets", "Build a target list of venues and promoters",
                    "You have \(bookers). Aim for 10–20 rooms that fit your draw in your top markets\(profile.audience.topMarkets.isBlank ? "" : " (\(profile.audience.topMarkets))").",
                    why: "You have a live goal.", area: .live, destination: .contacts)
            }
        }
        let staleTeam = ws.teamMembers.filter { member in
            guard let last = member.lastContacted else { return true }
            return Date.daysBetween(last, today) > ws.settings.teamCheckInDays
        }
        if !staleTeam.isEmpty {
            add("team-checkin", "Check in with \(staleTeam.count) team member\(staleTeam.count == 1 ? "" : "s")",
                staleTeam.prefix(4).map(\.displayName).joined(separator: ", ") + " — no logged conversation in \(ws.settings.teamCheckInDays)+ days.",
                why: "Regular check-ins keep work moving without a manager in the middle.", area: .team, destination: .team)
        }
        let dueFollowUps = ws.contacts.filter { ($0.nextFollowUp ?? .distantFuture) <= today.adding(days: 1) }
        if !dueFollowUps.isEmpty {
            add("contact-followups", "Follow up with \(dueFollowUps.count) contact\(dueFollowUps.count == 1 ? "" : "s")",
                dueFollowUps.prefix(4).map(\.displayName).joined(separator: ", "),
                why: "You set follow-up dates that are due.", area: .team, priority: .high,
                destination: dueFollowUps.allSatisfy(\.isTeamMember) ? .team : .contacts, due: today)
        }

        // Legacy: who looks after the music, and where everything is
        if !LegacyReadiness.releasedReleases(ws, now: now).isEmpty {
            if !LegacyReadiness.hasStarted(ws.legacy) {
                add("legacy-start", "Start a legacy plan for your music",
                    "Choose who would look after your catalog, and write down where your masters, documents and accounts are. It takes about half an hour.",
                    why: "Your released music keeps earning. Without a plan, the people you leave behind may not know what exists or how to reach it.",
                    area: .rights, priority: .low, destination: .legacy)
            } else if LegacyReadiness.isReviewDue(ws.legacy, now: now) && ws.legacy.lastReviewed != nil {
                add("legacy-review", "Review your legacy plan",
                    "Check the people, accounts and file locations are still right, and add anything new since last time.",
                    why: "You asked to review it every \(ws.legacy.reviewEveryMonths) months.", area: .rights, priority: .low, destination: .legacy)
            }
        }

        // Coverage
        for release in ws.releases {
            guard let date = release.releaseDate else { continue }
            let since = Date.daysBetween(date.startOfDay, today)
            let pitched = ws.outreach.contains { o in
                o.releaseID == release.id && [.review, .press, .radio, .playlist].contains(o.kind)
                    && [.sent, .replied, .covered].contains(o.status)
            }
            if (7...60).contains(since) && pitched && !ws.coverage.contains(where: { $0.releaseID == release.id }) {
                add("coverage-log-\(release.id)", "Save the coverage for “\(release.title)”",
                    "Paste links to any reviews, interviews, radio plays or mentions. Manager fills in the details and keeps a copy of each page.",
                    why: "Links break and pages change. Saving coverage while it's fresh keeps a record you can quote later.",
                    area: .press, priority: .low, destination: .coverage, related: release.id)
            }
        }
        let needQuotes = ws.coverage.filter { $0.includeInPressKit && $0.quote.isBlank && $0.kind != .playlistAdd }
        if !needQuotes.isEmpty {
            add("coverage-quotes", "Pick pull quotes for \(needQuotes.count) piece\(needQuotes.count == 1 ? "" : "s") of coverage",
                needQuotes.prefix(3).map(\.headline).joined(separator: "; "),
                why: "A short quote with the outlet's name is what press kits and pitches lead with.",
                area: .press, priority: .low, destination: .coverage)
        }
        let lost = ws.coverage.filter { !$0.linkIssue.isBlank && $0.savedCopy == nil && $0.attachments.isEmpty }
        if !lost.isEmpty {
            add("coverage-broken", "\(lost.count) coverage link\(lost.count == 1 ? " no longer works" : "s no longer work")",
                lost.prefix(3).map(\.headline).joined(separator: "; ") + ". There's no saved copy. Attach a PDF or screenshot if you have one, or take it out of your press kit.",
                why: "A broken link in a press kit sends writers and bookers to an error page.",
                area: .press, priority: lost.contains(where: \.includeInPressKit) ? .high : .normal, destination: .coverage)
        }

        // Targets: publications, labels and others the artist is watching
        let dueTargets = ws.targets.filter { Targets.isDue($0, today: today) }
            .sorted { ($0.nextCheck ?? .distantPast) < ($1.nextCheck ?? .distantPast) }
        if !dueTargets.isEmpty {
            add("targets-check", "Look in on \(dueTargets.count) target\(dueTargets.count == 1 ? "" : "s") you're watching",
                dueTargets.prefix(4).map(\.displayName).joined(separator: ", "),
                why: "You set a date to check on them — a submission window, a new issue, a roster change.",
                area: dueTargets.allSatisfy(\.kind.isMedia) ? .press : .strategy, destination: .targets, due: today)
        }
        let ready = ws.targets.filter { $0.status == .ready }.map { ($0, Targets.activity(for: $0, in: ws)) }
        let noWayIn = ready.filter { !Targets.hasWayIn($0.0, activity: $0.1) }.map(\.0)
        if !noWayIn.isEmpty {
            add("targets-way-in", "Find who to pitch at \(noWayIn.prefix(3).map(\.displayName).joined(separator: ", "))\(noWayIn.count > 3 ? " and \(noWayIn.count - 3) more" : "")",
                "Add a person who works there, their submission address, or their submission form.",
                why: "You marked \(noWayIn.count == 1 ? "it" : "them") ready to pitch, but there's no way to reach \(noWayIn.count == 1 ? "it" : "them") yet.",
                area: noWayIn.allSatisfy(\.kind.isMedia) ? .press : .strategy, destination: .targets)
        }
        let readyToGo = ready.filter { Targets.hasWayIn($0.0, activity: $0.1) && $0.1.pitches.isEmpty }.map(\.0)
        if !readyToGo.isEmpty {
            add("targets-ready", "Pitch the \(readyToGo.count) target\(readyToGo.count == 1 ? "" : "s") you marked ready",
                readyToGo.prefix(4).map(\.displayName).joined(separator: ", ") + ". Each pitch needs your approval before it goes out.",
                why: "You marked \(readyToGo.count == 1 ? "it" : "them") ready to pitch and there's a way in.",
                area: readyToGo.allSatisfy(\.kind.isMedia) ? .press : .strategy, destination: .targets)
        }

        // Email audience
        let subscribed = ws.subscribers.filter { $0.status == .subscribed }
        if ws.subscribers.isEmpty {
            add("email-start", "Start your email list",
                "Import your existing list (from your email provider or a merch-table sheet), or add a signup link to your bio and site.",
                why: "Email reaches fans directly, without an algorithm deciding who sees it.", area: .email,
                priority: goalCategories.contains(.audience) ? .high : .normal, destination: .email)
        } else {
            let lastSent = ws.campaigns.compactMap(\.sentAt).max()
            if lastSent == nil || Date.daysBetween(lastSent!, today) > 60, subscribed.count > 0 {
                add("email-cadence", "Send your list an update",
                    lastSent == nil ? "You haven't recorded a campaign yet." : "Your last recorded campaign was over 60 days ago.",
                    why: "Lists that hear from you regularly stay engaged and deliverable.", area: .email, destination: .email)
            }
            let hygiene = ListHygiene.report(ws.subscribers, now: now)
            if !hygiene.subscribedWithoutConsent.isEmpty || !hygiene.invalidAddresses.isEmpty || !hygiene.likelyTypos.isEmpty {
                add("email-hygiene", "Review \(hygiene.issueCount) list hygiene issue\(hygiene.issueCount == 1 ? "" : "s")",
                    "\(hygiene.subscribedWithoutConsent.count) without a consent record, \(hygiene.invalidAddresses.count) invalid, \(hygiene.likelyTypos.count) likely typos.",
                    why: "Clean, consented lists protect your sender reputation.", area: .email, destination: .email)
            }
        }

        // Workload and approvals
        let load = CalendarService.workload(in: ws, now: now)
        if load.hoursAvailable > 0 && load.hoursDue > load.hoursAvailable * 1.2 {
            add("workload", "This week has more work than time",
                "About \(Int(load.hoursDue.rounded())) hours of tasks are due in the next 7 days; you set \(Int(load.hoursAvailable)) hours a week.",
                why: "Move or drop lower-priority tasks so the important ones get done.", area: .admin, priority: .high,
                destination: .tasks, due: today)
        }
        let pending = ws.pendingApprovals.count
        if pending > 0 {
            add("approvals", "Review \(pending) item\(pending == 1 ? "" : "s") waiting for approval",
                "Nothing waiting for approval goes out until you decide.",
                why: "Approvals unblock pitches, campaigns and spending.", area: .admin, priority: .high, destination: .approvals, due: today)
        }

        let ranked = recs.sorted { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            return (a.suggestedDue ?? .distantFuture) < (b.suggestedDue ?? .distantFuture)
        }
        return Output(recommendations: ranked, activeRuleKeys: Set(ranked.map(\.ruleKey)))
    }

    /// Merges fresh output into existing recommendations, keeping the artist's decisions (accepted, done, dismissed).
    static func proposal(merging output: Output, into existing: [Recommendation], now: Date = Date()) -> Proposal {
        var proposal = Proposal()
        let byKey = Dictionary(existing.map { ($0.ruleKey, $0) }, uniquingKeysWith: { a, _ in a })
        for fresh in output.recommendations {
            if var current = byKey[fresh.ruleKey] {
                let reopened = current.status == .resolved
                if current.title != fresh.title || current.detail != fresh.detail || current.priority != fresh.priority
                    || current.destinationTab != fresh.destinationTab || reopened {
                    current.destinationTab = fresh.destinationTab
                    current.title = fresh.title
                    current.detail = fresh.detail
                    current.rationale = fresh.rationale
                    current.priority = fresh.priority
                    current.suggestedDue = fresh.suggestedDue
                    if reopened { current.status = .open }
                    current.updatedAt = now
                    proposal.recommendations.append(current)
                }
            } else {
                proposal.recommendations.append(fresh)
            }
        }
        for rec in existing where (rec.status == .open || rec.status == .accepted) && !output.activeRuleKeys.contains(rec.ruleKey) {
            proposal.resolvedRuleKeys.append(rec.ruleKey)
        }
        return proposal
    }

    /// Milestones for the plan timeline: goals with dates, release days, and key campaign tasks.
    static func milestones(for ws: Workspace) -> [Milestone] {
        var items: [Milestone] = []
        for goal in ws.goals {
            items.append(Milestone(id: "goal-\(goal.id)", title: goal.title, date: goal.targetDate, area: .strategy,
                                   isComplete: goal.status == .achieved))
        }
        for release in ws.releases where release.stage != .archived {
            items.append(Milestone(id: "release-\(release.id)", title: "Release: \(release.title)", date: release.releaseDate,
                                   area: .release, isComplete: release.stage == .released))
            for task in ws.tasks where task.priority == .high && ReleaseTimeline.isTimelineTask(task, release: release.id) {
                items.append(Milestone(id: "task-\(task.id)", title: task.title, date: task.due, area: task.area,
                                       isComplete: task.status == .done))
            }
        }
        return items.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
}

extension Proposal {
    /// Adds the proposed records, skipping any that already exist (by template / source key).
    func apply(to ws: inout Workspace, now: Date = Date()) {
        let taskKeys = Set(ws.tasks.compactMap(\.templateKey))
        for task in tasks where task.templateKey == nil || !taskKeys.contains(task.templateKey!) {
            ws.upsert(task, in: \.tasks)
        }
        let eventKeys = Set(ws.events.compactMap(\.sourceKey))
        for event in events where event.sourceKey == nil || !eventKeys.contains(event.sourceKey!) {
            ws.upsert(event, in: \.events)
        }
        let outreachKeys = Set(ws.outreach.compactMap(\.templateKey))
        for item in outreach where item.templateKey == nil || !outreachKeys.contains(item.templateKey!) {
            ws.upsert(item, in: \.outreach)
        }
        for rec in recommendations {
            if let index = ws.recommendations.firstIndex(where: { $0.ruleKey == rec.ruleKey }) {
                var updated = rec
                updated.id = ws.recommendations[index].id
                ws.recommendations[index] = updated
            } else {
                ws.recommendations.append(rec)
            }
        }
        for key in resolvedRuleKeys {
            if let index = ws.recommendations.firstIndex(where: { $0.ruleKey == key }),
               ws.recommendations[index].status == .open || ws.recommendations[index].status == .accepted {
                ws.recommendations[index].status = .resolved
                ws.recommendations[index].updatedAt = now
            }
        }
        for operation in organize ?? [] {
            Organizer.apply(operation, to: &ws, now: now)
        }
    }
}

// MARK: - Organizing records

enum Organizer {
    /// Trimmed, non-empty tags with case-insensitive duplicates removed (first spelling wins).
    static func tidy(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let t = tag.trimmed
            guard !t.isEmpty, !seen.contains(t.lowercased()) else { continue }
            seen.insert(t.lowercased())
            result.append(t)
        }
        return result
    }

    static func releasesToMarkReleased(in ws: Workspace, now: Date) -> [Release] {
        ws.releases.filter { release in
            guard release.stage == .delivered, let date = release.releaseDate else { return false }
            return date.startOfDay < now.startOfDay
        }
    }

    static func operations(for ws: Workspace, now: Date = Date()) -> [OrganizeOperation] {
        var ops: [OrganizeOperation] = releasesToMarkReleased(in: ws, now: now).map { .markReleased($0.id) }
        if ws.contacts.contains(where: { tidy($0.tags) != $0.tags }) { ops.append(.tidyContactTags) }
        if ws.subscribers.contains(where: { tidy($0.tags) != $0.tags }) { ops.append(.tidySubscriberTags) }
        return ops
    }

    static func apply(_ operation: OrganizeOperation, to ws: inout Workspace, now: Date) {
        switch operation {
        case .markReleased(let id):
            if let i = ws.releases.firstIndex(where: { $0.id == id }), ws.releases[i].stage == .delivered,
               let date = ws.releases[i].releaseDate, date.startOfDay < now.startOfDay {
                ws.releases[i].stage = .released
            }
        case .tidyContactTags:
            for i in ws.contacts.indices { ws.contacts[i].tags = tidy(ws.contacts[i].tags) }
        case .tidySubscriberTags:
            for i in ws.subscribers.indices { ws.subscribers[i].tags = tidy(ws.subscribers[i].tags) }
        }
    }
}

// MARK: - Press kit completeness

struct PressKitScore {
    var score: Double
    var missing: [String]

    static func evaluate(_ ws: Workspace) -> PressKitScore {
        let p = ws.profile, kit = ws.pressKit
        let checks: [(Bool, String)] = [
            (!p.artistName.isBlank, "artist name"),
            (!p.bioShort.isBlank, "short bio"),
            (!p.bioLong.isBlank, "full bio"),
            (!p.genres.isEmpty, "genres"),
            (!kit.headline.isBlank, "one-line description"),
            (!kit.photos.isEmpty, "press photos"),
            (kit.photos.contains(where: { !$0.photographerCredit.isBlank }), "photo credits"),
            (!p.links.labeled.isEmpty || !kit.featuredTracks.isEmpty, "music links"),
            (!kit.bookingContact.email.isBlank, "booking contact"),
            (!kit.publicityContact.email.isBlank, "publicity contact"),
            (ws.coverage.contains(where: { $0.includeInPressKit }) || !kit.achievements.isBlank, "press quotes or highlights"),
            (!kit.credits.isBlank, "credits")
        ]
        let met = checks.filter { $0.0 }.count
        return PressKitScore(score: Double(met) / Double(checks.count), missing: checks.filter { !$0.0 }.map { $0.1 })
    }
}
