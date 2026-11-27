import XCTest
@testable import ArtistManager

final class CoverageTests: XCTestCase {
    private let reviewPage = """
    <!doctype html>
    <html><head>
    <meta charset="utf-8">
    <title>Juniper Vale review | The Lantern</title>
    <meta property="og:title" content="Juniper Vale: Northern Lights review &#8211; a hushed, luminous debut">
    <meta property="og:site_name" content="The Lantern">
    <meta name="author" content="Dana Reyes">
    <meta property="article:published_time" content="2026-10-14T09:00:00-04:00">
    <meta name='description' content='Vale&rsquo;s first album trades volume for intimacy &amp; wins.'>
    <script type="application/ld+json">
    {"@context":"https://schema.org","@type":"Review","reviewRating":{"@type":"Rating","ratingValue":8.2,"bestRating":10},
     "author":{"@type":"Person","name":"Dana Reyes"},"publisher":{"@type":"Organization","name":"The Lantern"}}
    </script>
    <script>document.write("tracking")</script>
    <meta http-equiv="refresh" content="30">
    </head><body onload="track()"><article><p>Full review text.</p><a href="javascript:void(0)">x</a></article></body></html>
    """

    // MARK: Reading a page

    func testReadsOpenGraphArticleTagsAndReviewScore() {
        let meta = LinkReader.parse(html: reviewPage, url: "https://www.thelantern.example/reviews/juniper-vale-northern-lights?utm_source=x")
        XCTAssertEqual(meta.title, "Juniper Vale: Northern Lights review – a hushed, luminous debut")
        XCTAssertEqual(meta.siteName, "The Lantern")
        XCTAssertEqual(meta.author, "Dana Reyes")
        XCTAssertEqual(meta.published, ISO8601DateFormatter().date(from: "2026-10-14T13:00:00Z"))
        XCTAssertEqual(meta.description, "Vale’s first album trades volume for intimacy & wins.")
        XCTAssertEqual(meta.rating, "8.2/10")
        XCTAssertTrue(meta.schemaTypes.contains("Review"))

        let c = CoverageLinks.coverage(from: meta, now: TestDates.now)
        XCTAssertEqual(c.kind, .review)
        XCTAssertEqual(c.outlet, "The Lantern")
        XCTAssertEqual(c.rating, "8.2/10")
        XCTAssertTrue(c.verified, "The page was read, so the link is known to work")
        XCTAssertEqual(c.linkCheckedAt, TestDates.now)
        XCTAssertTrue(c.includeInPressKit)
        XCTAssertEqual(c.citation, "Dana Reyes, The Lantern (8.2/10)")
    }

    func testFallsBackToTitleElementAndWebAddress() {
        let html = "<html><head><TITLE>An Interview with Juniper Vale | Night Shift Radio</TITLE></head><body></body></html>"
        let meta = LinkReader.parse(html: html, url: "https://nightshiftradio.example/shows/juniper-vale")
        XCTAssertEqual(meta.siteName, "Night Shift Radio", "The title's suffix spells the outlet better than the address")
        XCTAssertEqual(meta.title, "An Interview with Juniper Vale")
        XCTAssertNil(meta.published)
        XCTAssertEqual(CoverageLinks.guessKind(url: meta.url, title: meta.title), .interview)

        let bare = LinkReader.parse(html: "<p>no head</p>", url: "https://www.smallzine.co.uk/2026/11/new-music")
        XCTAssertEqual(bare.siteName, "Smallzine")
        XCTAssertEqual(bare.title, "")
    }

    func testJSONLDGraphAndAuthorLists() {
        let html = """
        <script type="application/ld+json">{"@graph":[{"@type":"WebSite","name":"Site"},
        {"@type":"NewsArticle","headline":"Ten artists to watch","datePublished":"2026-03-02",
         "author":[{"name":"A. Writer"},{"name":"B. Writer"}]}]}</script>
        """
        let meta = LinkReader.parse(html: html, url: "https://example.org/news/ten-to-watch")
        XCTAssertEqual(meta.title, "Ten artists to watch")
        XCTAssertEqual(meta.author, "A. Writer, B. Writer")
        XCTAssertNotNil(meta.published)
        XCTAssertEqual(CoverageLinks.guessKind(url: meta.url, title: meta.title, schemaTypes: meta.schemaTypes), .article)
    }

    func testEntityDecoding() {
        XCTAssertEqual(LinkReader.decodeEntities("Rock &amp; Roll &#39;26 &#x2014; &quot;live&quot; &unknown; &"),
                       "Rock & Roll '26 — \"live\" &unknown; &")
    }

    func testDecodesDeclaredCharset() {
        let latin = "Café Señor".data(using: .isoLatin1)!
        XCTAssertEqual(LinkReader.decodeText(latin, contentType: "text/html; charset=ISO-8859-1"), "Café Señor")
        XCTAssertEqual(LinkReader.decodeText(Data("Café".utf8)), "Café")
    }

    // MARK: Links

    func testExtractsLinksFromPastedTextWithoutDuplicates() {
        let pasted = """
        Coverage so far:
        - https://thelantern.example/reviews/northern-lights/ (great one!)
        - http://www.thelantern.example/reviews/northern-lights?utm_source=newsletter&utm_medium=email.
        Interview: https://nightshiftradio.example/shows/juniper-vale, and the video https://youtu.be/abc123
        """
        let urls = CoverageLinks.extractURLs(from: pasted)
        XCTAssertEqual(urls, ["https://thelantern.example/reviews/northern-lights/",
                              "https://nightshiftradio.example/shows/juniper-vale",
                              "https://youtu.be/abc123"])
    }

    func testNormalizeIgnoresTrackingAndFormattingDifferences() {
        let a = CoverageLinks.normalize("https://www.thelantern.example/reviews/northern-lights/?utm_campaign=x&fbclid=1#comments")
        let b = CoverageLinks.normalize("http://thelantern.example/reviews/northern-lights")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(CoverageLinks.normalize("https://site.example/watch?v=1"), CoverageLinks.normalize("https://site.example/watch?v=2"),
                          "Meaningful query parameters still distinguish pages")
    }

    func testGuessesKindFromWhereTheLinkPoints() {
        XCTAssertEqual(CoverageLinks.guessKind(url: "https://open.spotify.com/playlist/37i9", title: "Fresh Folk"), .playlistAdd)
        XCTAssertEqual(CoverageLinks.guessKind(url: "https://podcasts.apple.com/us/podcast/x/id1", title: "Episode 12"), .podcast)
        XCTAssertEqual(CoverageLinks.guessKind(url: "https://www.youtube.com/watch?v=abc", title: "Live in studio"), .video)
        XCTAssertEqual(CoverageLinks.guessKind(url: "https://zine.example/2026/premiere-juniper-vale", title: "Juniper Vale shares new song"), .premiere)
        XCTAssertEqual(CoverageLinks.guessKind(url: "https://zine.example/a", title: "Album Review: Northern Lights"), .review)
    }

    func testMentionsAndPlaylistAddsStayOutOfThePressKitByDefault() {
        var meta = LinkMetadata()
        meta.url = "https://open.spotify.com/playlist/xyz"
        meta.title = "Fresh Folk"
        XCTAssertFalse(CoverageLinks.coverage(from: meta).includeInPressKit)
        XCTAssertFalse(CoverageLinks.coverage(from: meta, kindOverride: .mention).includeInPressKit)
    }

    // MARK: Saved copies

    func testSavedCopyRemovesScriptsAndNotesItsSource() {
        let saved = CoverageArchive.snapshot(html: reviewPage, url: "https://thelantern.example/r?a=1&b=2", savedAt: TestDates.now)
        XCTAssertFalse(saved.contains("<script"), "No scripts run from a saved copy")
        XCTAssertFalse(saved.contains("onload"))
        XCTAssertFalse(saved.contains("javascript:"))
        XCTAssertFalse(saved.lowercased().contains("http-equiv=\"refresh\""))
        XCTAssertTrue(saved.contains("<base href=\"https://thelantern.example/r?a=1&amp;b=2\">"), "Relative links resolve against the original")
        XCTAssertTrue(saved.contains("Copy saved by Manager on July 1, 2026"))
        XCTAssertTrue(saved.contains("Full review text."))
        let headIndex = saved.range(of: "<head>")!.upperBound
        XCTAssertTrue(saved[headIndex...].hasPrefix("<base"), "The base address comes before anything that loads")
    }

    func testCoverageFilesAreStoredInTheMediaFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("coverage-\(UUID().uuidString)")
        let persistence = Persistence(rootURL: root)
        let id = UUID()
        let name = try persistence.saveCoverageCopy("<html>copy</html>", for: id)
        XCTAssertEqual(name, "Coverage/\(id.uuidString)-page.html")
        XCTAssertTrue(persistence.mediaFileExists(name))

        let source = root.appendingPathComponent("Clipping Scan.PDF")
        try Data("pdf".utf8).write(to: source)
        let attachment = try persistence.importCoverageAttachment(from: source)
        XCTAssertEqual(attachment.originalName, "Clipping Scan.PDF")
        XCTAssertTrue(attachment.fileName.hasPrefix("Coverage/") && attachment.fileName.hasSuffix(".pdf"))
        XCTAssertEqual(try Data(contentsOf: persistence.mediaFile(attachment.fileName)), Data("pdf".utf8))
        XCTAssertFalse(persistence.mediaFileExists(""))
    }

    // MARK: CSV

    func testCSVRoundTrip() {
        let release = makeRelease(date: TestDates.now)
        var c = Coverage(outlet: "The Lantern", title: "Northern Lights review", url: "https://thelantern.example/r",
                         date: TestDates.day(2026, 10, 14), kind: .review, quote: "Hushed, luminous", includeInPressKit: true,
                         releaseID: release.id)
        c.author = "Dana Reyes"
        c.rating = "8.2/10"
        c.notes = "Ran in print, too"
        let csv = CoverageCSV.export([c], releases: [release])
        let preview = CoverageCSV.preview(csv: csv, existing: [], releases: [release], now: TestDates.now)
        XCTAssertEqual(preview.added.count, 1)
        let back = preview.added[0]
        XCTAssertEqual(back.outlet, c.outlet)
        XCTAssertEqual(back.title, c.title)
        XCTAssertEqual(back.kind, .review)
        XCTAssertEqual(back.author, "Dana Reyes")
        XCTAssertEqual(back.rating, "8.2/10")
        XCTAssertEqual(back.quote, "Hushed, luminous")
        XCTAssertEqual(back.notes, "Ran in print, too")
        XCTAssertEqual(back.releaseID, release.id)
        XCTAssertEqual(back.date, c.date)
        XCTAssertFalse(back.verified, "An imported row hasn't been checked")

        let again = CoverageCSV.preview(csv: csv, existing: [c], releases: [release])
        XCTAssertTrue(again.added.isEmpty)
        XCTAssertEqual(again.duplicates.count, 1)
    }

    func testCSVImportAcceptsCommonColumnNames() {
        let csv = """
        Publication,Headline,Link,Category,Published,Writer,Score
        The Lantern,Northern Lights review,https://thelantern.example/r,Album review,"October 14, 2026",Dana Reyes,4/5
        Night Shift Radio,,,Radio,11/02/2026,,
        ,,,,,,
        ,Untitled blurb,https://www.smallzine.example/blurb,mention,,,
        The Lantern,Northern Lights review,,review,,,
        """
        let preview = CoverageCSV.preview(csv: csv, existing: [], releases: [])
        XCTAssertEqual(preview.totalRows, 5)
        XCTAssertEqual(preview.added.count, 3)
        XCTAssertEqual(preview.skipped.count, 1)
        XCTAssertEqual(preview.duplicates.count, 1, "Same outlet and headline without a link is a duplicate")

        let review = preview.added[0]
        XCTAssertEqual(review.kind, .review)
        XCTAssertEqual(review.rating, "4/5")
        XCTAssertEqual(review.author, "Dana Reyes")
        XCTAssertEqual(review.date, TestDates.calendar.date(from: DateComponents(year: 2026, month: 10, day: 14)))
        XCTAssertEqual(preview.added[1].kind, .radioPlay)
        XCTAssertEqual(preview.added[2].outlet, "Smallzine", "Outlet comes from the link when the column is empty")
        XCTAssertEqual(preview.added[2].kind, .mention)
        XCTAssertFalse(preview.added[2].includeInPressKit)
    }

    func testOlderSavedCoverageStillLoads() throws {
        let json = """
        {"coverage":[{"id":"\(UUID().uuidString)","outlet":"Zine","title":"Feature","url":"","kind":"feature",
          "quote":"","includeInPressKit":true,"verified":false}]}
        """
        let ws = try TolerantDecoding.decodeWorkspace(Data(json.utf8))
        XCTAssertEqual(ws.coverage.count, 1)
        XCTAssertEqual(ws.coverage[0].outlet, "Zine")
        XCTAssertEqual(ws.coverage[0].attachments, [])
        XCTAssertNil(ws.coverage[0].savedCopy)
        XCTAssertEqual(ws.coverage[0].linkIssue, "")
    }
}

final class CoverageConnectionTests: XCTestCase {
    func testSuggestsReleaseAndPitchedWriter() {
        let older = makeRelease(title: "Lights", date: TestDates.day(2025, 1, 1))
        let album = makeRelease(title: "Northern Lights", date: TestDates.day(2026, 10, 1))
        let dana = makeContact("Dana Reyes", email: "dana@example.com")
        var editor = makeContact("Editor", email: "ed@example.com")
        editor.organization = "The Lantern"
        var other = makeContact("Sam", email: "sam@example.com")
        other.organization = "The Lantern"
        let pitch = Outreach(kind: .review, contactID: other.id, releaseID: album.id, status: .sent)

        var byAuthor = Coverage(outlet: "The Lantern", title: "Juniper Vale: Northern Lights review")
        byAuthor.author = "dana reyes"
        CoverageLinks.suggestLinks(for: &byAuthor, releases: [older, album], contacts: [dana, editor, other], outreach: [pitch])
        XCTAssertEqual(byAuthor.releaseID, album.id, "The longest matching title wins")
        XCTAssertEqual(byAuthor.contactID, dana.id)

        var byOutlet = Coverage(outlet: "the lantern", title: "Ten songs this week")
        CoverageLinks.suggestLinks(for: &byOutlet, releases: [album], contacts: [dana, editor, other], outreach: [pitch])
        XCTAssertNil(byOutlet.releaseID)
        XCTAssertEqual(byOutlet.contactID, other.id, "Of two people at the outlet, the one who was pitched")

        var ambiguous = Coverage(outlet: "The Lantern", title: "x")
        CoverageLinks.suggestLinks(for: &ambiguous, releases: [], contacts: [editor, other])
        XCTAssertNil(ambiguous.contactID, "No guess when two people at the outlet are equally likely")

        var kept = Coverage(outlet: "The Lantern", title: "Northern Lights", releaseID: older.id)
        CoverageLinks.suggestLinks(for: &kept, releases: [album], contacts: [])
        XCTAssertEqual(kept.releaseID, older.id, "Choices already made are kept")
    }

    func testCoverageClosesTheMatchingPitch() {
        let album = makeRelease(date: TestDates.now)
        let dana = makeContact("Dana Reyes")
        var ws = Workspace.onboarded()
        ws.outreach = [
            Outreach(kind: .review, contactID: dana.id, releaseID: album.id, status: .sent, sentAt: TestDates.now, followUpDue: TestDates.now.adding(days: 7)),
            Outreach(kind: .press, contactID: dana.id, releaseID: UUID(), status: .sent, sentAt: TestDates.now.adding(days: 1)),
            Outreach(kind: .review, contactID: dana.id, releaseID: album.id, status: .draft),
        ]
        ws.markPitchCovered(by: Coverage(outlet: "The Lantern", releaseID: album.id, contactID: dana.id))
        XCTAssertEqual(ws.outreach[0].status, .covered)
        XCTAssertNil(ws.outreach[0].followUpDue)
        XCTAssertEqual(ws.outreach[1].status, .sent, "A pitch for a different release stays open")
        XCTAssertEqual(ws.outreach[2].status, .draft, "Unsent drafts aren't touched")

        var none = ws
        none.markPitchCovered(by: Coverage(outlet: "Elsewhere"))
        XCTAssertEqual(none.outreach, ws.outreach)
    }
}

final class CoveragePlanTests: XCTestCase {
    func testPlanAsksToSaveCoverageAfterPitchedRelease() {
        var ws = Workspace.onboarded()
        let release = makeRelease(date: TestDates.now.adding(days: -14))
        ws.releases = [release]
        ws.outreach = [Outreach(kind: .review, releaseID: release.id, status: .sent)]
        let keys = Set(PlanGenerator.generate(for: ws, now: TestDates.now).recommendations.map(\.ruleKey))
        XCTAssertTrue(keys.contains("coverage-log-\(release.id)"))

        ws.coverage = [Coverage(outlet: "The Lantern", releaseID: release.id)]
        let after = Set(PlanGenerator.generate(for: ws, now: TestDates.now).recommendations.map(\.ruleKey))
        XCTAssertFalse(after.contains("coverage-log-\(release.id)"))
        XCTAssertTrue(after.contains("coverage-quotes"), "Press kit coverage without a quote gets a nudge")
    }

    func testBrokenLinksWithoutCopiesAreFlagged() {
        var ws = Workspace.onboarded()
        var broken = Coverage(outlet: "Gone Zine", quote: "Great")
        broken.linkIssue = "Page not found (404)"
        var kept = broken
        kept.id = UUID()
        kept.savedCopy = "Coverage/x-page.html"
        ws.coverage = [broken, kept]
        let recs = PlanGenerator.generate(for: ws, now: TestDates.now).recommendations
        let rec = recs.first { $0.ruleKey == "coverage-broken" }
        XCTAssertEqual(rec?.title, "1 coverage link no longer works")
        XCTAssertEqual(rec?.priority, .high)
        XCTAssertEqual(rec?.destination, .coverage)
    }

    func testPitchOutcomeStartsACoverageRecord() {
        var writer = makeContact("Dana Reyes")
        writer.organization = "The Lantern"
        let pitch = Outreach(kind: .review, contactID: writer.id, releaseID: UUID(), status: .covered)
        let c = CoverageLinks.coverage(resultOf: pitch, contact: writer)
        XCTAssertEqual(c.kind, .review)
        XCTAssertEqual(c.outlet, "The Lantern")
        XCTAssertEqual(c.author, "Dana Reyes")
        XCTAssertEqual(c.contactID, writer.id)
        XCTAssertEqual(c.releaseID, pitch.releaseID)
        XCTAssertFalse(c.verified)
        XCTAssertEqual(CoverageKind(resultOf: .spotifyEditorial), .playlistAdd)
    }
}
