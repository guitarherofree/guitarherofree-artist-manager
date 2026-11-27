import Foundation

// MARK: - Connections

enum IntegrationStatus: Equatable {
    /// Works now, on this Mac, with no account needed.
    case builtIn
    /// Not connected. Manager supports it through files you import and export.
    case manual
    /// Needs an external account or credentials that this version doesn't connect to.
    case notConnected

    var label: String {
        switch self {
        case .builtIn: return "Built in"
        case .manual: return "Manual — import & export"
        case .notConnected: return "Not connected"
        }
    }
}

struct IntegrationInfo: Identifiable {
    var id: String
    var name: String
    var symbol: String
    var status: IntegrationStatus
    var usedFor: String
    var howItWorksNow: String
    var formats: [String]
    /// What a live connection would need. Empty for built-in features.
    var requires: String
    var destination: AppDestination?
}

enum IntegrationCatalog {
    static let all: [IntegrationInfo] = [
        IntegrationInfo(
            id: "mail-app", name: "Your mail app", symbol: "envelope.open", status: .builtIn,
            usedFor: "Pitches, follow-ups and reminders you've approved.",
            howItWorksNow: "Approved messages open as a new draft in your default mail app. You review and press Send yourself, then mark the message sent here.",
            formats: ["mailto"], requires: "", destination: .press),
        IntegrationInfo(
            id: "email-provider", name: "Email list provider", symbol: "paperplane.circle", status: .manual,
            usedFor: "Sending campaigns to subscribers, unsubscribe links, bounce handling.",
            howItWorksNow: "Import your list and per-campaign reports as CSV. Approved campaigns export as HTML/text plus a recipients CSV and a suppression list for your provider (for example Mailchimp, Kit, MailerLite or Bandcamp). Bounces and unsubscribes from report imports are applied here and never re-subscribed.",
            formats: ["CSV import", "CSV export", "HTML", "Plain text"],
            requires: "An account with your provider and an API key (OAuth for some providers). Sending would still require your approval for every campaign.",
            destination: .email),
        IntegrationInfo(
            id: "calendar", name: "Calendar apps", symbol: "calendar.badge.plus", status: .manual,
            usedFor: "Seeing shows, sessions, release days and deadlines alongside your personal calendar.",
            howItWorksNow: "Import .ics files from Calendar, Google Calendar or Outlook, and export your Manager calendar as .ics to subscribe to or import elsewhere.",
            formats: [".ics import", ".ics export"],
            requires: "Live two-way sync needs macOS Calendar access (EventKit) or a Google/Microsoft account.", destination: .calendar),
        IntegrationInfo(
            id: "distributor", name: "Distributor", symbol: "shippingbox", status: .manual,
            usedFor: "Delivering releases to stores and streaming services.",
            howItWorksNow: "Check metadata in Releases, then export a metadata CSV to copy into your distributor's upload form (DistroKid, CD Baby, TuneCore, AWAL and others). Mark the release delivered when the distributor confirms.",
            formats: ["Metadata CSV"],
            requires: "Most distributors don't offer public upload APIs to independent artists.", destination: .releases),
        IntegrationInfo(
            id: "rights", name: "PROs, The MLC and SoundExchange", symbol: "c.circle", status: .manual,
            usedFor: "Registering songs and recordings so royalties can be paid.",
            howItWorksNow: "Track memberships in Profile › Rights and export songwriter splits as CSV for registration portals. Registration tasks are added to each release timeline.",
            formats: ["Splits CSV"],
            requires: "These organizations use member portals rather than public APIs.", destination: .profile),
        IntegrationInfo(
            id: "analytics", name: "Streaming analytics", symbol: "chart.line.uptrend.xyaxis", status: .notConnected,
            usedFor: "Streams, saves and listener data to measure goals and campaigns.",
            howItWorksNow: "Record results in each release's 30-day review task and update your goals.",
            formats: [],
            requires: "Spotify for Artists, Apple Music for Artists and similar dashboards don't offer general public APIs for this data.", destination: .plan),
        IntegrationInfo(
            id: "social", name: "Social media", symbol: "bubble.left.and.bubble.right", status: .notConnected,
            usedFor: "Publishing announcement posts and teasers.",
            howItWorksNow: "Plan posts as tasks and calendar entries. You publish them yourself; Manager never posts.",
            formats: [],
            requires: "Each platform's developer account and OAuth. Publishing would always require your approval.", destination: .tasks),
        IntegrationInfo(
            id: "contacts-import", name: "Contact lists and media lists", symbol: "person.crop.rectangle.stack", status: .manual,
            usedFor: "Bringing in industry contacts, press lists and playlist curators.",
            howItWorksNow: "Pick people from the Contacts app (read only), or import a vCard or a CSV from a spreadsheet or PR database. Existing contacts are only filled in, never overwritten.",
            formats: ["Contacts app", "vCard import", "CSV import", "CSV export"], requires: "", destination: .contacts),
        IntegrationInfo(
            id: "coverage-links", name: "Web pages (coverage and target links)", symbol: "quote.bubble", status: .builtIn,
            usedFor: "Filling in coverage and targets from a link, keeping a copy of coverage pages, and checking links still work.",
            howItWorksNow: "When you add or check a coverage link, Manager opens that one page the way a browser would and reads the outlet, headline, writer, date and review score the site publishes for link previews. When you look up a target's website, it reads the home page for the name, what they do, and any submissions page or address listed there. Nothing is fetched in the background and nothing is posted. Pages behind a paywall or sign-in can't be read: fill those in yourself, or attach a PDF or screenshot.",
            formats: ["Saved page copies (HTML)", "Attachments (PDF, images, audio, video)", "CSV import", "CSV export"],
            requires: "", destination: .coverage),
        IntegrationInfo(
            id: "github-updates", name: "Software updates (GitHub releases)", symbol: "arrow.down.circle", status: .builtIn,
            usedFor: "Keeping Manager up to date.",
            howItWorksNow: "Checks this app's GitHub releases shortly after it opens and then daily, and downloads new versions in the background. Before installing it checks the download against the checksum GitHub publishes, confirms it's Manager at the expected version, and verifies its code signature. It installs when you quit or click Restart Now, and keeps the previous version in case you need to go back.",
            formats: [], requires: "Nothing while the repository is public. A read-only GitHub token only if it becomes private.", destination: nil),
        IntegrationInfo(
            id: "notifications", name: "macOS notifications", symbol: "bell.badge", status: .builtIn,
            usedFor: "Telling you when approvals are waiting and deadlines are close.",
            howItWorksNow: "Uses Notification Center when the app runs as a packaged .app. Choose what to be told about in Profile › Communication.",
            formats: [], requires: "", destination: .profile)
    ]
}

// MARK: - Roadmap

struct RoadmapArea: Identifiable {
    var id: String
    var title: String
    var symbol: String
    var availableNow: [String]
    var next: [String]
    var needsExternalService: [String]
}

enum Roadmap {
    static let areas: [RoadmapArea] = [
        RoadmapArea(
            id: "live", title: "Live shows and touring", symbol: "music.mic",
            availableNow: ["Shows, rehearsals and travel on the calendar, with conflict checks against your availability",
                           "Booking inquiries drafted from your profile and sent only after approval",
                           "Venue, promoter and booking-agent contacts with follow-up dates",
                           "Reminders to the people attached to an upcoming show"],
            next: ["Offers with guarantee, door split, radius clause and deadline, accepted only with your approval",
                   "Routing view and tour budget (travel, lodging, crew, per diems) against expected income",
                   "Advancing checklist per show: load-in, set times, hospitality, tech rider",
                   "Merch inventory and night-of settlement sheets"],
            needsExternalService: ["Ticketing and venue system data"]),
        RoadmapArea(
            id: "finance", title: "Finances and rights", symbol: "dollarsign.circle",
            availableNow: ["Release budgets with planned, approved and paid costs; spending always needs approval",
                           "Annual budget tracking and over-budget warnings in your plan",
                           "PRO, mechanical and neighboring-rights memberships with status",
                           "Songwriter splits and a splits export for registrations"],
            next: ["Income ledger (streaming, shows, merch, sync, royalties) and monthly cash flow",
                   "Per-song registration status across each organization",
                   "Royalty statement imports and a collection-gap report",
                   "Exports for your accountant"],
            needsExternalService: ["Distributor and royalty statement downloads", "Bank feeds"]),
        RoadmapArea(
            id: "sync", title: "Sync and partnerships", symbol: "film",
            availableNow: ["Music supervisors, sync agents and brands as contacts",
                           "Sync submissions and partnership pitches drafted and tracked as outreach, sent only after approval"],
            next: ["Opportunity pipeline: brief, deadline, fee, media, territory and term",
                   "One-stop clearance checklist built from your splits and master ownership",
                   "Instrumental and stem asset tracking per track",
                   "Terms review checklist before anything is accepted"],
            needsExternalService: ["Sync licensing platforms"]),
        RoadmapArea(
            id: "marketing", title: "Marketing and media", symbol: "megaphone",
            availableNow: ["Release campaign timelines with dated marketing tasks",
                           "Press, radio and playlist pitch drafts, approval, sending via your mail app and response tracking",
                           "Coverage: reviews, articles, interviews, premieres, radio, podcasts, video and mentions, filled in from a link, with saved page copies, attachments, link checks, CSV import/export and pull quotes for the press kit",
                           "Targets: publications, labels, radio, podcasts, playlists and festivals to pitch or watch, with submission details, people there, pitches and coverage, look-again dates and CSV import/export"],
            next: ["Content calendar with post drafts per platform",
                   "Ad budget pacing per campaign",
                   "Interview prep sheets built from your bio, the release and the outlet's past coverage"],
            needsExternalService: ["Social platform publishing APIs", "Ad platform APIs",
                                   "A news or web-mention alert service, to find new coverage automatically"]),
        RoadmapArea(
            id: "daily", title: "Daily support and creative feedback", symbol: "sun.max",
            availableNow: ["Today view with approvals, overdue work, conflicts and next steps",
                           "Conversation prep built from a contact's history",
                           "Public statement framework for PR issues"],
            next: ["Tracklist and setlist feedback (flow, key and tempo changes, runtime), always framed around your stated preferences",
                   "Artwork checklist against distributor specs and your visual identity",
                   "Demo feedback notes you can request per track"],
            needsExternalService: ["An AI model service for written feedback on audio and artwork, if you choose to connect one"]),
        RoadmapArea(
            id: "platform", title: "Platform", symbol: "macwindow",
            availableNow: ["Local storage with daily backups, full export and restore",
                           "Activity log with undo for reversible changes",
                           "In-app updates from GitHub releases, checked against GitHub's checksum and the app's code signature"],
            next: ["Live connections for email providers and Calendar (EventKit), each with visible permissions",
                   "iCloud sync across your Macs",
                   "Shared access for a team member with their own permissions"],
            needsExternalService: ["Apple Developer ID for notarized builds", "iCloud container"])
    ]
}
