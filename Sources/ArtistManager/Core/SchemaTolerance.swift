import Foundation

/// Lets data saved by an older version load in a newer one.
///
/// Swift's synthesized decoding fails when a key is missing, even when the property has a default.
/// So when an update adds a field to a record (say, the profile), files saved before it would no longer
/// open. Before decoding, missing keys are filled in from a template built from the app's own defaults.
///
/// Two templates are used. The *defaults* template holds what a missing value should become (optional
/// values are absent, so they stay nil). The *shape* template has one sample element in every list and a
/// sample in every optional record, so nested records inside lists and optionals are filled in as well.
enum TolerantDecoding {
    static func decodeWorkspace(_ data: Data) throws -> Workspace {
        try JSONCoding.decode(Workspace.self, from: fillWorkspace(data))
    }

    /// Fills missing keys in a whole-workspace JSON document.
    static func fillWorkspace(_ data: Data) throws -> Data {
        let stored = try JSONSerialization.jsonObject(with: data)
        guard stored is [String: Any] else { return data }
        let filled = fill(stored, defaults: Templates.defaults, shape: Templates.shape)
        return try JSONSerialization.data(withJSONObject: filled)
    }

    /// Fills missing keys in one record saved in the activity log (for undo).
    static func fillRecord(kind: EntityKind, data: Data) -> Data {
        guard let stored = try? JSONSerialization.jsonObject(with: data), stored is [String: Any] else { return data }
        let key = kind.rawValue
        let defaults: Any?
        let shape: Any?
        if kind.isSingleton {
            defaults = Templates.defaults[key]
            shape = Templates.shape[key]
        } else {
            defaults = (Templates.defaults[key] as? [Any])?.first
            shape = (Templates.shape[key] as? [Any])?.first
        }
        let filled = fill(stored, defaults: defaults, shape: shape)
        return (try? JSONSerialization.data(withJSONObject: filled)) ?? data
    }

    static func fill(_ stored: Any, defaults: Any?, shape: Any?) -> Any {
        if let object = stored as? [String: Any] {
            let d = defaults as? [String: Any] ?? [:]
            let s = shape as? [String: Any] ?? [:]
            var result = object
            for key in Set(d.keys).union(s.keys) {
                if let value = object[key] {
                    // An optional record that's present: fill it from its sample when it has no default.
                    result[key] = fill(value, defaults: d[key] ?? s[key], shape: s[key])
                } else if let missing = d[key] {
                    // A list of records that's missing entirely starts empty; anything else takes its default.
                    if let list = missing as? [Any], list.first is [String: Any] {
                        result[key] = [Any]()
                    } else {
                        result[key] = missing
                    }
                }
            }
            return result
        }
        if let list = stored as? [Any] {
            let elementDefaults = (defaults as? [Any])?.first
            let elementShape = (shape as? [Any])?.first
            guard elementDefaults is [String: Any] || elementShape is [String: Any] else { return list }
            return list.map { fill($0, defaults: elementDefaults ?? elementShape, shape: elementShape ?? elementDefaults) }
        }
        return stored
    }

    // MARK: Templates

    private enum Templates {
        static let defaults: [String: Any] = json(sampleWorkspace(withOptionals: false))
        static let shape: [String: Any] = json(sampleWorkspace(withOptionals: true))

        private static func json(_ ws: Workspace) -> [String: Any] {
            guard let data = try? JSONCoding.encoder.encode(ws),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return object
        }

        /// One default element in every list, all the way down. With `withOptionals`, optional records are
        /// filled with their defaults too, so their own fields can be completed.
        private static func sampleWorkspace(withOptionals: Bool) -> Workspace {
            var ws = Workspace()
            ws.profile.rightsMemberships = [RightsMembership()]
            ws.profile.availability.blackoutDates = [DateRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 0))]
            ws.pressKit.photos = [PressPhoto()]
            ws.pressKit.featuredTracks = [FeaturedTrack()]
            ws.goals = [CareerGoal()]
            ws.recommendations = [sampleRecommendation()]
            var track = Track()
            track.writers = [Split()]
            var release = Release()
            release.tracks = [track]
            release.assets = [AssetItem()]
            ws.releases = [release]
            ws.tasks = [TaskItem()]
            ws.events = [CalendarEvent()]
            var contact = Contact()
            contact.interactions = [Interaction()]
            ws.contacts = [contact]
            var outreach = Outreach()
            if withOptionals { outreach.editorial = EditorialPitch() }
            ws.outreach = [outreach]
            ws.pressReleases = [PressRelease()]
            var coverage = Coverage()
            coverage.attachments = [CoverageAttachment()]
            ws.coverage = [coverage]
            ws.targets = [Target()]
            var subscriber = Subscriber()
            var segment = Segment()
            var campaign = EmailCampaign()
            var approval = ApprovalRequest(kind: .editRecord, title: "", summary: "", preview: "")
            var record = ActionRecord(title: "", kind: .editRecord, actor: .system, status: .completed)
            record.changes = [EntityChange(kind: .tasks, id: UUID(), before: nil, after: nil)]
            if withOptionals {
                subscriber.consent = ConsentRecord()
                segment.rules = SegmentRules()
                campaign.results = CampaignResults()
                approval.proposal = Proposal(tasks: [TaskItem()], events: [CalendarEvent()], outreach: [outreach],
                                             recommendations: [sampleRecommendation()])
            }
            ws.subscribers = [subscriber]
            ws.segments = [segment]
            ws.campaigns = [campaign]
            ws.budgetLines = [BudgetLine()]
            ws.approvals = [approval]
            ws.actionLog = [record]
            return ws
        }

        private static func sampleRecommendation() -> Recommendation {
            Recommendation(ruleKey: "", title: "", detail: "", rationale: "", area: .strategy)
        }
    }
}
