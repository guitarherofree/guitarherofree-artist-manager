import XCTest
@testable import ArtistManager

final class LegacyTests: XCTestCase {
    private func releasedWorkspace() -> (Workspace, Contact) {
        var ws = Workspace.onboarded()
        let sister = makeContact("Maya Vale", email: "maya@example.com", role: .other)
        ws.contacts = [sister]
        var release = makeRelease(title: "Northern Lights", date: TestDates.now.adding(days: -60))
        release.stage = .released
        release.distributor = "DistroKid"
        var track = Track(title: "Northern Lights", isrc: "US-AB1-26-00001", iswc: "T-123.456.789-0")
        track.writers = [Split(name: "Juniper Vale", share: 50, pro: "BMI", ipi: "00123456789"), Split(name: "Sam Ortiz", share: 50)]
        release.tracks = [track, Track(title: "Second Song")]
        ws.releases = [release]
        ws.profile.rightsMemberships = [RightsMembership(organization: "BMI", type: .performingRights, status: .registered),
                                        RightsMembership(organization: "SoundExchange", type: .neighboringRights, status: .inProgress)]
        ws.profile.links.bandcamp = "https://junipervale.bandcamp.com"
        return (ws, sister)
    }

    func testOlderFilesGetTheStarterPlanWithoutSampleRecords() throws {
        let ws = try TolerantDecoding.decodeWorkspace(Data(#"{"contacts":[]}"#.utf8))
        XCTAssertEqual(ws.legacy.documents.map(\.kind), [.will, .trust, .powerOfAttorney, .publishing, .recording, .splitSheets, .registrations])
        XCTAssertTrue(ws.legacy.accounts.isEmpty, "No blank sample account appears")
        XCTAssertTrue(ws.legacy.archive.isEmpty)
        XCTAssertEqual(ws.legacy.reviewEveryMonths, 12)

        let partial = #"{"legacy":{"whoKnows":"My sister","accounts":[{"id":"\#(UUID().uuidString)","service":"Bandcamp"}]}}"#
        let loaded = try TolerantDecoding.decodeWorkspace(Data(partial.utf8))
        XCTAssertEqual(loaded.legacy.whoKnows, "My sister")
        XCTAssertEqual(loaded.legacy.accounts.first?.service, "Bandcamp")
        XCTAssertEqual(loaded.legacy.accounts.first?.legacyOption, .unknown)
    }

    func testChangesAreUndoable() throws {
        var before = Workspace()
        before.legacy.whoKnows = "Nobody yet"
        var after = before
        after.legacy.whoKnows = "My attorney"
        after.legacy.archive = [ArchiveLocation(what: "Masters", location: "Studio drive")]
        let changes = Workspace.diff(before, after)
        XCTAssertEqual(changes.map(\.kind), [.legacy])
        try after.revert(changes)
        XCTAssertEqual(after, before)
    }

    func testReadinessChecks() {
        var (ws, sister) = releasedWorkspace()
        var checks = Dictionary(uniqueKeysWithValues: LegacyReadiness.checks(for: ws, now: TestDates.now).map { ($0.id, $0) })
        XCTAssertFalse(checks["executor"]!.done)
        XCTAssertFalse(checks["will"]!.done)
        XCTAssertFalse(checks["splits"]!.done, "“Second Song” has no splits")
        XCTAssertTrue(checks["splits"]!.detail.contains("1 song"))
        XCTAssertEqual(checks["splits"]!.destination, .releases)
        XCTAssertFalse(checks["registrations"]!.done)
        XCTAssertTrue(checks["registrations"]!.detail.contains("SoundExchange"))
        XCTAssertFalse(checks["reviewed"]!.done)
        XCTAssertEqual(LegacyReadiness.score(Array(checks.values)), 0, accuracy: 0.001)

        ws.legacy.executorID = sister.id
        ws.legacy.documents[0].status = .inPlace
        ws.legacy.documents[0].location = "Attorney's office"
        ws.legacy.accounts = [LegacyAccount(service: "DistroKid", accessKeptAt: "1Password", legacyOption: .setUp)]
        ws.legacy.archive = [ArchiveLocation(what: "Masters", location: "Studio drive", backupLocation: "Backblaze")]
        ws.legacy.wishes.unreleased = "Only finished songs, approved by Sam."
        ws.legacy.lastReviewed = TestDates.now
        checks = Dictionary(uniqueKeysWithValues: LegacyReadiness.checks(for: ws, now: TestDates.now).map { ($0.id, $0) })
        for id in ["executor", "will", "documents-located", "accounts", "legacy-contacts", "archive", "archive-backup", "unreleased", "reviewed"] {
            XCTAssertTrue(checks[id]!.done, id)
        }
        XCTAssertFalse(checks["backup"]!.done)
        XCTAssertFalse(checks["likeness"]!.done)

        ws.legacy.accounts.append(LegacyAccount(service: "Google Account", legacyOption: .notSetUp))
        checks = Dictionary(uniqueKeysWithValues: LegacyReadiness.checks(for: ws, now: TestDates.now).map { ($0.id, $0) })
        XCTAssertFalse(checks["accounts"]!.done, "A new account without a sign-in location")
        XCTAssertFalse(checks["legacy-contacts"]!.done)
        XCTAssertTrue(checks["legacy-contacts"]!.detail.contains("Google Account"))
    }

    func testReviewIsDueAfterTheChosenInterval() {
        var plan = LegacyPlan()
        XCTAssertTrue(LegacyReadiness.isReviewDue(plan, now: TestDates.now))
        plan.lastReviewed = TestDates.day(2026, 1, 1)
        plan.reviewEveryMonths = 12
        XCTAssertFalse(LegacyReadiness.isReviewDue(plan, now: TestDates.now))
        plan.reviewEveryMonths = 3
        XCTAssertTrue(LegacyReadiness.isReviewDue(plan, now: TestDates.now))
    }

    func testAccountSuggestions() {
        var (ws, _) = releasedWorkspace()
        var services = LegacyAccounts.suggestions(for: ws).map(\.service)
        XCTAssertEqual(services.prefix(4), ["DistroKid", "BMI", "SoundExchange", "Bandcamp"])
        XCTAssertTrue(services.contains("Password manager"))
        XCTAssertTrue(services.contains("Google Account"))
        XCTAssertTrue(LegacyAccounts.suggestions(for: ws).first!.legacyHint.contains("Leave a Legacy"))

        ws.legacy.accounts = [LegacyAccount(service: "distrokid")]
        services = LegacyAccounts.suggestions(for: ws).map(\.service)
        XCTAssertFalse(services.contains("DistroKid"), "Already listed, in any capitalization")
    }

    func testSpotsPasswordsTypedIntoNotes() {
        XCTAssertTrue(LegacyAccounts.looksLikeSecret("password: hunter2"))
        XCTAssertTrue(LegacyAccounts.looksLikeSecret("PIN is 4821"))
        XCTAssertTrue(LegacyAccounts.looksLikeSecret("it's Tr0ub4dor&3xyz"))
        XCTAssertTrue(LegacyAccounts.looksLikeSecret("recovery codes are in the drawer"), "Better to say less than to risk it")
        XCTAssertFalse(LegacyAccounts.looksLikeSecret("1Password › Music vault"))
        XCTAssertFalse(LegacyAccounts.looksLikeSecret("Ask Maya — she has emergency access"))
        XCTAssertFalse(LegacyAccounts.looksLikeSecret("juniper.vale.music@gmail.com"))
        XCTAssertFalse(LegacyAccounts.looksLikeSecret("https://distrokid.com/bank"))
    }

    func testLetterSummarizesWithoutSecrets() {
        var (ws, sister) = releasedWorkspace()
        ws.legacy.executorID = sister.id
        ws.legacy.whoKnows = "Maya has a printed copy"
        ws.legacy.documents[0].status = .inPlace
        ws.legacy.documents[0].location = "Attorney's office"
        ws.legacy.accounts = [LegacyAccount(service: "DistroKid", controls: "Releases & payouts", accessKeptAt: "1Password › Music")]
        ws.legacy.archive = [ArchiveLocation(what: "Masters", location: "Studio drive")]
        ws.legacy.wishes.nameAndLikeness = "No AI recreations of my voice."
        let md = LegacyLetter.markdown(for: ws, now: TestDates.now)
        XCTAssertTrue(md.contains("isn't a will and doesn't contain any passwords"))
        XCTAssertTrue(md.contains("**Looks after my music:** Maya Vale"))
        XCTAssertTrue(md.contains("**Will** — In place. Where: Attorney's office"))
        XCTAssertFalse(md.contains("**Trust**"), "Documents you don't have and haven't located are left out")
        XCTAssertTrue(md.contains("ISRC US-AB1-26-00001"))
        XCTAssertTrue(md.contains("Juniper Vale 50% (BMI, IPI 00123456789)"))
        XCTAssertTrue(md.contains("**BMI** — Performing rights (PRO)"))
        XCTAssertTrue(md.contains("Sign-in kept: 1Password › Music"))
        XCTAssertTrue(md.contains("**Masters** — Studio drive"))
        XCTAssertTrue(md.contains("No AI recreations of my voice."))

        let html = LegacyLetter.html(for: ws, now: TestDates.now)
        XCTAssertTrue(html.contains("<strong>Looks after my music:</strong>"))
        XCTAssertTrue(html.contains("Releases &amp; payouts"), "Text is escaped")
        XCTAssertTrue(html.contains("<h2>Accounts</h2>"))
        XCTAssertFalse(html.contains("**"))
    }

    func testPlanSuggestsStartingAndReviewing() {
        var ws = Workspace.onboarded()
        XCTAssertFalse(PlanGenerator.generate(for: ws, now: TestDates.now).recommendations.contains { $0.ruleKey == "legacy-start" },
                       "Nothing released, nothing to suggest")
        (ws, _) = releasedWorkspace()
        var recs = PlanGenerator.generate(for: ws, now: TestDates.now).recommendations
        let start = recs.first { $0.ruleKey == "legacy-start" }
        XCTAssertEqual(start?.destination, .legacy)
        XCTAssertEqual(start?.priority, .low)

        ws.legacy.lastReviewed = TestDates.day(2025, 1, 1)
        recs = PlanGenerator.generate(for: ws, now: TestDates.now).recommendations
        XCTAssertFalse(recs.contains { $0.ruleKey == "legacy-start" })
        XCTAssertTrue(recs.contains { $0.ruleKey == "legacy-review" })
    }
}
