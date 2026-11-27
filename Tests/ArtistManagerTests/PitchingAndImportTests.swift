import XCTest
@testable import ArtistManager

final class PitchingAndImportTests: XCTestCase {
    // MARK: Spotify editorial pitch

    func testEditorialPitchIsPrefilledAndFitsSpotifysLimit() {
        var ws = Workspace.onboarded()
        ws.profile.genres = ["Indie folk", "Americana", "Singer-songwriter", "Chamber pop", "Lo-fi"]
        ws.profile.soundDescription = String(repeating: "Warm, close-mic'd acoustic guitar and layered harmonies. ", count: 10)
        ws.profile.audience.comparableArtists = "Adrianne Lenker, Phoebe Bridgers"
        var release = makeRelease(date: TestDates.now.adding(days: 30))
        release.tracks = [Track(title: "Northern Lights")]
        let pitch = Drafting.editorialPitch(for: release, profile: ws.profile, subscriberCount: 420)
        XCTAssertEqual(pitch.trackTitle, "Northern Lights")
        XCTAssertEqual(pitch.trackID, release.tracks[0].id)
        XCTAssertEqual(pitch.primaryGenre, "Indie folk")
        XCTAssertEqual(pitch.subgenres, ["Americana", "Singer-songwriter", "Chamber pop"], "At most three subgenres")
        XCTAssertLessThanOrEqual(pitch.description.count, EditorialPitch.maxDescription)
        XCTAssertTrue(pitch.description.contains("420 subscribers"))
        XCTAssertEqual(pitch.hometown, "Atlanta, GA")
    }

    func testEditorialPitchChecks() {
        var pitch = EditorialPitch(trackTitle: "Song", primaryGenre: "Indie", moods: ["Chill"], hometown: "Atlanta", description: "A song.")
        XCTAssertTrue(pitch.issues(releaseDate: TestDates.now.adding(days: 30), now: TestDates.now).isEmpty)

        let soon = pitch.issues(releaseDate: TestDates.now.adding(days: 5), now: TestDates.now)
        XCTAssertTrue(soon.contains { $0.id == "late" && $0.level == .warning }, "Under 7 days misses Release Radar")
        XCTAssertTrue(pitch.issues(releaseDate: TestDates.now.adding(days: 14), now: TestDates.now).contains { $0.id == "early" })
        XCTAssertTrue(pitch.issues(releaseDate: TestDates.now.adding(days: -1), now: TestDates.now).contains { $0.id == "released" && $0.level == .error })

        pitch.description = String(repeating: "x", count: 501)
        pitch.subgenres = ["a", "b", "c", "d"]
        let ids = Set(pitch.issues(releaseDate: TestDates.now.adding(days: 30), now: TestDates.now).map(\.id))
        XCTAssertTrue(ids.isSuperset(of: ["length", "subgenres"]))
        XCTAssertEqual(EditorialPitch.deadline(for: TestDates.day(2026, 9, 18)), TestDates.day(2026, 9, 11).startOfDay)
    }

    func testEditorialApprovalShowsTheFormAndNeverSubmits() {
        var ws = Workspace.onboarded()
        let release = makeRelease(date: TestDates.now.adding(days: 30))
        ws.releases = [release]
        var item = Outreach(kind: .spotifyEditorial, releaseID: release.id, subject: "Spotify editorial pitch", body: "")
        item.editorial = EditorialPitch(trackTitle: "Northern Lights", primaryGenre: "Indie folk", description: "Hello editors.")
        ws.outreach = [item]
        let request = ApprovalService.requestForOutreach(item, in: &ws)
        XCTAssertEqual(request.kind, .sendPressOutreach, "Pitching Spotify always needs approval")
        XCTAssertTrue(request.title.contains("Northern Lights"))
        XCTAssertTrue(request.preview.contains("Main genre: Indie folk"))
        XCTAssertTrue(request.preview.contains("Hello editors."))
        XCTAssertFalse(request.preview.contains("To:"), "There's no email recipient")
        ApprovalService.approve(request.id, in: &ws)
        XCTAssertEqual(ws.outreach[0].status, .approved)
        XCTAssertNil(ws.outreach[0].sentAt)
    }

    func testPlanRecommendsSpotifyPitchAtTheRightTime() {
        var ws = Workspace.onboarded()
        let release = makeRelease(date: TestDates.now.adding(days: 30))
        ws.releases = [release]
        let recs = PlanGenerator.generate(for: ws, now: TestDates.now).recommendations
        let rec = try! XCTUnwrap(recs.first { $0.ruleKey == "spotify-pitch-\(release.id)" })
        XCTAssertEqual(rec.destinationTab, "playlists")
        XCTAssertEqual(rec.priority, .high)

        var pitch = Outreach(kind: .spotifyEditorial, releaseID: release.id, subject: "x", body: "", status: .awaitingApproval)
        pitch.editorial = EditorialPitch()
        ws.outreach = [pitch]
        XCTAssertFalse(PlanGenerator.generate(for: ws, now: TestDates.now).activeRuleKeys.contains("spotify-pitch-\(release.id)"))

        ws.outreach = []
        ws.releases[0].releaseDate = TestDates.now.adding(days: 3)
        XCTAssertFalse(PlanGenerator.generate(for: ws, now: TestDates.now).activeRuleKeys.contains("spotify-pitch-\(release.id)"),
                       "Too late for Release Radar")
    }

    // MARK: Review requests and batches

    func testReviewRequestTemplate() {
        let ws = Workspace.onboarded()
        var release = makeRelease(date: TestDates.day(2026, 9, 18), type: .ep)
        release.tracks = [Track(title: "One"), Track(title: "Two")]
        let writer = Contact(name: "Ana Ruiz", organization: "Paste", role: .journalist, email: "ana@paste.com")
        let draft = Drafting.pitch(kind: .review, contact: writer, release: release, profile: ws.profile, pressKit: ws.pressKit)
        XCTAssertTrue(draft.subject.hasPrefix("For review:"))
        XCTAssertTrue(draft.body.hasPrefix("Hi Ana,"))
        XCTAssertTrue(draft.body.contains("Paste to consider"))
        XCTAssertTrue(draft.body.contains("Tracklist: One · Two"))
        XCTAssertTrue(draft.body.contains("[private streaming link]"))
    }

    func testBatchDraftsOnePerContactAndSkipsRepeats() {
        let ws = Workspace.onboarded()
        let release = makeRelease(date: TestDates.now.adding(days: 40))
        let a = Contact(name: "Ana", role: .journalist, email: "a@zine.com")
        let b = Contact(name: "Bo", role: .journalist, email: "b@blog.com")
        let earlier = Outreach(kind: .review, contactID: b.id, releaseID: release.id, subject: "old", body: "")
        let result = Drafting.batch(kind: .review, contacts: [a, b], release: release, existing: [earlier],
                                    profile: ws.profile, pressKit: ws.pressKit, now: TestDates.now)
        XCTAssertEqual(result.drafts.count, 1)
        XCTAssertEqual(result.drafts[0].contactID, a.id)
        XCTAssertEqual(result.drafts[0].status, .draft)
        XCTAssertTrue(result.drafts[0].body.hasPrefix("Hi Ana,"))
        XCTAssertEqual(result.skipped.map(\.id), [b.id])
    }

    func testApproveAllRecordsEachDecision() {
        var ws = Workspace.onboarded()
        let items = (0..<3).map { Outreach(kind: .review, subject: "Pitch \($0)", body: "Hi") }
        ws.outreach = items
        let ids = items.map { ApprovalService.requestForOutreach($0, in: &ws).id }
        ApprovalService.approveAll(ids, in: &ws, now: TestDates.now)
        XCTAssertTrue(ws.outreach.allSatisfy { $0.status == .approved && $0.sentAt == nil })
        XCTAssertTrue(ws.approvals.allSatisfy { $0.state == .approved && $0.decidedAt == TestDates.now })
    }

    func testTimelineIncludesReviewAndSpotifySteps() {
        let tasks = ReleaseTimeline.missingTasks(for: makeRelease(date: TestDates.day(2026, 9, 18)), existing: [], actor: .artist)
        let keys = tasks.compactMap(\.templateKey).map { $0.components(separatedBy: ":").last ?? "" }
        XCTAssertTrue(keys.contains("review-pitches"))
        XCTAssertTrue(keys.contains("editorial-pitch"))
    }

    // MARK: Contacts from vCard

    func testAppleContactsVCard() {
        let vcf = """
        BEGIN:VCARD\r
        VERSION:3.0\r
        PRODID:-//Apple Inc.//macOS 15.0//EN\r
        N:Ruiz;Ana;;;\r
        FN:Ana Ruiz\r
        ORG:Paste Magazine;Music\r
        TITLE:Music Editor\r
        item1.EMAIL;type=INTERNET;type=pref:ana@paste.com\r
        EMAIL;type=INTERNET;type=HOME:ana.ruiz@gmail.com\r
        TEL;type=CELL;type=VOICE:(404) 555-0101\r
        item2.URL;type=pref:https://pastemagazine.com\r
        ADR;type=WORK;type=pref:;;123 Main St;Atlanta;GA;30303;United States\r
        NOTE:Met at SXSW\\nLoves folk\r
        CATEGORIES:Press,Indie\r
        END:VCARD\r
        BEGIN:VCARD\r
        VERSION:3.0\r
        FN:The Earl\r
        ORG:The Earl\r
        EMAIL:booking@theearl.com\r
        TITLE:Talent Buyer\r
        END:VCARD\r
        BEGIN:VCARD\r
        VERSION:3.0\r
        FN:\r
        END:VCARD\r
        """
        let contacts = VCard.contacts(from: vcf, defaultRole: .other)
        XCTAssertEqual(contacts.count, 2, "Empty cards are dropped")
        let ana = contacts[0]
        XCTAssertEqual(ana.name, "Ana Ruiz")
        XCTAssertEqual(ana.organization, "Paste Magazine")
        XCTAssertEqual(ana.email, "ana@paste.com", "The preferred address wins")
        XCTAssertEqual(ana.phone, "(404) 555-0101")
        XCTAssertEqual(ana.website, "https://pastemagazine.com")
        XCTAssertEqual(ana.location, "Atlanta, GA")
        XCTAssertEqual(ana.role, .journalist)
        XCTAssertEqual(ana.tags, ["Press", "Indie"])
        XCTAssertTrue(ana.notes.contains("Met at SXSW\nLoves folk"))
        let venue = contacts[1]
        XCTAssertEqual(venue.name, "", "Company cards keep the company as the organization only")
        XCTAssertEqual(venue.organization, "The Earl")
        XCTAssertEqual(venue.role, .promoter)
    }

    func testVCard21QuotedPrintableAndFolding() {
        let vcf = "BEGIN:VCARD\nVERSION:2.1\nN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:Mart=C3=ADnez;Jos=C3=A9\nEMAIL;PREF;INTERNET:jose@example.com\nNOTE:A long note that is\n  folded onto the next line\nEND:VCARD\n"
        let contacts = VCard.contacts(from: vcf, defaultRole: .playlistCurator)
        XCTAssertEqual(contacts.first?.name, "José Martínez")
        XCTAssertEqual(contacts.first?.email, "jose@example.com")
        XCTAssertEqual(contacts.first?.notes, "A long note that is folded onto the next line")
        XCTAssertEqual(contacts.first?.role, .playlistCurator, "No title, so the chosen default role applies")
    }

    func testVCardImportFillsGapsWithoutOverwriting() {
        let existing = [Contact(name: "Ana Ruiz", organization: "", role: .journalist, email: "ANA@paste.com", notes: "Mine")]
        let vcf = "BEGIN:VCARD\nFN:Ana Ruiz\nORG:Paste\nEMAIL:ana@paste.com\nNOTE:Theirs\nEND:VCARD\nBEGIN:VCARD\nFN:Bo\nEMAIL:bo@radio.fm\nEND:VCARD\nBEGIN:VCARD\nFN:Bo again\nEMAIL:BO@radio.fm\nEND:VCARD\n"
        let preview = VCard.preview(vcf: vcf, existing: existing, defaultRole: .other, tagsToAdd: ["From Contacts"])
        XCTAssertEqual(preview.totalRows, 3)
        XCTAssertEqual(preview.updated.count, 1)
        XCTAssertEqual(preview.updated[0].organization, "Paste")
        XCTAssertEqual(preview.updated[0].notes, "Mine")
        XCTAssertTrue(preview.updated[0].tags.contains("From Contacts"))
        XCTAssertEqual(preview.added.map(\.email), ["bo@radio.fm"])
        XCTAssertEqual(preview.skipped.count, 1, "The second Bo is a duplicate")
    }

    func testMergeAppliesDefaultRoleOnlyWhenUnknown() {
        let candidates = [(label: "A", contact: Contact(name: "A", role: .other)), (label: "B", contact: Contact(name: "B", role: .venue))]
        let preview = ContactImport.merge(candidates, existing: [], tagsToAdd: [], markAsTeam: false, defaultRole: .journalist)
        XCTAssertEqual(preview.added.map(\.role), [.journalist, .venue])
    }
}
