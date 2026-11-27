import Foundation
@testable import ArtistManager

/// Fixed dates so tests don't depend on today.
enum TestDates {
    static let calendar = Calendar.current

    static func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Wednesday, 1 July 2026, noon local time.
    static let now = day(2026, 7, 1)
}

extension Workspace {
    /// A workspace that has finished onboarding, with a name and a goal.
    static func onboarded(goals: [GoalCategory] = [.streaming]) -> Workspace {
        var ws = Workspace()
        ws.profile.artistName = "Juniper Vale"
        ws.profile.genres = ["Indie folk"]
        ws.profile.location = "Atlanta, GA"
        ws.profile.bioShort = "Juniper Vale writes late-night folk songs."
        ws.profile.onboardingCompleted = true
        ws.goals = goals.map { CareerGoal(title: "Goal \($0.rawValue)", category: $0) }
        return ws
    }
}

func makeContact(_ name: String, email: String = "", role: ContactRole = .journalist, team: Bool = false) -> Contact {
    Contact(name: name, organization: "Outlet", role: role, email: email, isTeamMember: team)
}

func makeRelease(title: String = "Northern Lights", date: Date?, type: ReleaseType = .single) -> Release {
    var r = Release()
    r.title = title
    r.type = type
    r.releaseDate = date
    return r
}
