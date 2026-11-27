import XCTest
@testable import ArtistManager

final class TargetTests: XCTestCase {
    private func workspace() -> (Workspace, Target, Contact) {
        var ws = Workspace.onboarded()
        ws.profile.genres = ["Indie folk", "Americana"]
        ws.profile.audience.comparableArtists = "Adrianne Lenker, Gillian Welch"
        var editor = makeContact("Dana Reyes", email: "dana@thelantern.example")
        editor.organization = "The Lantern Magazine"
        var freelancer = makeContact("Sam Ortiz", email: "sam@gmail.com")
        freelancer.organization = "Freelance"
        var byDomain = makeContact("Pat Lee", email: "pat@news.thelantern.example")
        byDomain.organization = ""
        ws.contacts = [editor, freelancer, byDomain]
        var t = Target(name: "Lantern Magazine", kind: .publication, status: .watching)
        t.website = "https://www.thelantern.example"
        t.genres = ["Folk", "Americana"]
        t.similarArtists = "Big Thief, Adrianne Lenker"
        t.location = "Atlanta, GA"
        ws.targets = [t]
        return (ws, t, editor)
    }

    func testFindsPeopleByOrganizationWebsiteDomainOrLink() {
        let (ws, t, editor) = workspace()
        var linked = t
        let people = Targets.contacts(for: t, in: ws.contacts)
        XCTAssertEqual(Set(people.map(\.name)), ["Dana Reyes", "Pat Lee"],
                       "“The Lantern Magazine” matches “Lantern Magazine”, and a work address on their domain counts")
        XCTAssertFalse(people.contains { $0.name == "Sam Ortiz" }, "A Gmail address doesn't tie someone to an outlet")
        linked.contactIDs = [ws.contacts[1].id]
        XCTAssertTrue(Targets.contacts(for: linked, in: ws.contacts).contains { $0.name == "Sam Ortiz" }, "Linked by hand")
        XCTAssertTrue(people.contains { $0.id == editor.id })
    }

    func testActivitySuggestsTheNextStatusWithoutApplyingIt() {
        var (ws, t, editor) = workspace()
        XCTAssertNil(Targets.activity(for: t, in: ws).suggestedStatus)

        ws.outreach = [Outreach(kind: .press, contactID: editor.id, status: .sent, sentAt: TestDates.now)]
        var a = Targets.activity(for: t, in: ws)
        XCTAssertEqual(a.pitches.count, 1)
        XCTAssertEqual(a.lastPitch, TestDates.now)
        XCTAssertEqual(a.suggestedStatus, .pitched)
        XCTAssertEqual(ws.targets[0].status, .watching, "The suggestion is only offered")

        ws.outreach[0].status = .replied
        XCTAssertEqual(Targets.activity(for: t, in: ws).suggestedStatus, .talking)

        ws.coverage = [Coverage(outlet: "Elsewhere", title: "Review", url: "https://thelantern.example/reviews/x")]
        a = Targets.activity(for: t, in: ws)
        XCTAssertEqual(a.coverage.count, 1, "Coverage on their website counts even under another outlet name")
        XCTAssertEqual(a.suggestedStatus, .won)

        var further = t
        further.status = .won
        XCTAssertNil(Targets.activity(for: further, in: ws).suggestedStatus, "Never suggests going backwards")
        var paused = t
        paused.status = .notNow
        XCTAssertNil(Targets.activity(for: paused, in: ws).suggestedStatus)

        let drafts = Outreach(kind: .press, contactID: editor.id, status: .draft)
        ws.outreach = [drafts]
        ws.coverage = []
        XCTAssertNil(Targets.activity(for: t, in: ws).suggestedStatus, "Unsent drafts aren't pitches")
    }

    func testSharedPlatformsDontMatchEveryOutlet() {
        var playlist = Target(name: "Fresh Folk", kind: .playlist)
        playlist.website = "https://open.spotify.com/playlist/abc"
        let other = Coverage(outlet: "Another Playlist", url: "https://open.spotify.com/playlist/xyz")
        XCTAssertTrue(Targets.coverage(for: playlist, in: [other]).isEmpty)
        XCTAssertNil(Targets.host("https://www.youtube.com/@channel"))
        XCTAssertEqual(Targets.host("WWW.TheLantern.example/path"), "thelantern.example")
        XCTAssertEqual(Targets.siteRoot("thelantern.example/reviews?x=1"), "https://thelantern.example")
    }

    func testFitReasons() {
        let (ws, t, _) = workspace()
        let reasons = Targets.fitReasons(for: t, profile: ws.profile)
        XCTAssertTrue(reasons.contains("Covers indie folk and americana"))
        XCTAssertTrue(reasons.contains("Works with artists like Adrianne Lenker"))
        XCTAssertTrue(reasons.contains("Based in Atlanta"))
        XCTAssertTrue(Targets.fitReasons(for: Target(name: "Metal Weekly", genres: ["Metal"]), profile: ws.profile).isEmpty)
    }

    func testDueAndWayIn() {
        var t = Target(name: "Quiet Records", kind: .label, status: .ready)
        XCTAssertFalse(Targets.isDue(t, today: TestDates.now))
        t.nextCheck = TestDates.now.adding(days: -1)
        XCTAssertTrue(Targets.isDue(t, today: TestDates.now))
        XCTAssertFalse(Targets.hasWayIn(t, activity: TargetActivity()))
        t.submissionURL = "https://quietrecords.example/demos"
        XCTAssertTrue(Targets.hasWayIn(t, activity: TargetActivity()))
    }

    func testSuggestionsFromContactsAndCoverage() {
        var ws = Workspace.onboarded()
        var labelRep = makeContact("Ana", email: "ana@quiet.example", role: .label)
        labelRep.organization = "Quiet Records"
        var second = makeContact("Ben", email: "ben@quiet.example", role: .label)
        second.organization = "quiet records"
        let team = makeContact("My Manager", role: .manager, team: true)
        var venue = makeContact("Venue Person", role: .venue)
        venue.organization = "The Earl"
        ws.contacts = [labelRep, second, team, venue]
        ws.coverage = [Coverage(outlet: "Night Shift Radio", url: "https://nightshiftradio.example/show/1", kind: .radioPlay),
                       Coverage(outlet: "Quiet Records", kind: .mention)]
        ws.targets = [Target(name: "Already Here")]
        let s = Targets.suggestions(in: ws)
        XCTAssertEqual(s.map(\.name), ["Quiet Records", "Night Shift Radio"])
        XCTAssertEqual(s[0].kind, .label)
        XCTAssertEqual(Set(s[0].contactIDs), [labelRep.id, second.id], "Everyone at the same organization is linked")
        XCTAssertEqual(s[1].kind, .radio)
        XCTAssertEqual(s[1].status, .won)
        XCTAssertEqual(s[1].website, "https://nightshiftradio.example")

        ws.targets.append(s[0])
        XCTAssertEqual(Targets.suggestions(in: ws).map(\.name), ["Night Shift Radio"])
    }

    // MARK: Reading a website

    func testFindsSubmissionPagesAndAddresses() {
        let html = """
        <html><head><meta property="og:site_name" content="Quiet Records"><meta name="description" content="An independent label for folk and ambient music."></head>
        <body>
          <a href="/about">About</a>
          <a href="/contact">Contact us</a>
          <a href="https://www.submithub.com/to/quiet">Send us music</a>
          <a href="/demos">Demo <b>submissions</b></a>
          <a href="mailto:demos@quietrecords.example?subject=Demo">Email demos</a>
          <a href="javascript:void(0)">submit</a>
          <p>Press: press@quietrecords.example · logo@2x.png · noreply@quietrecords.example</p>
        </body></html>
        """
        let f = Targets.findings(html: html, baseURL: "https://quietrecords.example/")
        XCTAssertEqual(f.submissionLinks.first, "https://quietrecords.example/demos", "Demo and submission pages come first")
        XCTAssertTrue(f.submissionLinks.contains("https://www.submithub.com/to/quiet"))
        XCTAssertEqual(f.submissionLinks.last, "https://quietrecords.example/contact", "A contact page is the fallback")
        XCTAssertFalse(f.submissionLinks.contains { $0.contains("about") || $0.hasPrefix("javascript") })
        XCTAssertEqual(f.emails, ["demos@quietrecords.example", "press@quietrecords.example"])

        let meta = LinkReader.parse(html: html, url: "https://quietrecords.example/")
        let t = Targets.target(from: meta, findings: f, now: TestDates.now)
        XCTAssertEqual(t.name, "Quiet Records")
        XCTAssertEqual(t.kind, .label)
        XCTAssertEqual(t.website, "https://quietrecords.example")
        XCTAssertEqual(t.submissionURL, "https://quietrecords.example/demos")
        XCTAssertEqual(t.submissionEmail, "demos@quietrecords.example")
        XCTAssertEqual(t.notes, "An independent label for folk and ambient music.")
    }

    func testGuessesKindFromNameAndDescription() {
        XCTAssertEqual(Targets.guessKind(name: "Night Shift Radio", description: "", url: ""), .radio)
        XCTAssertEqual(Targets.guessKind(name: "WRAS 88.5 FM", description: "", url: ""), .radio)
        XCTAssertEqual(Targets.guessKind(name: "Folk Talk", description: "A weekly podcast about songwriting", url: ""), .podcast)
        XCTAssertEqual(Targets.guessKind(name: "Shaky Knees", description: "Atlanta's rock festival", url: ""), .festival)
        XCTAssertEqual(Targets.guessKind(name: "The Lantern", description: "Music news and reviews", url: ""), .publication)
    }

    // MARK: CSV

    func testCSVRoundTripAndDuplicates() {
        var t = Target(name: "Quiet Records", kind: .label, status: .ready, tier: .dream)
        t.website = "https://quietrecords.example"
        t.submissionEmail = "demos@quietrecords.example"
        t.submissionPolicy = .open
        t.genres = ["Folk", "Ambient"]
        t.similarArtists = "Big Thief"
        t.tags = ["2027"]
        t.nextCheck = TestDates.day(2027, 1, 15)
        let csv = TargetCSV.export([t])
        let back = TargetCSV.preview(csv: csv, existing: [], now: TestDates.now)
        XCTAssertEqual(back.added.count, 1)
        let r = back.added[0]
        XCTAssertEqual(r.name, t.name)
        XCTAssertEqual(r.kind, .label)
        XCTAssertEqual(r.status, .ready)
        XCTAssertEqual(r.tier, .dream)
        XCTAssertEqual(r.submissionPolicy, .open)
        XCTAssertEqual(r.genres, ["Folk", "Ambient"])
        XCTAssertEqual(r.tags, ["2027"])
        XCTAssertEqual(r.nextCheck, t.nextCheck)
        XCTAssertEqual(r.website, t.website)

        let again = TargetCSV.preview(csv: csv, existing: [t])
        XCTAssertTrue(again.added.isEmpty)
        XCTAssertEqual(again.duplicates.count, 1)
    }

    func testCSVImportUnderstandsCommonColumns() {
        let csv = """
        Outlet,Category,Stage,URL,Email,Accepts Demos,Genre
        The Lantern,Blog,Want to pitch,thelantern.example/reviews,editor@thelantern.example,yes,"Folk, Americana"
        Quiet Records,Record label,not now,,,no,
        ,,,https://www.nightshiftradio.example,,,
        lantern,,,https://thelantern.example,,,
        ,,,,,,
        """
        let p = TargetCSV.preview(csv: csv, existing: [])
        XCTAssertEqual(p.added.map(\.name), ["The Lantern", "Quiet Records", "Nightshiftradio"])
        XCTAssertEqual(p.duplicates.count, 1, "Same website as a row above")
        XCTAssertEqual(p.skipped.count, 1)
        XCTAssertEqual(p.added[0].kind, .publication)
        XCTAssertEqual(p.added[0].status, .ready)
        XCTAssertEqual(p.added[0].website, "https://thelantern.example")
        XCTAssertEqual(p.added[0].submissionPolicy, .open)
        XCTAssertEqual(p.added[0].genres, ["Folk", "Americana"])
        XCTAssertEqual(p.added[1].kind, .label)
        XCTAssertEqual(p.added[1].status, .notNow)
        XCTAssertEqual(p.added[1].submissionPolicy, .closed)
    }

    // MARK: Storage, plan and pitches

    func testOlderFilesWithoutTargetsLoadAndTargetsUndo() throws {
        let ws = try TolerantDecoding.decodeWorkspace(Data(#"{"contacts":[]}"#.utf8))
        XCTAssertTrue(ws.targets.isEmpty)

        let partial = #"{"targets":[{"id":"\#(UUID().uuidString)","name":"Quiet Records"}]}"#
        let loaded = try TolerantDecoding.decodeWorkspace(Data(partial.utf8))
        XCTAssertEqual(loaded.targets.first?.name, "Quiet Records")
        XCTAssertEqual(loaded.targets.first?.status, .watching)
        XCTAssertEqual(loaded.targets.first?.contactIDs, [])

        var before = Workspace()
        before.targets = [Target(name: "A")]
        var after = before
        after.targets[0].status = .ready
        after.targets.append(Target(name: "B"))
        let changes = Workspace.diff(before, after)
        XCTAssertEqual(changes.count, 2)
        XCTAssertTrue(changes.allSatisfy { $0.kind == .targets })
        try after.revert(changes)
        XCTAssertEqual(after, before)
    }

    func testPlanNudges() {
        var (ws, t, editor) = workspace()
        ws.targets[0].nextCheck = TestDates.now.adding(days: -2)
        var label = Target(name: "Quiet Records", kind: .label, status: .ready)
        label.website = "https://quietrecords.example"
        ws.targets.append(label)
        var keys = Set(PlanGenerator.generate(for: ws, now: TestDates.now).recommendations.map(\.ruleKey))
        XCTAssertTrue(keys.contains("targets-check"))
        XCTAssertTrue(keys.contains("targets-way-in"), "Ready to pitch, but no one to pitch")
        XCTAssertFalse(keys.contains("targets-ready"))

        ws.targets[1].submissionEmail = "demos@quietrecords.example"
        ws.targets[0].status = .ready
        keys = Set(PlanGenerator.generate(for: ws, now: TestDates.now).recommendations.map(\.ruleKey))
        XCTAssertFalse(keys.contains("targets-way-in"))
        XCTAssertTrue(keys.contains("targets-ready"))

        ws.outreach = [Outreach(kind: .press, contactID: editor.id, status: .sent)]
        let recs = PlanGenerator.generate(for: ws, now: TestDates.now).recommendations
        let ready = recs.first { $0.ruleKey == "targets-ready" }
        XCTAssertEqual(ready?.title, "Pitch the 1 target you marked ready", "\(t.name) was pitched; only the label is left")
        XCTAssertEqual(ready?.destination, .targets)
    }

    func testLabelPitchDraft() {
        var ws = Workspace.onboarded()
        ws.pressKit.achievements = "Played Eddie's Attic.\nFeatured on Night Shift Radio."
        var rep = makeContact("Ana Ruiz", email: "ana@quiet.example", role: .label)
        rep.organization = "Quiet Records"
        let draft = Drafting.pitch(kind: .label, contact: rep, release: nil, profile: ws.profile, pressKit: ws.pressKit)
        XCTAssertTrue(draft.subject.contains("Quiet Records"))
        XCTAssertTrue(draft.body.hasPrefix("Hi Ana,") || draft.body.hasPrefix("Dear Ana,"))
        XCTAssertTrue(draft.body.contains("Played Eddie's Attic. Featured on Night Shift Radio."))
        XCTAssertTrue(draft.body.contains("[what you like about the label and its roster]"), "Leaves the personal part to the artist")
        XCTAssertEqual(OutreachKind.label.permission, .sendExternalMessage)
        XCTAssertEqual(OutreachKind.label.suggestedRoles, [.label])
        XCTAssertEqual(TargetKind.label.pitchKind, .label)
    }
}
