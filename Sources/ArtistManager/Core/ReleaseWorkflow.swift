import Foundation

/// One step of a release campaign, scheduled relative to release day.
struct TimelineStep {
    var key: String
    var offsetDays: Int        // negative = before release day
    var title: String
    var notes: String
    var area: WorkArea
    var priority: Priority = .normal
    var needsApprovalToSend = false
    var hours: Double = 1
}

enum ReleaseTimeline {
    /// Default campaign for a single. EPs and albums stretch the pre-release lead time.
    static let singleSteps: [TimelineStep] = [
        TimelineStep(key: "masters", offsetDays: -56, title: "Approve final mixes and masters",
                     notes: "Get WAV masters (24-bit) and instrumental/clean versions if needed.", area: .creative, priority: .high, hours: 3),
        TimelineStep(key: "artwork", offsetDays: -49, title: "Finalize cover artwork",
                     notes: "Most distributors want a square 3000 × 3000 px RGB JPG or PNG with no URLs, prices or social handles.", area: .creative, priority: .high, hours: 2),
        TimelineStep(key: "metadata", offsetDays: -45, title: "Complete release metadata and credits",
                     notes: "Titles, versions, ISRCs, explicit flags, songwriter splits, producers and featured artists. Check the Metadata tab for gaps.", area: .release, priority: .high, hours: 2),
        TimelineStep(key: "distributor", offsetDays: -35, title: "Upload release to your distributor",
                     notes: "Leave 2–4 weeks for stores to receive it, and longer for editorial pitching.", area: .release, priority: .high, hours: 2),
        TimelineStep(key: "register-works", offsetDays: -30, title: "Register the songs with your PRO and mechanical collector",
                     notes: "Register compositions and splits so performance and mechanical royalties can be matched.", area: .rights, hours: 1),
        TimelineStep(key: "review-pitches", offsetDays: -35, title: "Pitch the release for reviews",
                     notes: "Use Press Kit › Pitches › Pitch Several to draft review requests to writers and outlets in one go. Each needs your approval before it goes out.", area: .press, needsApprovalToSend: true, hours: 2),
        TimelineStep(key: "editorial-pitch", offsetDays: -28, title: "Pitch the song to Spotify's editors",
                     notes: "Fill in the pitch in Press Kit › Playlists, approve it, then submit it in Spotify for Artists (Music › Upcoming). One song per release; at least 7 days before release to reach followers' Release Radar.", area: .marketing, priority: .high, needsApprovalToSend: true, hours: 1),
        TimelineStep(key: "press-release", offsetDays: -26, title: "Draft the press release",
                     notes: "Use Press Kit › Press releases to generate a draft from this release.", area: .press, hours: 2),
        TimelineStep(key: "smart-link", offsetDays: -24, title: "Set up pre-save / smart link",
                     notes: "Add the link to the release so it flows into pitches, the press kit and email drafts.", area: .marketing, hours: 1),
        TimelineStep(key: "press-outreach", offsetDays: -21, title: "Send press and blog pitches",
                     notes: "Draft pitches from the Press Kit › Outreach tab. Each one needs your approval before it goes out.", area: .press, priority: .high, needsApprovalToSend: true, hours: 3),
        TimelineStep(key: "content-plan", offsetDays: -18, title: "Plan teaser content",
                     notes: "Plan 3–5 short clips, a behind-the-scenes post and the announcement post. Add them to the calendar.", area: .marketing, hours: 2),
        TimelineStep(key: "announce", offsetDays: -14, title: "Announce the release",
                     notes: "Announcement post with the pre-save link. Publishing needs your go-ahead.", area: .marketing, needsApprovalToSend: true, hours: 1),
        TimelineStep(key: "email-announce", offsetDays: -10, title: "Draft the email announcement",
                     notes: "Draft in Email List › Campaigns; it needs your approval before it can be exported to your provider.", area: .email, needsApprovalToSend: true, hours: 1),
        TimelineStep(key: "curator-outreach", offsetDays: -7, title: "Pitch independent playlist curators",
                     notes: "Use Press Kit › Playlists › Pitch Curators to draft a note to each curator in one go. Only pitch curators who accept submissions.", area: .marketing, needsApprovalToSend: true, hours: 2),
        TimelineStep(key: "release-day", offsetDays: 0, title: "Release day: post, update links, send email",
                     notes: "Update the press kit and bio links, post, and send the approved email campaign.", area: .marketing, priority: .high, needsApprovalToSend: true, hours: 2),
        TimelineStep(key: "follow-ups", offsetDays: 7, title: "Follow up on unanswered pitches",
                     notes: "Manager drafts follow-ups for pitches with no reply. Review and approve them.", area: .press, hours: 1),
        TimelineStep(key: "neighboring", offsetDays: 14, title: "Confirm sound recording registrations",
                     notes: "Make sure the recordings are registered for digital performance / neighboring rights royalties.", area: .rights, hours: 1),
        TimelineStep(key: "retro", offsetDays: 30, title: "Review results and update the plan",
                     notes: "Streams, saves, playlist adds, coverage, list growth, and spend vs. budget.", area: .strategy, hours: 1)
    ]

    static let extendedSteps: [TimelineStep] = [
        TimelineStep(key: "rollout-plan", offsetDays: -120, title: "Plan the singles rollout",
                     notes: "Pick focus tracks and dates for each single leading up to the project.", area: .strategy, priority: .high, hours: 2),
        TimelineStep(key: "first-single", offsetDays: -90, title: "Release the first focus single",
                     notes: "Create a separate single release for it so it gets its own campaign.", area: .release, priority: .high, hours: 1)
    ]

    static func steps(for type: ReleaseType) -> [TimelineStep] {
        let scaled = singleSteps.map { step -> TimelineStep in
            var s = step
            if s.offsetDays < 0 {
                s.offsetDays = Int((Double(s.offsetDays) * type.leadTimeMultiplier).rounded())
            }
            return s
        }
        return type == .single ? scaled : extendedSteps + scaled
    }

    static func templateKey(release: UUID, step: String) -> String { "release:\(release.uuidString):\(step)" }

    /// True for tasks generated from this release's campaign timeline (not tasks the artist linked by hand).
    static func isTimelineTask(_ task: TaskItem, release: UUID) -> Bool {
        task.releaseID == release && (task.templateKey?.hasPrefix("release:\(release.uuidString):") ?? false)
    }

    static func hasTimeline(_ release: UUID, tasks: [TaskItem]) -> Bool {
        tasks.contains { isTimelineTask($0, release: release) }
    }

    /// Tasks for the release's campaign that don't exist yet.
    static func missingTasks(for release: Release, existing: [TaskItem], actor: Actor) -> [TaskItem] {
        guard let date = release.releaseDate else { return [] }
        let existingKeys = Set(existing.compactMap(\.templateKey))
        return steps(for: release.type).compactMap { step in
            let key = templateKey(release: release.id, step: step.key)
            guard !existingKeys.contains(key) else { return nil }
            var notes = step.notes
            if step.needsApprovalToSend {
                notes += "\n\nAnything that goes out for this step needs your approval first."
            }
            return TaskItem(title: "\(step.title) — \(release.title)", notes: notes,
                            due: date.startOfDay.adding(days: step.offsetDays), area: step.area,
                            priority: step.priority, releaseID: release.id, createdBy: actor,
                            templateKey: key, estimatedHours: step.hours)
        }
    }

    /// Moves open, generated tasks when the release date changes. Finished tasks keep their dates.
    static func rescheduled(tasks: [TaskItem], for release: Release) -> [TaskItem] {
        guard let date = release.releaseDate else { return tasks }
        let byKey = Dictionary(uniqueKeysWithValues: steps(for: release.type).map {
            (templateKey(release: release.id, step: $0.key), $0)
        })
        return tasks.map { task in
            guard task.releaseID == release.id, task.isOpen, let key = task.templateKey, let step = byKey[key] else { return task }
            var t = task
            t.due = date.startOfDay.adding(days: step.offsetDays)
            return t
        }
    }

    static func releaseDayKey(_ release: UUID) -> String { "release-day:\(release.uuidString)" }

    static func releaseDayEvent(for release: Release, actor: Actor) -> CalendarEvent? {
        guard let date = release.releaseDate else { return nil }
        return CalendarEvent(title: "Release day: \(release.title)", kind: .release, start: date.startOfDay,
                             end: date.startOfDay, isAllDay: true, notes: "\(release.type.label) release",
                             releaseID: release.id, createdBy: actor, sourceKey: releaseDayKey(release.id))
    }
}

// MARK: - Metadata checks

struct MetadataIssue: Identifiable, Equatable {
    enum Severity: String { case blocking, warning }
    var id: String
    var severity: Severity
    var message: String
}

enum MetadataValidator {
    /// ISRC: 2-letter country, 3-character registrant, 2-digit year, 5-digit designation (12 characters).
    static func isValidISRC(_ raw: String) -> Bool {
        let code = raw.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "").uppercased()
        guard code.count == 12 else { return false }
        let chars = Array(code)
        let letters = chars[0...1].allSatisfy { $0.isLetter && $0.isASCII }
        let registrant = chars[2...4].allSatisfy { ($0.isLetter || $0.isNumber) && $0.isASCII }
        let digits = chars[5...11].allSatisfy { $0.isNumber && $0.isASCII }
        return letters && registrant && digits
    }

    /// UPC-A (12 digits) or EAN-13 (13 digits).
    static func isValidUPC(_ raw: String) -> Bool {
        let code = raw.trimmed
        return (code.count == 12 || code.count == 13) && code.allSatisfy { $0.isNumber && $0.isASCII }
    }

    static func issues(for release: Release) -> [MetadataIssue] {
        var issues: [MetadataIssue] = []
        func add(_ id: String, _ severity: MetadataIssue.Severity, _ message: String) {
            issues.append(MetadataIssue(id: id, severity: severity, message: message))
        }
        if release.title.isBlank { add("title", .blocking, "The release needs a title.") }
        if release.releaseDate == nil { add("date", .blocking, "Pick a release date.") }
        if let date = release.releaseDate, date.weekday != 6 {
            add("friday", .warning, "Most releases go out on a Friday (the global release day). This one isn't on a Friday.")
        }
        if release.distributor.isBlank { add("distributor", .warning, "Add the distributor you'll deliver through.") }
        if release.primaryGenre.isBlank { add("genre", .warning, "Add a primary genre — distributors require one.") }
        if release.artworkStatus != .final { add("artwork", .blocking, "Cover artwork isn't marked final.") }
        if !release.upc.isBlank && !isValidUPC(release.upc) {
            add("upc", .blocking, "The UPC should be 12 or 13 digits.")
        }
        if release.tracks.isEmpty { add("tracks", .blocking, "Add at least one track.") }
        if release.type == .single && release.tracks.count > 3 {
            add("single-length", .warning, "Many stores treat releases with more than 3 tracks as EPs.")
        }
        for (index, track) in release.tracks.enumerated() {
            let name = track.title.isBlank ? "Track \(index + 1)" : "“\(track.title)”"
            let tid = track.id.uuidString
            if track.title.isBlank { add("\(tid)-title", .blocking, "Track \(index + 1) needs a title.") }
            if track.isrc.isBlank {
                add("\(tid)-isrc", .warning, "\(name) has no ISRC. Your distributor can assign one, but record it here once you have it.")
            } else if !isValidISRC(track.isrc) {
                add("\(tid)-isrc-format", .blocking, "\(name): the ISRC should look like CC-XXX-YY-NNNNN (12 characters).")
            }
            if track.writers.isEmpty {
                add("\(tid)-writers", .blocking, "\(name) has no songwriters listed.")
            } else if abs(track.splitTotal - 100) > 0.01 {
                add("\(tid)-splits", .blocking, "\(name): songwriter splits add up to \(track.splitTotal.formatted(.number.precision(.fractionLength(0...2))))%, not 100%.")
            }
            if track.writers.contains(where: { $0.name.isBlank }) {
                add("\(tid)-writer-name", .blocking, "\(name) has a songwriter with no name.")
            }
            if !track.mastered { add("\(tid)-master", .warning, "\(name) isn't marked as mastered.") }
            if track.durationSeconds <= 0 { add("\(tid)-duration", .warning, "\(name) has no duration.") }
        }
        return issues
    }
}

// MARK: - Budgets

struct BudgetSummary: Equatable {
    var planned: Double
    var committed: Double
    var paid: Double
    var budget: Double

    var remaining: Double { budget - max(planned, committed) }
    var isOver: Bool { budget > 0 && max(planned, committed) > budget }
}

enum BudgetMath {
    static func summary(for release: Release, lines: [BudgetLine]) -> BudgetSummary {
        let relevant = lines.filter { $0.releaseID == release.id && $0.status.countsTowardSpend }
        return summarize(relevant, budget: release.budget)
    }

    static func summarize(_ lines: [BudgetLine], budget: Double) -> BudgetSummary {
        let planned = lines.reduce(0) { $0 + $1.effectiveAmount }
        let committed = lines.filter { $0.status == .approved || $0.status == .paid }.reduce(0) { $0 + $1.effectiveAmount }
        let paid = lines.filter { $0.status == .paid }.reduce(0) { $0 + max($1.actual, 0) }
        return BudgetSummary(planned: planned, committed: committed, paid: paid, budget: budget)
    }

    /// Spend dated within the last 12 months (or undated) against the annual budget.
    static func annualSummary(lines: [BudgetLine], annualBudget: Double, now: Date = Date()) -> BudgetSummary {
        let cutoff = now.adding(days: -365)
        let relevant = lines.filter { $0.status.countsTowardSpend && ($0.date ?? now) >= cutoff }
        return summarize(relevant, budget: annualBudget)
    }
}
