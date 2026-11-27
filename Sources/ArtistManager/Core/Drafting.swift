import Foundation

/// Template-based drafting. Everything produced here is a draft for the artist to edit and approve.
enum Drafting {
    static func greeting(for contact: Contact?, tone: DraftTone) -> String {
        let first = contact?.name.split(separator: " ").first.map(String.init) ?? ""
        switch tone {
        case .professional: return first.isEmpty ? "Hello," : "Dear \(first),"
        case .brief: return first.isEmpty ? "Hi," : "Hi \(first),"
        case .warm, .playful: return first.isEmpty ? "Hi there," : "Hi \(first),"
        }
    }

    static func signature(_ profile: ArtistProfile) -> String {
        var lines: [String] = []
        let signOff = profile.communication.signOff.isBlank ? "Thanks," : profile.communication.signOff
        lines.append(signOff)
        lines.append(profile.displayName)
        if !profile.links.website.isBlank { lines.append(profile.links.website) }
        return lines.joined(separator: "\n")
    }

    static func releaseLink(_ release: Release?) -> String {
        guard let release else { return "" }
        if !release.smartLinkURL.isBlank { return release.smartLinkURL }
        return release.preSaveURL
    }

    static func pitch(kind: OutreachKind, contact: Contact?, release: Release?, profile: ArtistProfile, pressKit: PressKit) -> (subject: String, body: String) {
        let tone = profile.communication.draftTone
        let name = profile.displayName
        let title = release?.title ?? "my new music"
        let typeLabel = release?.type.label.lowercased() ?? "release"
        let dateText = release?.releaseDate.map { $0.formatted(date: .long, time: .omitted) } ?? "soon"
        let genre = release.map { $0.primaryGenre.isBlank ? profile.genres.first ?? "" : $0.primaryGenre } ?? (profile.genres.first ?? "")
        let link = releaseLink(release)
        let hook = pressKit.headline.isBlank ? profile.bioShort : pressKit.headline
        var subject: String
        var paragraphs: [String] = [greeting(for: contact, tone: tone)]

        switch kind {
        case .press, .radio:
            subject = "\(name) — “\(title)” (\(typeLabel), out \(dateText))"
            paragraphs.append("I'm \(name)\(genre.isBlank ? "" : ", a \(genre.lowercased()) artist")\(profile.location.isBlank ? "" : " from \(profile.location)"). My new \(typeLabel) “\(title)” comes out \(dateText), and I think it could be a fit for \(contact?.organization.isBlank == false ? contact!.organization : "you").")
            if !hook.isBlank { paragraphs.append(hook) }
            if !link.isBlank { paragraphs.append("Private listen / pre-save: \(link)") }
            paragraphs.append("Happy to send a press kit, high-res photos, or set up an interview. Coverage ideas: a premiere, review, or feature.")
        case .review:
            let outlet = contact?.organization.isBlank == false ? contact!.organization : "your outlet"
            subject = "For review: \(name) — “\(title)” (\(typeLabel), out \(dateText))"
            paragraphs.append("I'm \(name)\(genre.isBlank ? "" : ", a \(genre.lowercased()) artist")\(profile.location.isBlank ? "" : " from \(profile.location)"). I'd love for \(outlet) to consider my new \(typeLabel) “\(title)” for review. It comes out \(dateText).")
            if !hook.isBlank { paragraphs.append(hook) }
            if release?.tracks.count ?? 0 > 1 {
                paragraphs.append("Tracklist: " + (release?.tracks.map(\.title).filter { !$0.isBlank }.joined(separator: " · ") ?? ""))
            }
            paragraphs.append("Private stream: \(link.isBlank ? "[private streaming link]" : link)")
            paragraphs.append("Press release, photos and credits: \(profile.links.website.isBlank ? "[link to your press kit]" : profile.links.website)")
            paragraphs.append("Please keep any review until release day. I'm happy to send lyrics or answer questions for the piece.")
        case .playlist:
            subject = "Submission: \(name) — “\(title)”"
            paragraphs.append("I'd love for you to consider “\(title)” for your playlist\(contact?.organization.isBlank == false ? " on \(contact!.organization)" : "").\(genre.isBlank ? "" : " It's \(genre.lowercased())")\(profile.audience.comparableArtists.isBlank ? "." : " and sits well next to \(profile.audience.comparableArtists).")")
            if !link.isBlank { paragraphs.append("Listen: \(link)") }
            paragraphs.append("No worries if it isn't a fit — thanks for listening.")
        case .spotifyEditorial:
            subject = "Spotify editorial pitch: “\(title)”"
            paragraphs = [editorialDescription(release: release, profile: profile, subscriberCount: 0)]
            return (subject, paragraphs.joined(separator: "\n\n"))
        case .label:
            let org = contact?.organization.isBlank == false ? contact!.organization : "your label"
            subject = "\(name)\(genre.isBlank ? "" : " (\(genre.lowercased()))") — music for \(org) to consider"
            paragraphs.append("I'm \(name)\(genre.isBlank ? "" : ", a \(genre.lowercased()) artist")\(profile.location.isBlank ? "" : " from \(profile.location)"). I've been following \(org) [what you like about the label and its roster], and I think my music could be a fit.")
            if !hook.isBlank { paragraphs.append(hook) }
            if !profile.audience.comparableArtists.isBlank { paragraphs.append("For fans of \(clip(profile.audience.comparableArtists, to: 120)).") }
            paragraphs.append("Listen: \(link.isBlank ? (profile.links.website.isBlank ? "[private streaming link]" : profile.links.website) : link)")
            paragraphs.append(pressKit.achievements.isBlank
                ? "So far: [releases, listeners, shows, press — two or three highlights]."
                : "So far: \(clip(pressKit.achievements.replacingOccurrences(of: "\n", with: " "), to: 300))")
            paragraphs.append("I'm looking for [a label partner for my next release / help with distribution and marketing / a conversation]. Would you be open to a listen?")
        case .booking:
            subject = "Booking inquiry: \(name)"
            paragraphs.append("I'm \(name)\(profile.location.isBlank ? "" : ", based in \(profile.location)"), and I'm looking for dates\(contact?.organization.isBlank == false ? " at \(contact!.organization)" : ""). \(hook)")
            if !profile.links.website.isBlank { paragraphs.append("More about me: \(profile.links.website)") }
            paragraphs.append("Could we talk about availability and what you look for in a booking?")
        case .sync:
            subject = "Music for sync: \(name)"
            paragraphs.append("I write and record \(genre.isBlank ? "original music" : genre.lowercased()) and control my masters and publishing\(profile.rightsMemberships.isEmpty ? "" : " (one-stop clearance where noted)"). I'd like to share a few tracks for your current projects.")
            if !link.isBlank { paragraphs.append("Listen: \(link)") }
            paragraphs.append("Instrumentals and stems are available on request.")
        case .partnership:
            subject = "Partnership idea: \(name)"
            paragraphs.append("I'm \(name). \(hook) I think there's a natural fit between my audience and \(contact?.organization.isBlank == false ? contact!.organization : "your brand"), and I'd love to explore working together.")
        case .followUp:
            subject = "Following up: \(name) — “\(title)”"
            paragraphs.append("Just following up on my note about “\(title)”. I know inboxes are busy — happy to resend anything useful.")
            if !link.isBlank { paragraphs.append(link) }
        case .reminder:
            subject = "Reminder from \(name)"
            paragraphs.append("Quick reminder about our upcoming plans.")
        case .general:
            subject = "Hello from \(name)"
            paragraphs.append("")
        }
        paragraphs.append(signature(profile))
        return (subject, paragraphs.joined(separator: "\n\n"))
    }

    /// A Spotify for Artists pitch filled in from the release and profile, ready to edit.
    static func editorialPitch(for release: Release, profile: ArtistProfile, subscriberCount: Int = 0) -> EditorialPitch {
        var pitch = EditorialPitch()
        let focus = release.tracks.first { !$0.title.isBlank }
        pitch.trackID = focus?.id
        pitch.trackTitle = focus?.title ?? release.title
        pitch.primaryGenre = release.primaryGenre.isBlank ? (profile.genres.first ?? "") : release.primaryGenre
        pitch.subgenres = Array(profile.genres.filter { $0.caseInsensitiveCompare(pitch.primaryGenre) != .orderedSame }.prefix(EditorialPitch.maxSubgenres))
        pitch.hometown = profile.location
        pitch.currentLocation = profile.location
        pitch.description = editorialDescription(release: release, profile: profile, subscriberCount: subscriberCount, track: focus)
        return pitch
    }

    /// The 500-character note to Spotify's editors: what the song is, who it's for, and the plan around it.
    static func editorialDescription(release: Release?, profile: ArtistProfile, subscriberCount: Int, track: Track? = nil) -> String {
        let title = track?.title ?? release?.title ?? "[song title]"
        let genre = release.map { $0.primaryGenre.isBlank ? (profile.genres.first ?? "") : $0.primaryGenre } ?? (profile.genres.first ?? "")
        var sentences: [String] = []
        sentences.append("“\(title)” is a\(genre.isBlank ? "" : " \(genre.lowercased())") song about [what it's about, in a few words].")
        if !profile.soundDescription.isBlank { sentences.append(clip(profile.soundDescription, to: 160)) }
        if !profile.audience.comparableArtists.isBlank { sentences.append("For fans of \(clip(profile.audience.comparableArtists, to: 80)).") }
        var plan = "[Release plan: press, shows, video]"
        if subscriberCount > 0 { plan = "Release plan: email to \(subscriberCount) subscribers, [press, shows, video]" }
        sentences.append(plan + ".")
        var text = sentences.joined(separator: " ")
        if text.count > EditorialPitch.maxDescription { text = clip(text, to: EditorialPitch.maxDescription) }
        return text
    }

    /// Shortens text to at most `limit` characters, at a word boundary where possible.
    static func clip(_ text: String, to limit: Int) -> String {
        let t = text.trimmed
        guard t.count > limit else { return t }
        let cut = String(t.prefix(limit - 1))
        let atWord = cut.range(of: " ", options: .backwards).map { String(cut[..<$0.lowerBound]) } ?? cut
        return atWord.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:.")) + "…"
    }

    /// One personalized draft per contact. Skips anyone who already has this kind of pitch for this release.
    static func batch(kind: OutreachKind, contacts: [Contact], release: Release?, existing: [Outreach],
                      profile: ArtistProfile, pressKit: PressKit, now: Date = Date()) -> (drafts: [Outreach], skipped: [Contact]) {
        var drafts: [Outreach] = []
        var skipped: [Contact] = []
        for contact in contacts {
            let already = existing.contains { $0.contactID == contact.id && $0.kind == kind && $0.releaseID == release?.id }
            if already { skipped.append(contact); continue }
            let draft = pitch(kind: kind, contact: contact, release: release, profile: profile, pressKit: pressKit)
            drafts.append(Outreach(kind: kind, contactID: contact.id, releaseID: release?.id, subject: draft.subject,
                                   body: draft.body, status: .draft, createdAt: now, createdBy: .artist))
        }
        return (drafts, skipped)
    }

    static func followUp(for original: Outreach, contact: Contact?, release: Release?, profile: ArtistProfile, pressKit: PressKit, now: Date = Date()) -> Outreach {
        let draft = pitch(kind: .followUp, contact: contact, release: release, profile: profile, pressKit: pressKit)
        let subject = original.subject.isBlank ? draft.subject : (original.subject.lowercased().hasPrefix("re:") ? original.subject : "Re: \(original.subject)")
        return Outreach(kind: .followUp, contactID: original.contactID, releaseID: original.releaseID, subject: subject,
                        body: draft.body, status: .draft, createdAt: now, createdBy: .automation, parentID: original.id,
                        templateKey: "followup:\(original.id.uuidString)")
    }

    static func eventReminder(for event: CalendarEvent, contact: Contact, profile: ArtistProfile) -> (subject: String, body: String) {
        let when = event.isAllDay
            ? event.start.formatted(date: .complete, time: .omitted)
            : event.start.formatted(date: .complete, time: .shortened)
        let subject = "Reminder: \(event.title) — \(event.start.formatted(date: .abbreviated, time: .omitted))"
        var body = [greeting(for: contact, tone: profile.communication.draftTone),
                    "A quick reminder about \(event.title) on \(when)\(event.location.isBlank ? "" : " at \(event.location)")."]
        if !event.notes.isBlank { body.append(event.notes) }
        body.append("Let me know if anything's changed.")
        body.append(signature(profile))
        return (subject, body.joined(separator: "\n\n"))
    }

    // MARK: Email to subscribers

    /// A release announcement for the artist's own list. A draft only: campaigns need approval before export.
    static func emailAnnouncement(for release: Release?, profile: ArtistProfile, now: Date = Date()) -> (subject: String, preheader: String, body: String) {
        let name = profile.displayName
        guard let release else {
            return ("News from \(name)", "What I've been working on", [
                "Hi friends,",
                "[What's new: a show, a song you're working on, something you want them to hear first.]",
                signature(profile)
            ].joined(separator: "\n\n"))
        }
        let typeLabel = release.type.label.lowercased()
        let link = releaseLink(release)
        var isOut = false
        var when = "soon"
        if let date = release.releaseDate {
            isOut = date.startOfDay <= now.startOfDay
            when = date.formatted(date: .long, time: .omitted)
        }
        let subject = isOut ? "“\(release.title)” is out now" : "My new \(typeLabel) “\(release.title)” — out \(when)"
        let preheader = isOut ? "Listen now, and thank you." : "You're hearing it here first."
        var paragraphs = ["Hi friends,"]
        if isOut {
            paragraphs.append("“\(release.title)” is out today. You're the people who hear everything first, so thank you for being here.")
        } else {
            paragraphs.append("You're hearing it first: my new \(typeLabel) “\(release.title)” comes out \(when).")
        }
        paragraphs.append("[A few lines about what it's about, how it was made, or why it matters to you.]")
        if !link.isBlank { paragraphs.append(isOut ? "Listen: \(link)" : "Pre-save it here: \(link)") }
        paragraphs.append("If you'd like to help, the best thing you can do is listen, save it, and share it with one friend.")
        paragraphs.append(signature(profile))
        return (subject, preheader, paragraphs.joined(separator: "\n\n"))
    }

    // MARK: Press release

    static func pressRelease(for release: Release, profile: ArtistProfile, pressKit: PressKit) -> PressRelease {
        let name = profile.displayName
        let dateText = release.releaseDate?.formatted(date: .long, time: .omitted) ?? "[release date]"
        let genre = release.primaryGenre.isBlank ? (profile.genres.first ?? "") : release.primaryGenre
        let trackList = release.tracks.enumerated().map { index, track in
            "\(index + 1). \(track.title)\(track.version.isBlank ? "" : " (\(track.version))")"
        }
        var body: [String] = []
        body.append("\(profile.location.isBlank ? "[CITY]" : profile.location.uppercased()) — \(name) announces “\(release.title)”, a new \(release.type.label.lowercased())\(genre.isBlank ? "" : " of \(genre.lowercased())"), out \(dateText)\(release.distributor.isBlank ? "" : " via \(release.distributor)").")
        body.append(profile.soundDescription.isBlank ? "[Describe the record: what it sounds like, what it's about, and why now.]" : profile.soundDescription)
        body.append("[Add a quote from \(name) about the record.]")
        if release.tracks.count > 1 { body.append("Tracklist:\n" + trackList.joined(separator: "\n")) }
        let producers = Set(release.tracks.map(\.producers).filter { !$0.isBlank })
        if !producers.isEmpty { body.append("Produced by \(producers.sorted().joined(separator: ", ")).") }
        let link = releaseLink(release)
        if !link.isBlank { body.append("Listen / pre-save: \(link)") }
        body.append("ABOUT \(name.uppercased())\n" + (profile.bioShort.isBlank ? "[Short bio]" : profile.bioShort))
        let contactCard = pressKit.publicityContact.isEmpty ? pressKit.bookingContact : pressKit.publicityContact
        if !contactCard.isEmpty {
            body.append("PRESS CONTACT\n" + [contactCard.name, contactCard.organization, contactCard.email, contactCard.phone]
                .filter { !$0.isBlank }.joined(separator: "\n"))
        }
        body.append("###")
        return PressRelease(headline: "\(name) Announces New \(release.type.label) “\(release.title)”",
                            subheadline: "Out \(dateText)\(genre.isBlank ? "" : " — \(genre)")",
                            dateline: profile.location, publishDate: release.releaseDate.map { $0.adding(days: -21) },
                            body: body.joined(separator: "\n\n"), releaseID: release.id, status: .draft, createdBy: .automation)
    }

    static func pressReleaseText(_ pr: PressRelease) -> String {
        var parts = ["FOR IMMEDIATE RELEASE", pr.headline.uppercased()]
        if !pr.subheadline.isBlank { parts.append(pr.subheadline) }
        parts.append(pr.body)
        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Press kit export

enum PressKitRenderer {
    static func html(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func paragraphs(_ s: String) -> String {
        s.components(separatedBy: "\n\n").filter { !$0.isBlank }
            .map { "<p>\(html($0).replacingOccurrences(of: "\n", with: "<br>"))</p>" }
            .joined(separator: "\n")
    }

    static func safeURL(_ s: String) -> String {
        let t = s.trimmed
        let lower = t.lowercased()
        guard lower.hasPrefix("https://") || lower.hasPrefix("http://") || lower.hasPrefix("mailto:") else { return "#" }
        return html(t)
    }

    /// A single self-contained HTML page. Photos are embedded so the file can be emailed or hosted as is.
    static func htmlDocument(workspace ws: Workspace, photoData: (PressPhoto) -> (data: Data, mime: String)?) -> String {
        let p = ws.profile, kit = ws.pressKit
        let name = html(p.displayName)
        var sections: [String] = []

        let primary = kit.photos.first(where: \.isPrimary) ?? kit.photos.first
        var hero = "<header><h1>\(name)</h1>"
        if !kit.headline.isBlank { hero += "<p class=\"lede\">\(html(kit.headline))</p>" }
        if !p.genres.isEmpty || !p.location.isBlank {
            hero += "<p class=\"meta\">\(html([p.genres.commaJoined, p.location].filter { !$0.isBlank }.joined(separator: " · ")))</p>"
        }
        hero += "</header>"
        sections.append(hero)

        if let primary, let img = photoData(primary) {
            sections.append("<figure class=\"hero\"><img src=\"data:\(img.mime);base64,\(img.data.base64EncodedString())\" alt=\"\(html(primary.caption.isBlank ? "Photo of \(p.displayName)" : primary.caption))\">\(primary.photographerCredit.isBlank ? "" : "<figcaption>Photo: \(html(primary.photographerCredit))</figcaption>")</figure>")
        }
        if !p.bioShort.isBlank || !p.bioLong.isBlank {
            sections.append("<section><h2>Bio</h2>\(paragraphs(p.bioLong.isBlank ? p.bioShort : p.bioLong))</section>")
        }
        let links = p.links.labeled
        if !links.isEmpty || !kit.featuredTracks.isEmpty {
            var s = "<section><h2>Listen</h2><ul class=\"links\">"
            for t in kit.featuredTracks where !t.title.isBlank {
                s += "<li><a href=\"\(safeURL(t.url))\">\(html(t.title))</a></li>"
            }
            for link in links { s += "<li><a href=\"\(safeURL(link.url))\">\(html(link.label))</a></li>" }
            s += "</ul></section>"
            sections.append(s)
        }
        let quotes = ws.coverage.filter { $0.includeInPressKit }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        if !quotes.isEmpty || !kit.achievements.isBlank {
            var s = "<section><h2>Press</h2>"
            for q in quotes {
                if !q.quote.isBlank { s += "<blockquote>“\(html(q.quote))”<cite>— \(html(q.citation))</cite></blockquote>" }
                else { s += "<p><a href=\"\(safeURL(q.url))\">\(html(q.outlet)): \(html(q.title))</a></p>" }
            }
            if !kit.achievements.isBlank { s += "<h3>Highlights</h3>\(paragraphs(kit.achievements))" }
            s += "</section>"
            sections.append(s)
        }
        if !kit.credits.isBlank { sections.append("<section><h2>Credits</h2>\(paragraphs(kit.credits))</section>") }
        let others = kit.photos.filter { $0.id != primary?.id }
        if !others.isEmpty {
            var s = "<section><h2>Photos</h2><div class=\"grid\">"
            for photo in others {
                if let img = photoData(photo) {
                    s += "<figure><img src=\"data:\(img.mime);base64,\(img.data.base64EncodedString())\" alt=\"\(html(photo.caption.isBlank ? "Photo of \(p.displayName)" : photo.caption))\">\(photo.photographerCredit.isBlank ? "" : "<figcaption>Photo: \(html(photo.photographerCredit))</figcaption>")</figure>"
                }
            }
            s += "</div></section>"
            sections.append(s)
        }
        if !kit.technicalRider.isBlank { sections.append("<section><h2>Technical rider</h2>\(paragraphs(kit.technicalRider))</section>") }
        var contacts = ""
        for (label, card) in [("Booking", kit.bookingContact), ("Publicity", kit.publicityContact)] where !card.isEmpty {
            contacts += "<div><h3>\(label)</h3><p>\([card.name, card.organization].filter { !$0.isBlank }.map(html).joined(separator: "<br>"))"
            if !card.email.isBlank { contacts += "<br><a href=\"mailto:\(html(card.email))\">\(html(card.email))</a>" }
            if !card.phone.isBlank { contacts += "<br>\(html(card.phone))" }
            contacts += "</p></div>"
        }
        if !contacts.isEmpty { sections.append("<section><h2>Contact</h2><div class=\"contacts\">\(contacts)</div></section>") }

        let css = """
        :root{color-scheme:light dark;--ink:#1d1d1f;--muted:#6e6e73;--rule:#d2d2d7;--bg:#fff}
        @media (prefers-color-scheme:dark){:root{--ink:#f5f5f7;--muted:#a1a1a6;--rule:#3a3a3c;--bg:#111}}
        body{margin:0;background:var(--bg);color:var(--ink);font:17px/1.6 -apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif}
        main{max-width:760px;margin:0 auto;padding:48px 24px}
        h1{font-size:44px;line-height:1.1;margin:0 0 8px}h2{font-size:22px;margin:40px 0 12px;border-top:1px solid var(--rule);padding-top:24px}
        .lede{font-size:21px;margin:0}.meta{color:var(--muted);margin:4px 0 0}
        figure{margin:24px 0}img{max-width:100%;border-radius:8px;display:block}figcaption{color:var(--muted);font-size:13px;margin-top:6px}
        .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:16px}.grid figure{margin:0}
        blockquote{margin:16px 0;font-size:19px}cite{display:block;color:var(--muted);font-style:normal;font-size:15px}
        .links{padding-left:18px}.contacts{display:flex;gap:48px;flex-wrap:wrap}a{color:inherit}
        footer{color:var(--muted);font-size:13px;margin-top:48px}
        """
        return """
        <!DOCTYPE html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(name) — Press Kit</title><style>\(css)</style></head>
        <body><main>
        \(sections.joined(separator: "\n"))
        <footer>Press kit updated \(html((kit.updatedAt ?? Date()).formatted(date: .long, time: .omitted))).</footer>
        </main></body></html>
        """
    }

    static func markdown(workspace ws: Workspace) -> String {
        let p = ws.profile, kit = ws.pressKit
        var out = ["# \(p.displayName)"]
        if !kit.headline.isBlank { out.append("_\(kit.headline)_") }
        let meta = [p.genres.commaJoined, p.location].filter { !$0.isBlank }.joined(separator: " · ")
        if !meta.isBlank { out.append(meta) }
        if !p.bioLong.isBlank || !p.bioShort.isBlank { out.append("## Bio\n\n" + (p.bioLong.isBlank ? p.bioShort : p.bioLong)) }
        var listen: [String] = kit.featuredTracks.filter { !$0.title.isBlank }.map { "- [\($0.title)](\($0.url))" }
        listen += p.links.labeled.map { "- [\($0.label)](\($0.url))" }
        if !listen.isEmpty { out.append("## Listen\n\n" + listen.joined(separator: "\n")) }
        let quotes = ws.coverage.filter { $0.includeInPressKit }
        if !quotes.isEmpty {
            out.append("## Press\n\n" + quotes.map { q in
                q.quote.isBlank ? "- [\(q.outlet): \(q.title)](\(q.url))" : "> “\(q.quote)” — \(q.citation)"
            }.joined(separator: "\n\n"))
        }
        if !kit.achievements.isBlank { out.append("## Highlights\n\n" + kit.achievements) }
        if !kit.credits.isBlank { out.append("## Credits\n\n" + kit.credits) }
        if !kit.photos.isEmpty {
            out.append("## Photos\n\n" + kit.photos.map { "- \($0.fileName)\($0.photographerCredit.isBlank ? "" : " (photo: \($0.photographerCredit))")" }.joined(separator: "\n"))
        }
        for (label, card) in [("Booking", kit.bookingContact), ("Publicity", kit.publicityContact)] where !card.isEmpty {
            out.append("## \(label)\n\n" + [card.name, card.organization, card.email, card.phone].filter { !$0.isBlank }.joined(separator: "  \n"))
        }
        return out.joined(separator: "\n\n") + "\n"
    }
}
