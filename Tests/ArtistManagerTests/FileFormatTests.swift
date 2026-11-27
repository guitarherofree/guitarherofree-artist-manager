import XCTest
@testable import ArtistManager

final class FileFormatTests: XCTestCase {
    // MARK: CSV

    func testCSVHandlesQuotesNewlinesBOMAndCRLF() {
        let text = "\u{FEFF}Name,Notes\r\n\"Vale, Juniper\",\"Said \"\"yes\"\"\nthen left\"\r\nSam,plain\r\n\r\n"
        let rows = CSV.parse(text)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], ["Name", "Notes"])
        XCTAssertEqual(rows[1], ["Vale, Juniper", "Said \"yes\"\nthen left"])
        XCTAssertEqual(rows[2], ["Sam", "plain"])
    }

    func testCSVHeadersAreNormalized() {
        let table = CSV.parseTable("Email Address,First Name ,OPTIN_TIME\na@b.co,Ada,x\n")
        XCTAssertEqual(table.headers, ["email_address", "first_name", "optin_time"])
        XCTAssertEqual(table.rows.first?["first_name"], "Ada")
    }

    func testCSVWriteEscapesAndBlocksFormulaInjection() {
        let out = CSV.write(headers: ["a", "b"], rows: [["=HYPERLINK(\"x\")", "-42"], ["a,b", "line\nbreak"]])
        XCTAssertTrue(out.contains("\"'=HYPERLINK(\"\"x\"\")\""), out)
        XCTAssertTrue(out.contains(",-42"), "Plain negative numbers are left alone")
        XCTAssertTrue(out.contains("\"a,b\""))
        let back = CSV.parse(out)
        XCTAssertEqual(back[2], ["a,b", "line\nbreak"])
    }

    func testDateParsingFormats() {
        XCTAssertNotNil(DateParsing.parse("2026-05-01T10:00:00Z"))
        XCTAssertNotNil(DateParsing.parse("2026-05-01 10:00:00"))
        XCTAssertNotNil(DateParsing.parse("05/01/2026"))
        XCTAssertNotNil(DateParsing.parse("1767225600"))
        XCTAssertNil(DateParsing.parse("soon"))
        XCTAssertNil(DateParsing.parse(""))
    }

    // MARK: Contacts

    func testContactImportFillsGapsOnlyAndMatchesRoles() {
        let existing = [Contact(name: "Ana Ruiz", organization: "", role: .journalist, email: "ana@zine.com", notes: "Met at SXSW")]
        let csv = "Name,Outlet,Email,Role,Notes,Tags\nAna Ruiz,Zine,ANA@zine.com,Editor,Should not overwrite,indie\nBo,Late Night Radio,bo@radio.fm,DJ,,\n,,,,,\n"
        let preview = ContactCSV.preview(csv: csv, existing: existing, defaultRole: .other, tagsToAdd: ["Media list"])
        XCTAssertEqual(preview.updated.count, 1)
        XCTAssertEqual(preview.updated[0].organization, "Zine")
        XCTAssertEqual(preview.updated[0].notes, "Met at SXSW", "Existing notes are never overwritten")
        XCTAssertEqual(Set(preview.updated[0].tags), ["indie", "Media list"])
        XCTAssertEqual(preview.added.count, 1)
        XCTAssertEqual(preview.added[0].role, .radio)
        XCTAssertEqual(preview.skipped.count, 1)
    }

    func testContactExportImportRoundTrip() {
        let contacts = [Contact(name: "Kim", organization: "Agency", role: .bookingAgent, email: "kim@agency.com", isTeamMember: true)]
        let preview = ContactCSV.preview(csv: ContactCSV.export(contacts), existing: [], defaultRole: .other, tagsToAdd: [])
        XCTAssertEqual(preview.added.first?.role, .bookingAgent)
        XCTAssertEqual(preview.added.first?.isTeamMember, true)
    }

    // MARK: iCalendar

    func testICSRoundTripAndDedupe() {
        let start = TestDates.day(2026, 9, 12, hour: 20)
        let show = CalendarEvent(title: "The Earl; Atlanta, GA", kind: .show, start: start, end: start.adding(hours: 2),
                                 location: "488 Flat Shoals Ave", notes: "Load-in 6pm\nSoundcheck 7pm")
        let releaseDay = CalendarEvent(title: "Release day", kind: .release, start: TestDates.day(2026, 9, 18).startOfDay,
                                       end: TestDates.day(2026, 9, 18).startOfDay, isAllDay: true)
        let text = ICalendar.export([show, releaseDay], calendarName: "Juniper")
        XCTAssertTrue(text.contains("SUMMARY:The Earl\\; Atlanta\\, GA"))
        XCTAssertTrue(text.contains("DTSTART;VALUE=DATE:20260918"))
        XCTAssertTrue(text.contains("DTEND;VALUE=DATE:20260919"), "All-day end dates are exclusive")
        XCTAssertTrue(text.components(separatedBy: "\r\n").allSatisfy { $0.count <= 75 }, "Lines are folded")

        let parsed = ICalendar.parse(text)
        XCTAssertEqual(parsed.count, 2)
        let back = ICalendar.calendarEvents(from: parsed, existing: [])
        let parsedShow = try! XCTUnwrap(back.first { !$0.isAllDay })
        XCTAssertEqual(parsedShow.title, "The Earl; Atlanta, GA")
        XCTAssertEqual(parsedShow.notes, "Show\nLoad-in 6pm\nSoundcheck 7pm")
        XCTAssertEqual(parsedShow.start, start)
        let parsedDay = try! XCTUnwrap(back.first { $0.isAllDay })
        XCTAssertTrue(parsedDay.start.isSameDay(as: releaseDay.start))
        XCTAssertTrue(parsedDay.end.isSameDay(as: releaseDay.start), "Exclusive end converted back")

        // Importing our own export again adds nothing.
        XCTAssertTrue(ICalendar.calendarEvents(from: parsed, existing: [show, releaseDay]).isEmpty)
        // Importing the same file twice adds nothing the second time.
        XCTAssertTrue(ICalendar.calendarEvents(from: parsed, existing: back).isEmpty)
    }

    func testImportedEventsKeepTheirUIDWhenExported() {
        let ics = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:abc-123@google.com\r\nDTSTART;TZID=America/New_York:20261010T190000\r\nDTEND;TZID=America/New_York:20261010T210000\r\nSUMMARY:Dinner\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
        let events = ICalendar.calendarEvents(from: ICalendar.parse(ics), existing: [])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].sourceKey, "ics:abc-123@google.com")
        XCTAssertTrue(ICalendar.export(events, calendarName: "x").contains("UID:abc-123@google.com"))
        let comps = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "America/New_York")!, from: events[0].start)
        XCTAssertEqual(comps.hour, 19)
    }

    // MARK: Release metadata exports

    func testMetadataAndSplitsExports() {
        var release = makeRelease(date: TestDates.day(2026, 9, 18))
        release.upc = "123456789012"
        var track = Track(title: "Northern Lights", isrc: "USABC2600001", durationSeconds: 215)
        track.writers = [Split(name: "Juniper Vale", share: 60, pro: "BMI"), Split(name: "Sam Lee", share: 40, pro: "ASCAP")]
        release.tracks = [track]
        let metadata = ReleaseExport.metadataCSV(release, artistName: "Juniper Vale")
        XCTAssertTrue(metadata.contains("3:35"))
        XCTAssertTrue(metadata.contains("2026-09-18"))
        let splits = CSV.parse(ReleaseExport.splitsCSV(release))
        XCTAssertEqual(splits.count, 3)
        XCTAssertEqual(splits[1][3], "Juniper Vale")
        XCTAssertEqual(splits[2][5], "40")
    }

    // MARK: Press kit

    func testPressKitHTMLEscapesAndOnlyAllowsSafeLinks() {
        var ws = Workspace.onboarded()
        ws.profile.artistName = "Juniper <Vale>"
        ws.pressKit.featuredTracks = [FeaturedTrack(title: "Song", url: "javascript:alert(1)"), FeaturedTrack(title: "Real", url: "https://example.com")]
        ws.pressKit.bookingContact = ContactCard(name: "Kim", email: "kim@agency.com")
        ws.coverage = [Coverage(outlet: "Zine", title: "Review", quote: "A <b>triumph</b>", includeInPressKit: true)]
        let html = PressKitRenderer.htmlDocument(workspace: ws, photoData: { _ in nil })
        XCTAssertTrue(html.contains("Juniper &lt;Vale&gt;"))
        XCTAssertFalse(html.contains("javascript:"))
        XCTAssertTrue(html.contains("href=\"https://example.com\""))
        XCTAssertTrue(html.contains("A &lt;b&gt;triumph&lt;/b&gt;"))
        XCTAssertTrue(html.contains("mailto:kim@agency.com"))
        let md = PressKitRenderer.markdown(workspace: ws)
        XCTAssertTrue(md.contains("## Booking"))
    }

    func testPressKitScore() {
        var ws = Workspace.onboarded()
        let before = PressKitScore.evaluate(ws)
        XCTAssertLessThan(before.score, 0.5)
        XCTAssertTrue(before.missing.contains("press photos"))
        ws.pressKit.photos = [PressPhoto(fileName: "a.jpg", photographerCredit: "Lee")]
        XCTAssertGreaterThan(PressKitScore.evaluate(ws).score, before.score)
    }
}
