import Foundation

// MARK: - Reading a coverage page

/// What a web page says about itself: the tags news sites, blogs and podcasts publish for link previews
/// (Open Graph, article tags) and for search engines (Schema.org JSON-LD, including review scores).
struct LinkMetadata: Equatable {
    var url = ""
    var title = ""
    var siteName = ""
    var author = ""
    var published: Date?
    var description = ""
    var rating = ""
    var schemaTypes: [String] = []
}

enum LinkReader {
    static func parse(html: String, url: String) -> LinkMetadata {
        var meta = LinkMetadata()
        meta.url = url
        let head = String(html.prefix(600_000))
        let tags = metaTags(head)
        func tag(_ keys: String...) -> String {
            for key in keys { if let v = tags[key], !v.isBlank { return v } }
            return ""
        }

        let ld = jsonLD(head)
        meta.schemaTypes = ld.types

        meta.title = tag("og:title", "twitter:title")
        if meta.title.isBlank { meta.title = ld.headline }
        if meta.title.isBlank { meta.title = titleElement(head) }
        meta.siteName = tag("og:site_name", "application-name")
        if meta.siteName.isBlank { meta.siteName = ld.publisher }
        if meta.siteName.isBlank { meta.siteName = siteFromTitle(meta.title, url: url) }
        meta.title = trimSiteSuffix(meta.title, siteName: meta.siteName)

        var author = tag("author", "article:author", "byl", "parsely-author", "sailthru.author", "dc.creator")
        if author.lowercased().hasPrefix("http") { author = "" }
        if author.isBlank { author = ld.author }
        if author.lowercased().hasPrefix("by ") { author = String(author.dropFirst(3)) }
        meta.author = author.trimmed

        let dateText = tag("article:published_time", "og:published_time", "datepublished", "date", "pubdate",
                           "publish-date", "parsely-pub-date", "sailthru.date", "dc.date")
        meta.published = DateParsing.parse(dateText) ?? DateParsing.parse(ld.datePublished)
            ?? DateParsing.parse(String(ld.datePublished.prefix(10)))
            ?? DateParsing.parse(String(dateText.prefix(10)))

        meta.description = tag("og:description", "description", "twitter:description")
        if meta.description.isBlank { meta.description = ld.description }
        meta.rating = ld.rating
        return meta
    }

    // MARK: HTML pieces

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are fixed strings in this file, so this can't fail at runtime.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }

    private static let metaPattern = regex("<meta\\s[^>]*>")
    private static let attributePattern = regex("([a-zA-Z_:.-]+)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))")
    private static let titlePattern = regex("<title[^>]*>(.*?)</title>")
    private static let ldPattern = regex("<script[^>]*application/ld\\+json[^>]*>(.*?)</script>")

    private static func matches(_ re: NSRegularExpression, in text: String) -> [NSTextCheckingResult] {
        re.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, in text: String) -> String? {
        guard i < m.numberOfRanges, let r = Range(m.range(at: i), in: text) else { return nil }
        return String(text[r])
    }

    /// `property`/`name`/`itemprop` → `content`, lowercased keys. The first value for a key wins.
    static func metaTags(_ html: String) -> [String: String] {
        var result: [String: String] = [:]
        for m in matches(metaPattern, in: html) {
            guard let tagText = group(m, 0, in: html) else { continue }
            var attrs: [String: String] = [:]
            for a in matches(attributePattern, in: tagText) {
                guard let name = group(a, 1, in: tagText)?.lowercased() else { continue }
                let value = group(a, 3, in: tagText) ?? group(a, 4, in: tagText) ?? group(a, 5, in: tagText) ?? ""
                attrs[name] = value
            }
            guard let content = attrs["content"] else { continue }
            for keyAttr in ["property", "name", "itemprop"] {
                if let key = attrs[keyAttr]?.lowercased(), result[key] == nil {
                    result[key] = decodeEntities(content).trimmed
                }
            }
        }
        return result
    }

    static func titleElement(_ html: String) -> String {
        guard let m = matches(titlePattern, in: html).first, let t = group(m, 1, in: html) else { return "" }
        return decodeEntities(t).replacingOccurrences(of: "\n", with: " ").trimmed
    }

    struct LDInfo {
        var types: [String] = []
        var headline = ""
        var author = ""
        var publisher = ""
        var datePublished = ""
        var description = ""
        var rating = ""
    }

    static func jsonLD(_ html: String) -> LDInfo {
        var info = LDInfo()
        var objects: [[String: Any]] = []
        func collect(_ value: Any) {
            if let dict = value as? [String: Any] {
                objects.append(dict)
                if let graph = dict["@graph"] { collect(graph) }
                if let item = dict["itemReviewed"] as? [String: Any], item["review"] != nil { collect(item["review"]!) }
            } else if let array = value as? [Any] {
                array.forEach(collect)
            }
        }
        for m in matches(ldPattern, in: html) {
            guard let body = group(m, 1, in: html), let data = body.trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            collect(json)
        }
        func types(_ o: [String: Any]) -> [String] {
            if let t = o["@type"] as? String { return [t] }
            return o["@type"] as? [String] ?? []
        }
        func name(_ value: Any?) -> String {
            if let s = value as? String { return s }
            if let d = value as? [String: Any] { return d["name"] as? String ?? "" }
            if let a = value as? [Any] { return a.map { name($0) }.filter { !$0.isBlank }.joined(separator: ", ") }
            return ""
        }
        let articleTypes: Set<String> = ["Review", "CriticReview", "NewsArticle", "Article", "BlogPosting", "ReportageNewsArticle",
                                         "AnalysisNewsArticle", "OpinionNewsArticle", "PodcastEpisode", "VideoObject", "Interview"]
        let ranked = objects.sorted { a, b in
            let aHit = types(a).contains { articleTypes.contains($0) }
            let bHit = types(b).contains { articleTypes.contains($0) }
            return aHit && !bHit
        }
        for o in ranked {
            info.types.append(contentsOf: types(o))
            if info.headline.isBlank { info.headline = decodeEntities((o["headline"] as? String) ?? (o["name"] as? String ?? "")) }
            if info.author.isBlank { info.author = decodeEntities(name(o["author"] ?? o["creator"])) }
            if info.publisher.isBlank { info.publisher = decodeEntities(name(o["publisher"])) }
            if info.datePublished.isBlank { info.datePublished = (o["datePublished"] as? String) ?? (o["uploadDate"] as? String ?? "") }
            if info.description.isBlank { info.description = decodeEntities(o["description"] as? String ?? "") }
            if info.rating.isBlank, let r = o["reviewRating"] as? [String: Any] {
                let value = r["ratingValue"].map { "\($0)" } ?? ""
                let best = r["bestRating"].map { "\($0)" } ?? ""
                if !value.isBlank { info.rating = best.isBlank ? value : "\(value)/\(best)" }
            }
        }
        info.types = Array(NSOrderedSet(array: info.types)) as? [String] ?? info.types
        return info
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
                                       "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "mdash": "—", "ndash": "–",
                                       "hellip": "…", "eacute": "é", "egrave": "è", "aacute": "á", "oacute": "ó", "uacute": "ú",
                                       "iacute": "í", "ntilde": "ñ", "uuml": "ü", "ouml": "ö", "auml": "ä", "ccedil": "ç"]
        var out = ""
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "&", let semi = text[i...].prefix(12).firstIndex(of: ";") {
                let entity = String(text[text.index(after: i)..<semi])
                var replacement: String?
                if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                    replacement = UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else if entity.hasPrefix("#") {
                    replacement = UInt32(entity.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else {
                    replacement = named[entity.lowercased()]
                }
                if let replacement {
                    out += replacement
                    i = text.index(after: semi)
                    continue
                }
            }
            out.append(text[i])
            i = text.index(after: i)
        }
        return out
    }

    private static let titleSeparators = [" | ", " - ", " – ", " — ", " :: ", " · "]

    private static func squashed(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func lastTitlePart(_ title: String) -> (head: String, tail: String)? {
        let t = title.trimmed
        let ranges = titleSeparators.compactMap { t.range(of: $0, options: .backwards) }
        guard let range = ranges.max(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        return (String(t[..<range.lowerBound]).trimmed, String(t[range.upperBound...]).trimmed)
    }

    /// "Northern Lights review | The Lantern" → "Northern Lights review" when the site is The Lantern.
    static func trimSiteSuffix(_ title: String, siteName: String) -> String {
        let t = title.trimmed
        guard !siteName.isBlank, let parts = lastTitlePart(t), !parts.head.isBlank else { return t }
        let tail = squashed(parts.tail)
        let site = squashed(siteName)
        if tail == site || (tail.count > 2 && site.contains(tail)) || (site.count > 2 && tail.contains(site)) {
            return parts.head
        }
        return t
    }

    /// The outlet's name as its page titles spell it ("Night Shift Radio"), falling back to the web address.
    static func siteFromTitle(_ title: String, url: String) -> String {
        let fromHost = outletName(fromURL: url)
        if let parts = lastTitlePart(title), !parts.tail.isBlank {
            let tail = squashed(parts.tail)
            let host = squashed(URL(string: url.trimmed)?.host ?? "")
            if !tail.isEmpty, tail == squashed(fromHost) || host.contains(tail) { return parts.tail }
        }
        return fromHost
    }

    /// Page bytes as text, honouring the charset the server or the page declares.
    static func decodeText(_ data: Data, contentType: String? = nil) -> String {
        func charset(in text: String) -> String? {
            guard let range = text.range(of: "charset=[\"']?([A-Za-z0-9_-]+)", options: [.regularExpression, .caseInsensitive]) else { return nil }
            return String(text[range]).dropFirst("charset=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")).lowercased()
        }
        let declared = contentType.flatMap(charset(in:))
            ?? charset(in: String(decoding: data.prefix(4096), as: UTF8.self))
        let encodings: [String: String.Encoding] = ["utf-8": .utf8, "utf8": .utf8, "iso-8859-1": .isoLatin1, "latin1": .isoLatin1,
                                                    "windows-1252": .windowsCP1252, "us-ascii": .ascii, "utf-16": .utf16]
        if let name = declared, let encoding = encodings[name], let text = String(data: data, encoding: encoding) { return text }
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }

    /// "https://www.stereogum.com/2026/…" → "Stereogum".
    static func outletName(fromURL raw: String) -> String {
        guard let host = URL(string: raw.trimmed)?.host?.lowercased() else { return "" }
        var parts = host.split(separator: ".").map(String.init)
        for prefix in ["www", "m", "amp", "blog", "music"] where parts.count > 2 && parts.first == prefix { parts.removeFirst() }
        guard parts.count >= 2 else { return host }
        let secondLevel = ["co", "com", "org", "net", "ac"]
        let name = parts.count >= 3 && secondLevel.contains(parts[parts.count - 2]) ? parts[parts.count - 3] : parts[parts.count - 2]
        let known: [String: String] = ["nytimes": "The New York Times", "theguardian": "The Guardian", "npr": "NPR",
                                       "rollingstone": "Rolling Stone", "pitchfork": "Pitchfork", "stereogum": "Stereogum",
                                       "pastemagazine": "Paste", "consequence": "Consequence", "billboard": "Billboard",
                                       "nme": "NME", "kexp": "KEXP", "bandcamp": "Bandcamp", "youtube": "YouTube",
                                       "spotify": "Spotify", "apple": "Apple", "ajc": "The Atlanta Journal-Constitution"]
        return known[name] ?? name.prefix(1).uppercased() + name.dropFirst()
    }
}

// MARK: - Turning links into coverage

enum CoverageLinks {
    private static let urlPattern = try! NSRegularExpression(pattern: "https?://[^\\s<>\"')\\]]+", options: [.caseInsensitive])

    /// Every web link in pasted text, in order, without duplicates.
    static func extractURLs(from text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for m in urlPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range, in: text) else { continue }
            let url = String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
            let key = normalize(url)
            if !key.isEmpty, seen.insert(key).inserted { result.append(url) }
        }
        return result
    }

    /// Compares links the way a person would: ignores http/https, "www.", a trailing slash,
    /// tracking parameters and #fragments.
    static func normalize(_ raw: String) -> String {
        guard var components = URLComponents(string: raw.trimmed), let host = components.host?.lowercased() else {
            return raw.trimmed.lowercased()
        }
        let tracking: Set<String> = ["fbclid", "gclid", "igshid", "mc_cid", "mc_eid", "ref", "ref_src", "si", "share"]
        components.queryItems = components.queryItems?.filter { item in
            !item.name.lowercased().hasPrefix("utm_") && !tracking.contains(item.name.lowercased())
        }
        if components.queryItems?.isEmpty == true { components.queryItems = nil }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let query = components.query.map { "?" + $0 } ?? ""
        return bareHost + path + query
    }

    static func existingKeys(_ coverage: [Coverage]) -> Set<String> {
        Set(coverage.compactMap { $0.url.isBlank ? nil : normalize($0.url) })
    }

    /// A best guess at what kind of coverage a page is. The artist can always change it.
    static func guessKind(url: String, title: String, description: String = "", schemaTypes: [String] = []) -> CoverageKind {
        let u = url.lowercased()
        let text = (title + " " + description).lowercased()
        let types = Set(schemaTypes.map { $0.lowercased() })
        if u.contains("open.spotify.com/playlist") || u.contains("music.apple.com") && u.contains("/playlist/") { return .playlistAdd }
        if u.contains("podcasts.apple.com") || u.contains("open.spotify.com/episode") || u.contains("open.spotify.com/show")
            || types.contains("podcastepisode") || text.contains("podcast") { return .podcast }
        if u.contains("youtube.com") || u.contains("youtu.be") || u.contains("vimeo.com") || u.contains("tiktok.com")
            || types.contains("videoobject") { return .video }
        if types.contains("review") || types.contains("criticreview") || u.contains("/review") || text.contains(" review") || text.hasPrefix("review") {
            return .review
        }
        if text.contains("interview") || text.contains("q&a") || u.contains("interview") || types.contains("interview") { return .interview }
        if text.contains("premiere") || u.contains("premiere") { return .premiere }
        if u.contains("radio") || text.contains("radio session") || text.contains("live session") { return .radioPlay }
        return .article
    }

    /// A coverage record filled in from what the page says about itself.
    static func coverage(from meta: LinkMetadata, kindOverride: CoverageKind? = nil, now: Date = Date()) -> Coverage {
        var c = Coverage()
        c.url = meta.url
        c.outlet = meta.siteName
        c.title = meta.title
        c.author = meta.author
        c.date = meta.published
        c.excerpt = Drafting.clip(meta.description, to: 600)
        c.rating = meta.rating
        c.kind = kindOverride ?? guessKind(url: meta.url, title: meta.title, description: meta.description, schemaTypes: meta.schemaTypes)
        c.includeInPressKit = c.kind != .mention && c.kind != .playlistAdd
        c.verified = true
        c.linkCheckedAt = now
        c.addedAt = now
        return c
    }
}

// MARK: - Connecting coverage to the rest of the workspace

extension CoverageLinks {
    /// Fills in the release and the writer when the piece makes them obvious. Leaves anything already set alone.
    static func suggestLinks(for c: inout Coverage, releases: [Release], contacts: [Contact], outreach: [Outreach] = []) {
        let text = " \(c.title) \(c.excerpt) \(c.quote) ".lowercased()
        if c.releaseID == nil {
            let named = releases.filter { r in
                let t = r.title.trimmed.lowercased()
                return t.count >= 3 && text.contains(t)
            }
            c.releaseID = named.max { ($0.title.count, $0.releaseDate ?? .distantPast) < ($1.title.count, $1.releaseDate ?? .distantPast) }?.id
        }
        if c.contactID == nil {
            let author = c.author.trimmed.lowercased()
            let outlet = c.outlet.trimmed.lowercased()
            let pitched = Set(outreach.filter { $0.status == .sent || $0.status == .replied }.compactMap(\.contactID))
            let byName = contacts.filter { !author.isEmpty && $0.name.trimmed.lowercased() == author }
            let byOutlet = contacts.filter { !outlet.isEmpty && $0.organization.trimmed.lowercased() == outlet }
            let candidates = byName.isEmpty ? byOutlet : byName
            c.contactID = (candidates.first { pitched.contains($0.id) } ?? (candidates.count == 1 ? candidates.first : nil))?.id
        }
    }
}

extension CoverageKind {
    /// What a pitch of this kind usually turns into.
    init(resultOf pitch: OutreachKind) {
        switch pitch {
        case .review: self = .review
        case .press: self = .feature
        case .playlist, .spotifyEditorial: self = .playlistAdd
        case .radio: self = .radioPlay
        default: self = .mention
        }
    }
}

extension CoverageLinks {
    /// A coverage record started from the pitch that led to it.
    static func coverage(resultOf pitch: Outreach, contact: Contact?, now: Date = Date()) -> Coverage {
        var c = Coverage(kind: CoverageKind(resultOf: pitch.kind), releaseID: pitch.releaseID, contactID: pitch.contactID)
        if let contact {
            c.outlet = contact.organization.isBlank ? contact.displayName : contact.organization
            if !contact.organization.isBlank { c.author = contact.name }
        }
        if pitch.kind == .spotifyEditorial { c.outlet = "Spotify editorial playlist" }
        c.includeInPressKit = c.kind != .mention && c.kind != .playlistAdd
        c.addedAt = now
        return c
    }
}

extension Workspace {
    /// Coverage that came from a pitch closes the loop on that pitch: it's marked as resulting in coverage
    /// and its follow-up reminder is cleared.
    mutating func markPitchCovered(by c: Coverage) {
        guard let contactID = c.contactID else { return }
        let open: Set<OutreachStatus> = [.sent, .replied, .noResponse]
        let matches = outreach.indices.filter { i in
            outreach[i].contactID == contactID && open.contains(outreach[i].status)
                && (c.releaseID == nil || outreach[i].releaseID == nil || outreach[i].releaseID == c.releaseID)
        }
        guard let i = matches.max(by: { (outreach[$0].sentAt ?? .distantPast) < (outreach[$1].sentAt ?? .distantPast) }) else { return }
        outreach[i].status = .covered
        outreach[i].followUpDue = nil
    }
}

// MARK: - Saved copies

enum CoverageArchive {
    /// A copy of a page to keep in case the link later breaks: scripts and auto-refresh removed, relative
    /// links pointed at the original site, and a note at the top saying where and when it was saved.
    static func snapshot(html: String, url: String, savedAt: Date) -> String {
        func strip(_ pattern: String, in text: String) -> String {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return text }
            return re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        var page = html
        page = strip("<script\\b[^>]*>.*?</script\\s*>", in: page)
        page = strip("<script\\b[^>]*/>", in: page)
        page = strip("<meta[^>]+http-equiv\\s*=\\s*[\"']?refresh[^>]*>", in: page)
        page = strip("<base\\b[^>]*>", in: page)
        page = strip("\\son[a-z]+\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)", in: page)
        page = page.replacingOccurrences(of: "javascript:", with: "", options: .caseInsensitive)

        let safe = PressKitRenderer.html(url)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d, yyyy 'at' h:mm a"
        let base = "<base href=\"\(safe)\"><meta charset=\"utf-8\">"
        let note = "<div style=\"font: 13px -apple-system, sans-serif; background: #fff8d6; color: #333; padding: 10px 14px; border-bottom: 1px solid #e0d48a;\">Copy saved by Manager on \(formatter.string(from: savedAt)) from <a href=\"\(safe)\">\(safe)</a>. The page may have changed since; images load from the original site when it’s still up.</div>"

        if let head = page.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            page.insert(contentsOf: base, at: head.upperBound)
        } else {
            page = "<head>\(base)</head>" + page
        }
        if let body = page.range(of: "<body[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            page.insert(contentsOf: note, at: body.upperBound)
        } else if let headEnd = page.range(of: "</head>", options: .caseInsensitive) {
            page.insert(contentsOf: note, at: headEnd.upperBound)
        } else {
            page = note + page
        }
        return page
    }
}

// MARK: - Coverage as CSV

struct CoverageImportPreview {
    var totalRows = 0
    var added: [Coverage] = []
    var duplicates: [String] = []
    var skipped: [String] = []
    var hasChanges: Bool { !added.isEmpty }
}

enum CoverageCSV {
    static let headers = ["date", "outlet", "title", "type", "url", "author", "rating", "quote", "excerpt", "notes",
                          "release", "in_press_kit", "verified"]

    static func export(_ coverage: [Coverage], releases: [Release]) -> String {
        let releaseNames = Dictionary(uniqueKeysWithValues: releases.map { ($0.id, $0.title) })
        let rows = coverage.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.map { c -> [String] in
            [c.date.map { DateParsing.iso($0) } ?? "", c.outlet, c.title, c.kind.label, c.url, c.author, c.rating, c.quote,
             c.excerpt, c.notes, c.releaseID.flatMap { releaseNames[$0] } ?? "", c.includeInPressKit ? "yes" : "no",
             c.verified ? "yes" : "no"]
        }
        return CSV.write(headers: headers, rows: rows)
    }

    static func kind(from raw: String) -> CoverageKind? {
        let v = raw.trimmed.lowercased()
        guard !v.isEmpty else { return nil }
        if let exact = CoverageKind.allCases.first(where: { $0.rawValue.lowercased() == v || $0.label.lowercased() == v }) { return exact }
        let synonyms: [(String, CoverageKind)] = [("review", .review), ("interview", .interview), ("q&a", .interview),
                                                  ("premiere", .premiere), ("podcast", .podcast), ("radio", .radioPlay),
                                                  ("video", .video), ("tv", .video), ("playlist", .playlistAdd),
                                                  ("mention", .mention), ("feature", .feature), ("profile", .feature),
                                                  ("news", .article), ("article", .article), ("blog", .article)]
        return synonyms.first { v.contains($0.0) }?.1
    }

    static func preview(csv text: String, existing: [Coverage], releases: [Release], now: Date = Date()) -> CoverageImportPreview {
        let table = CSV.parseTable(text)
        var preview = CoverageImportPreview()
        preview.totalRows = table.rows.count
        var urls = CoverageLinks.existingKeys(existing)
        var titles = Set(existing.map { "\($0.outlet.lowercased())|\($0.title.lowercased())" })
        let releaseByName = Dictionary(releases.map { ($0.title.lowercased(), $0.id) }, uniquingKeysWith: { a, _ in a })
        for (index, row) in table.rows.enumerated() {
            let label = "Row \(index + 2)"
            var c = Coverage()
            c.url = CSV.value(row, ["url", "link", "address"])
            c.outlet = CSV.value(row, ["outlet", "publication", "source", "site", "station", "show", "playlist"])
            c.title = CSV.value(row, ["title", "headline", "name"])
            if c.outlet.isBlank && !c.url.isBlank { c.outlet = LinkReader.outletName(fromURL: c.url) }
            guard !(c.outlet.isBlank && c.title.isBlank && c.url.isBlank) else {
                preview.skipped.append("\(label): no outlet, title or link")
                continue
            }
            c.date = DateParsing.parse(CSV.value(row, ["date", "published", "published_at", "air_date"]))
            c.kind = kind(from: CSV.value(row, ["type", "kind", "category"]))
                ?? CoverageLinks.guessKind(url: c.url, title: c.title)
            c.author = CSV.value(row, ["author", "writer", "journalist", "host", "by"])
            c.rating = CSV.value(row, ["rating", "score"])
            c.quote = CSV.value(row, ["quote", "pull_quote", "pullquote"])
            c.excerpt = CSV.value(row, ["excerpt", "summary", "description"])
            c.notes = CSV.value(row, ["notes", "note", "comments"])
            c.releaseID = releaseByName[CSV.value(row, ["release", "album", "single"]).lowercased()]
            let inKit = CSV.value(row, ["in_press_kit", "press_kit"]).lowercased()
            c.includeInPressKit = inKit.isEmpty ? (c.kind != .mention && c.kind != .playlistAdd) : ["yes", "true", "1", "y"].contains(inKit)
            c.verified = ["yes", "true", "1", "y"].contains(CSV.value(row, ["verified"]).lowercased())
            c.addedAt = now

            let urlKey = c.url.isBlank ? nil : CoverageLinks.normalize(c.url)
            let titleKey = "\(c.outlet.lowercased())|\(c.title.lowercased())"
            if let urlKey, urls.contains(urlKey) {
                preview.duplicates.append("\(label): \(c.headline) is already saved")
                continue
            }
            if urlKey == nil, !c.title.isBlank, titles.contains(titleKey) {
                preview.duplicates.append("\(label): \(c.headline) is already saved")
                continue
            }
            if let urlKey { urls.insert(urlKey) }
            titles.insert(titleKey)
            preview.added.append(c)
        }
        return preview
    }
}
