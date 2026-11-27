import XCTest
@testable import ArtistManager

final class PlanningTests: XCTestCase {
    // MARK: Release timeline

    func testSingleTimelineIsDatedFromReleaseDay() {
        let date = TestDates.day(2026, 9, 18)
        let release = makeRelease(date: date)
        let tasks = ReleaseTimeline.missingTasks(for: release, existing: [], actor: .automation)
        XCTAssertEqual(tasks.count, ReleaseTimeline.singleSteps.count)
        let masters = try! XCTUnwrap(tasks.first { $0.templateKey?.hasSuffix(":masters") == true })
        XCTAssertEqual(Date.daysBetween(masters.due!, date), 56)
        XCTAssertTrue(tasks.allSatisfy { $0.releaseID == release.id && $0.createdBy == .automation })
        let outreach = try! XCTUnwrap(tasks.first { $0.templateKey?.hasSuffix(":press-outreach") == true })
        XCTAssertTrue(outreach.notes.contains("needs your approval"))
    }

    func testAlbumTimelineStartsEarlierAndAddsRollout() {
        let date = TestDates.day(2027, 3, 5)
        let album = makeRelease(date: date, type: .album)
        let tasks = ReleaseTimeline.missingTasks(for: album, existing: [], actor: .artist)
        XCTAssertEqual(tasks.count, ReleaseTimeline.singleSteps.count + ReleaseTimeline.extendedSteps.count)
        let masters = try! XCTUnwrap(tasks.first { $0.templateKey?.hasSuffix(":masters") == true })
        XCTAssertEqual(Date.daysBetween(masters.due!, date), 90)
    }

    func testTimelineNeverDuplicatesAndReschedulesOnlyOpenTasks() {
        var release = makeRelease(date: TestDates.day(2026, 9, 18))
        var tasks = ReleaseTimeline.missingTasks(for: release, existing: [], actor: .artist)
        XCTAssertTrue(ReleaseTimeline.missingTasks(for: release, existing: tasks, actor: .artist).isEmpty)

        tasks[0].status = .done
        let doneDue = tasks[0].due
        release.releaseDate = TestDates.day(2026, 10, 2)
        let moved = ReleaseTimeline.rescheduled(tasks: tasks, for: release)
        XCTAssertEqual(moved[0].due, doneDue, "Finished tasks keep their dates")
        XCTAssertEqual(Date.daysBetween(tasks[1].due!, moved[1].due!), 14)
    }

    // MARK: Metadata

    func testISRCAndUPCValidation() {
        XCTAssertTrue(MetadataValidator.isValidISRC("US-ABC-26-00001"))
        XCTAssertTrue(MetadataValidator.isValidISRC("usabc2600001"))
        XCTAssertFalse(MetadataValidator.isValidISRC("US-ABC-26-0001"))
        XCTAssertFalse(MetadataValidator.isValidISRC("12ABC2600001"))
        XCTAssertTrue(MetadataValidator.isValidUPC("123456789012"))
        XCTAssertFalse(MetadataValidator.isValidUPC("12345"))
    }

    func testMetadataIssues() {
        var release = makeRelease(date: TestDates.day(2026, 9, 16)) // a Wednesday
        var track = Track(title: "Song", isrc: "bad")
        track.writers = [Split(name: "A", share: 50), Split(name: "", share: 30)]
        release.tracks = [track]
        let issues = MetadataValidator.issues(for: release)
        let ids = Set(issues.map(\.id))
        XCTAssertTrue(ids.contains("friday"))
        XCTAssertTrue(ids.contains("artwork"))
        XCTAssertTrue(ids.contains("\(track.id.uuidString)-isrc-format"))
        XCTAssertTrue(ids.contains("\(track.id.uuidString)-splits"))
        XCTAssertTrue(ids.contains("\(track.id.uuidString)-writer-name"))

        release.releaseDate = TestDates.day(2026, 9, 18)
        release.artworkStatus = .final
        release.tracks[0].isrc = "USABC2600001"
        release.tracks[0].writers = [Split(name: "A", share: 50), Split(name: "B", share: 50)]
        XCTAssertTrue(MetadataValidator.issues(for: release).allSatisfy { $0.severity == .warning })
    }

    // MARK: Budgets

    func testBudgetSummary() {
        let release = makeRelease(date: nil)
        var r = release
        r.budget = 1000
        let lines = [
            BudgetLine(releaseID: r.id, planned: 600, status: .approved),
            BudgetLine(releaseID: r.id, planned: 300, actual: 350, status: .paid),
            BudgetLine(releaseID: r.id, planned: 500, status: .cancelled),
            BudgetLine(releaseID: r.id, planned: 200, status: .planned)
        ]
        let summary = BudgetMath.summary(for: r, lines: lines)
        XCTAssertEqual(summary.planned, 1150)
        XCTAssertEqual(summary.committed, 950)
        XCTAssertEqual(summary.paid, 350)
        XCTAssertTrue(summary.isOver)
    }

    // MARK: Career plan

    func testNewArtistGetsFoundationalRecommendations() {
        var ws = Workspace()
        ws.profile.onboardingCompleted = true
        let keys = PlanGenerator.generate(for: ws, now: TestDates.now).activeRuleKeys
        XCTAssertTrue(keys.isSuperset(of: ["profile-basics", "set-goals", "epk-complete", "email-start", "rights-pro"]))
    }

    func testReleaseRecommendationsFollowTheData() {
        var ws = Workspace.onboarded()
        let release = makeRelease(date: TestDates.now.adding(days: 20))
        ws.releases = [release]
        ws.subscribers = [Subscriber(email: "a@example.com")]
        let keys = PlanGenerator.generate(for: ws, now: TestDates.now).activeRuleKeys
        XCTAssertTrue(keys.contains("timeline-\(release.id)"))
        XCTAssertTrue(keys.contains("metadata-\(release.id)"))
        XCTAssertTrue(keys.contains("press-release-\(release.id)"))
        XCTAssertTrue(keys.contains("email-\(release.id)"))
        XCTAssertFalse(keys.contains("next-release"), "A release is already scheduled")

        ws.tasks = ReleaseTimeline.missingTasks(for: release, existing: [], actor: .artist)
        ws.pressReleases = [PressRelease(releaseID: release.id)]
        let after = PlanGenerator.generate(for: ws, now: TestDates.now).activeRuleKeys
        XCTAssertFalse(after.contains("timeline-\(release.id)"))
        XCTAssertFalse(after.contains("press-release-\(release.id)"))
    }

    func testRefreshKeepsTheArtistsDecisionsAndResolvesStaleOnes() {
        var ws = Workspace()
        ws.profile.onboardingCompleted = true
        let first = PlanGenerator.generate(for: ws, now: TestDates.now)
        PlanGenerator.proposal(merging: first, into: ws.recommendations, now: TestDates.now).apply(to: &ws, now: TestDates.now)
        let count = ws.recommendations.count

        // The artist dismisses one; refreshing doesn't reopen it or duplicate anything.
        let i = ws.recommendations.firstIndex { $0.ruleKey == "rights-pro" }!
        ws.recommendations[i].status = .dismissed
        let again = PlanGenerator.proposal(merging: PlanGenerator.generate(for: ws, now: TestDates.now), into: ws.recommendations, now: TestDates.now)
        again.apply(to: &ws, now: TestDates.now)
        XCTAssertEqual(ws.recommendations.count, count)
        XCTAssertEqual(ws.recommendations[i].status, .dismissed)

        // Once goals exist, "set goals" is no longer needed.
        ws.goals = [CareerGoal(title: "Grow", category: .audience)]
        PlanGenerator.proposal(merging: PlanGenerator.generate(for: ws, now: TestDates.now), into: ws.recommendations, now: TestDates.now)
            .apply(to: &ws, now: TestDates.now)
        XCTAssertEqual(ws.recommendations.first { $0.ruleKey == "set-goals" }?.status, .resolved)
    }

    // MARK: Routine work

    func testAutomationPlansTimelineCalendarAndFollowUpsWithoutDuplicates() {
        var ws = Workspace.onboarded()
        let release = makeRelease(date: TestDates.now.adding(days: 60))
        ws.releases = [release]
        let curator = makeContact("Curator", email: "c@playlists.com", role: .playlistCurator)
        ws.contacts = [curator]
        var pitch = Outreach(kind: .playlist, contactID: curator.id, releaseID: release.id, subject: "Submission", body: "Hi", status: .sent)
        pitch.sentAt = TestDates.now.adding(days: -10)
        ws.outreach = [pitch]

        let items = AutomationEngine.plan(for: ws, now: TestDates.now)
        let kinds = Set(items.map(\.kind))
        XCTAssertTrue(kinds.isSuperset(of: [.createTasks, .updateCalendar, .draftMaterials, .refreshPlan]))
        let followUp = try! XCTUnwrap(items.first { $0.kind == .draftMaterials }?.proposal.outreach.first)
        XCTAssertEqual(followUp.status, .draft, "Follow-ups are drafts only")
        XCTAssertEqual(followUp.parentID, pitch.id)

        for item in items { item.proposal.apply(to: &ws, now: TestDates.now) }
        let taskCount = ws.tasks.count
        let eventCount = ws.events.count
        let outreachCount = ws.outreach.count
        for item in AutomationEngine.plan(for: ws, now: TestDates.now) { item.proposal.apply(to: &ws, now: TestDates.now) }
        XCTAssertEqual(ws.tasks.count, taskCount)
        XCTAssertEqual(ws.events.count, eventCount)
        XCTAssertEqual(ws.outreach.count, outreachCount)
    }

    func testOrganizerMarksDeliveredReleasesAndTidiesTags() {
        var ws = Workspace.onboarded()
        var release = makeRelease(date: TestDates.now.adding(days: -3))
        release.stage = .delivered
        ws.releases = [release]
        ws.contacts = [Contact(name: "A", tags: [" press ", "Press", "radio"])]
        let ops = Organizer.operations(for: ws, now: TestDates.now)
        XCTAssertEqual(ops.count, 2)
        for op in ops { Organizer.apply(op, to: &ws, now: TestDates.now) }
        XCTAssertEqual(ws.releases[0].stage, .released)
        XCTAssertEqual(ws.contacts[0].tags, ["press", "radio"])
    }

    // MARK: Calendar checks

    func testConflictsForOverlapsAndBlackouts() {
        var ws = Workspace.onboarded()
        let start = TestDates.day(2026, 7, 10, hour: 19)
        ws.events = [
            CalendarEvent(title: "Show A", kind: .show, start: start, end: start.adding(hours: 2)),
            CalendarEvent(title: "Show B", kind: .show, start: start.adding(hours: 1), end: start.adding(hours: 3)),
            CalendarEvent(title: "Back to back", kind: .meeting, start: start.adding(hours: 3), end: start.adding(hours: 4))
        ]
        ws.profile.availability.blackoutDates = [DateRange(start: TestDates.day(2026, 7, 20), end: TestDates.day(2026, 7, 22), reason: "Family")]
        ws.tasks = [TaskItem(title: "Upload", due: TestDates.day(2026, 7, 21))]
        let conflicts = CalendarService.conflicts(in: ws, from: TestDates.now, days: 60)
        XCTAssertEqual(conflicts.filter { $0.id.hasPrefix("overlap") }.count, 1, "Touching events don't conflict")
        XCTAssertTrue(conflicts.contains { $0.id.hasPrefix("task-blackout") && $0.detail.contains("Family") })
    }

    func testDraftsUseTheArtistsProfile() {
        var ws = Workspace.onboarded()
        ws.profile.communication.signOff = "Warmly,"
        var release = makeRelease(date: TestDates.day(2026, 9, 18))
        release.smartLinkURL = "https://example.com/nl"
        let contact = makeContact("Ana Ruiz", email: "ana@zine.com")
        let pitch = Drafting.pitch(kind: .press, contact: contact, release: release, profile: ws.profile, pressKit: ws.pressKit)
        XCTAssertTrue(pitch.subject.contains("Northern Lights"))
        XCTAssertTrue(pitch.body.hasPrefix("Hi Ana,"))
        XCTAssertTrue(pitch.body.contains("https://example.com/nl"))
        XCTAssertTrue(pitch.body.contains("Warmly,\nJuniper Vale"))

        let pr = Drafting.pressRelease(for: release, profile: ws.profile, pressKit: ws.pressKit)
        XCTAssertTrue(pr.body.contains("ATLANTA, GA"))
        XCTAssertTrue(Drafting.pressReleaseText(pr).hasPrefix("FOR IMMEDIATE RELEASE"))
    }
}
