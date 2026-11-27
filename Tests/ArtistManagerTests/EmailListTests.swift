import XCTest
@testable import ArtistManager

final class EmailListTests: XCTestCase {
    private let options = SubscriberImportOptions(source: "Mailchimp")

    // MARK: Import keeps suppressions

    func testImportNeverResubscribesSuppressedAddresses() {
        let existing = [
            Subscriber(email: "left@example.com", status: .unsubscribed),
            Subscriber(email: "bounced@example.com", status: .bounced),
            Subscriber(email: "spam@example.com", status: .complained)
        ]
        let csv = "Email Address,Status\nleft@example.com,subscribed\nbounced@example.com,subscribed\nSPAM@example.com,subscribed\n"
        let preview = SubscriberImporter.preview(csv: csv, existing: existing, options: options)
        XCTAssertEqual(Set(preview.suppressionsKept), ["left@example.com", "bounced@example.com", "spam@example.com"])
        XCTAssertTrue(preview.added.isEmpty)

        var list = existing
        SubscriberImporter.apply(preview, to: &list)
        XCTAssertEqual(list.map(\.status), [.unsubscribed, .bounced, .complained])
    }

    func testImportCanNewlySuppress() {
        let existing = [Subscriber(email: "fan@example.com", status: .subscribed)]
        let csv = "email,status,unsub_time\nfan@example.com,unsubscribed,2026-06-01 10:00:00\n"
        let preview = SubscriberImporter.preview(csv: csv, existing: existing, options: options)
        XCTAssertEqual(preview.newlySuppressed, ["fan@example.com"])
        var list = existing
        SubscriberImporter.apply(preview, to: &list)
        XCTAssertEqual(list[0].status, .unsubscribed)
        XCTAssertNotNil(list[0].statusChangedAt)
    }

    func testProviderUnsubscribedExportWithoutStatusColumn() {
        var opts = options
        opts.defaultStatus = .unsubscribed
        let preview = SubscriberImporter.preview(csv: "Email\nold@example.com\n", existing: [], options: opts)
        XCTAssertEqual(preview.added.first?.status, .unsubscribed)
    }

    func testDuplicateRowsInFileSuppressedWins() {
        let csv = "email,status\nx@example.com,subscribed\nx@example.com,unsubscribed\nX@Example.com,subscribed\n"
        let preview = SubscriberImporter.preview(csv: csv, existing: [], options: options)
        XCTAssertEqual(preview.added.count, 1)
        XCTAssertEqual(preview.added[0].status, .unsubscribed)
        XCTAssertEqual(preview.duplicateRowsInFile, 2)
    }

    func testConsentAndSourceAreRecorded() {
        let csv = "Email Address,First Name,Last Name,OPTIN_TIME,Tags\nnew@example.com,Ada,Lovelace,2026-05-01 09:30:00,\"VIP, Atlanta\"\n"
        let preview = SubscriberImporter.preview(csv: csv, existing: [], options: options)
        let s = try! XCTUnwrap(preview.added.first)
        XCTAssertEqual(s.firstName, "Ada")
        XCTAssertEqual(s.signupSource, "Mailchimp")
        XCTAssertEqual(s.tags, ["VIP", "Atlanta"])
        XCTAssertNotNil(s.consent?.capturedAt)
        XCTAssertEqual(s.consent?.method, .importedFromProvider)
        XCTAssertEqual(preview.missingConsent, 0)
    }

    func testSignupDateIsNotConsent() {
        let preview = SubscriberImporter.preview(csv: "email,date_added\na@example.com,2025-01-02\n", existing: [], options: options)
        XCTAssertNil(preview.added.first?.consent)
        XCTAssertEqual(preview.missingConsent, 1)
        XCTAssertEqual(Calendar.current.component(.year, from: preview.added.first!.createdAt), 2025)
    }

    func testMissingConsentIsCounted() {
        let preview = SubscriberImporter.preview(csv: "email\na@example.com\nb@example.com\n", existing: [], options: options)
        XCTAssertEqual(preview.missingConsent, 2)
    }

    func testInvalidRowsAndMissingEmailColumn() {
        let preview = SubscriberImporter.preview(csv: "email\nnot-an-email\n\ngood@example.com\n", existing: [], options: options)
        XCTAssertEqual(preview.added.count, 1)
        XCTAssertEqual(preview.invalidRows.count, 1)
        let noColumn = SubscriberImporter.preview(csv: "name\nAda\n", existing: [], options: options)
        XCTAssertFalse(noColumn.hasChanges)
        XCTAssertFalse(noColumn.invalidRows.isEmpty)
    }

    func testImportFillsGapsWithoutOverwriting() {
        let existing = [Subscriber(email: "a@example.com", firstName: "Original", tags: ["fan"])]
        let csv = "email,first_name,last_name,tags\na@example.com,Changed,Smith,\"fan, new\"\n"
        let preview = SubscriberImporter.preview(csv: csv, existing: existing, options: options)
        XCTAssertEqual(preview.updated.first?.firstName, "Original")
        XCTAssertEqual(preview.updated.first?.lastName, "Smith")
        XCTAssertEqual(preview.updated.first?.tags, ["fan", "new"])
    }

    // MARK: Export keeps suppressions

    func testFullExportRoundTripPreservesStatusAndConsent() {
        let list = [
            Subscriber(email: "a@example.com", status: .subscribed, consent: ConsentRecord(method: .doubleOptIn, source: "Site", capturedAt: TestDates.now, evidence: "form #12")),
            Subscriber(email: "b@example.com", status: .unsubscribed, statusChangedAt: TestDates.now),
            Subscriber(email: "c@example.com", status: .bounced)
        ]
        let csv = SubscriberExporter.csv(list)
        let preview = SubscriberImporter.preview(csv: csv, existing: [], options: SubscriberImportOptions())
        let byEmail = Dictionary(uniqueKeysWithValues: preview.added.map { ($0.email, $0) })
        XCTAssertEqual(byEmail["a@example.com"]?.status, .subscribed)
        XCTAssertEqual(byEmail["a@example.com"]?.consent?.method, .doubleOptIn)
        XCTAssertEqual(byEmail["a@example.com"]?.consent?.evidence, "form #12")
        XCTAssertEqual(byEmail["b@example.com"]?.status, .unsubscribed)
        XCTAssertNil(byEmail["b@example.com"]?.consent, "A signup date alone never becomes a consent record")
        XCTAssertEqual(byEmail["c@example.com"]?.status, .bounced)
    }

    func testSendableExportExcludesEveryoneWhoCantReceive() {
        let list = [Subscriber(email: "ok@example.com"), Subscriber(email: "p@example.com", status: .pending),
                    Subscriber(email: "u@example.com", status: .unsubscribed), Subscriber(email: "b@example.com", status: .bounced)]
        let sendable = SubscriberExporter.sendableCSV(list)
        XCTAssertTrue(sendable.contains("ok@example.com"))
        XCTAssertFalse(sendable.contains("p@example.com"))
        XCTAssertFalse(sendable.contains("u@example.com"))
        let suppression = SubscriberExporter.suppressionCSV(list)
        XCTAssertTrue(suppression.contains("u@example.com") && suppression.contains("b@example.com"))
        XCTAssertFalse(suppression.contains("ok@example.com"))
    }

    // MARK: Campaign results

    func testResultsApplyBouncesAndUnsubscribesButNeverResubscribe() {
        var list = [Subscriber(email: "hard@example.com"), Subscriber(email: "soft@example.com"),
                    Subscriber(email: "unsub@example.com"), Subscriber(email: "spam@example.com"),
                    Subscriber(email: "old@example.com", status: .complained), Subscriber(email: "ok@example.com")]
        let report = """
        email,event,bounce_type,opened,clicked
        hard@example.com,bounce,hard,,
        soft@example.com,bounce,soft,,
        unsub@example.com,unsubscribe,,1,0
        spam@example.com,spam complaint,,,
        old@example.com,unsubscribe,,,
        ok@example.com,delivered,,true,1
        stranger@example.com,delivered,,,
        """
        let result = CampaignResultsImporter.read(csv: report, subscribers: list, fileName: "report.csv")
        XCTAssertEqual(result.results.recipients, 7)
        XCTAssertEqual(result.results.bounces, 2)
        XCTAssertEqual(result.results.unsubscribes, 2)
        XCTAssertEqual(result.results.complaints, 1)
        XCTAssertEqual(result.results.opens, 2)
        XCTAssertEqual(result.results.clicks, 1)
        XCTAssertEqual(result.unknownAddresses, 1)

        CampaignResultsImporter.apply(result, to: &list, campaignName: "Single")
        let status = Dictionary(uniqueKeysWithValues: list.map { ($0.email, $0.status) })
        XCTAssertEqual(status["hard@example.com"], .bounced)
        XCTAssertEqual(status["soft@example.com"], .subscribed, "Soft bounces are not suppressed")
        XCTAssertEqual(status["unsub@example.com"], .unsubscribed)
        XCTAssertEqual(status["spam@example.com"], .complained)
        XCTAssertEqual(status["old@example.com"], .complained, "A complaint isn't downgraded")
        XCTAssertEqual(status["ok@example.com"], .subscribed)
    }

    // MARK: Hygiene, segments and checks

    func testHygieneReport() {
        let list = [
            Subscriber(email: "a@gmial.com", consent: ConsentRecord()),
            Subscriber(email: "info@band.com", consent: ConsentRecord()),
            Subscriber(email: "noconsent@example.com"),
            Subscriber(email: "bad address"),
            Subscriber(email: "late@example.com", status: .pending, createdAt: TestDates.now.adding(days: -40)),
            Subscriber(email: "gone@gmial.com", status: .unsubscribed)
        ]
        let report = ListHygiene.report(list, now: TestDates.now)
        XCTAssertEqual(report.likelyTypos, ["a@gmial.com"], "Suppressed addresses aren't flagged")
        XCTAssertEqual(report.roleAccounts, ["info@band.com"])
        XCTAssertEqual(report.subscribedWithoutConsent, ["noconsent@example.com"])
        XCTAssertEqual(report.invalidAddresses, ["bad address"])
        XCTAssertEqual(report.stalePending, ["late@example.com"])
        XCTAssertEqual(EmailAddress.suggestedFix("a@gmial.com"), "a@gmail.com")
    }

    func testSegmentsOnlyEverReachSubscribedAddresses() {
        var ws = Workspace.onboarded()
        ws.subscribers = [
            Subscriber(email: "atl@example.com", signupSource: "Merch table", tags: ["VIP"], location: "Atlanta"),
            Subscriber(email: "atl-unsub@example.com", status: .unsubscribed, tags: ["VIP"], location: "Atlanta"),
            Subscriber(email: "nyc@example.com", tags: ["vip"], location: "New York")
        ]
        var segment = Segment(name: "Atlanta VIPs")
        segment.rules.anyTags = ["VIP"]
        segment.rules.locationContains = "atlanta"
        ws.segments = [segment]
        XCTAssertEqual(ws.recipients(for: segment.id).map(\.email), ["atl@example.com"])
        XCTAssertEqual(ws.recipients(for: nil).count, 2)
    }

    func testCampaignChecks() {
        var ws = Workspace.onboarded()
        let empty = EmailCampaign()
        XCTAssertTrue(CampaignLint.hasErrors(CampaignLint.check(empty, workspace: ws)), "No subject, body or recipients")

        ws.subscribers = [Subscriber(email: "a@example.com")]
        let campaign = EmailCampaign(subject: "New music", body: "It's out.")
        let checks = CampaignLint.check(campaign, workspace: ws)
        XCTAssertFalse(CampaignLint.hasErrors(checks))
        XCTAssertTrue(checks.contains { $0.id == "address" }, "Warns about the missing postal address")
        XCTAssertTrue(checks.contains { $0.id == "consent" })
        XCTAssertTrue(checks.contains { $0.id == "unsubscribe" })
    }

    func testCampaignExportIncludesFooterAndEscapesHTML() {
        var profile = Workspace.onboarded().profile
        profile.communication.mailingAddress = "PO Box 1, Atlanta GA"
        let campaign = EmailCampaign(subject: "Fish & <Chips>", body: "Line one\n\nLine <two>")
        let html = CampaignExport.html(campaign, profile: profile)
        XCTAssertTrue(html.contains("Fish &amp; &lt;Chips&gt;"))
        XCTAssertTrue(html.contains("Line &lt;two&gt;"))
        XCTAssertTrue(html.contains("PO Box 1"))
        XCTAssertTrue(CampaignExport.plainText(campaign, profile: profile).contains("Unsubscribe"))
    }

    func testAnnouncementDraftDependsOnReleaseDate() {
        let profile = Workspace.onboarded().profile
        var release = makeRelease(date: TestDates.now.adding(days: 10))
        release.smartLinkURL = "https://example.com/link"
        let upcoming = Drafting.emailAnnouncement(for: release, profile: profile, now: TestDates.now)
        XCTAssertTrue(upcoming.subject.contains("out"))
        XCTAssertTrue(upcoming.body.contains("Pre-save"))
        let out = Drafting.emailAnnouncement(for: release, profile: profile, now: TestDates.now.adding(days: 11))
        XCTAssertTrue(out.subject.contains("out now"))
        XCTAssertTrue(out.body.contains("Listen: https://example.com/link"))
    }
}
