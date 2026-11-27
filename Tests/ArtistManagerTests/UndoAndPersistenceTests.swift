import XCTest
@testable import ArtistManager

final class UndoAndPersistenceTests: XCTestCase {
    func testDiffCapturesAddsChangesAndRemovals() {
        var before = Workspace.onboarded()
        let keep = TaskItem(title: "Keep")
        let drop = TaskItem(title: "Drop")
        before.tasks = [keep, drop]
        var after = before
        after.tasks[0].title = "Keep (edited)"
        after.tasks.remove(at: 1)
        after.tasks.append(TaskItem(title: "New"))
        after.profile.artistName = "Renamed"

        let changes = Workspace.diff(before, after)
        XCTAssertEqual(changes.filter { $0.kind == .tasks }.map(\.changeDescription).sorted(), ["Added", "Changed", "Removed"])
        XCTAssertTrue(changes.contains { $0.kind == .profile })
    }

    func testRevertRestoresEveryRecord() throws {
        let before = Workspace.onboarded()
        var after = before
        after.tasks.append(TaskItem(title: "Added"))
        after.contacts.append(makeContact("Ana"))
        after.pressKit.headline = "New headline"
        let changes = Workspace.diff(before, after)
        try after.revert(changes)
        XCTAssertEqual(after.tasks, before.tasks)
        XCTAssertEqual(after.contacts, before.contacts)
        XCTAssertEqual(after.pressKit, before.pressKit)
    }

    func testConflictDetectedWhenRecordEditedAfterAction() {
        let before = Workspace.onboarded()
        var after = before
        let task = TaskItem(title: "Draft pitch")
        after.tasks.append(task)
        let changes = Workspace.diff(before, after)
        XCTAssertTrue(after.conflicts(forUndoing: changes).isEmpty)
        after.tasks[0].title = "Edited later"
        XCTAssertEqual(after.conflicts(forUndoing: changes).count, 1)
    }

    func testOlderFilesWithMissingFieldsStillLoad() throws {
        // A file from an older version: no collections, and nested records missing fields added later.
        let json = """
        {"schemaVersion":1,
         "profile":{"artistName":"Old File","onboardingCompleted":true,"links":{"website":"https://example.com"}},
         "tasks":[{"id":"6F1D0D4A-6E0B-4C4D-9E43-1B0B7B5D2C11","title":"Old task"}],
         "releases":[{"id":"7A1D0D4A-6E0B-4C4D-9E43-1B0B7B5D2C11","title":"Old release","tracks":[{"title":"Song","writers":[{"name":"Me","share":100}]}]}],
         "subscribers":[{"id":"8B1D0D4A-6E0B-4C4D-9E43-1B0B7B5D2C11","email":"fan@example.com","status":"unsubscribed","consent":{"method":"webForm"}}],
         "campaigns":[{"id":"9C1D0D4A-6E0B-4C4D-9E43-1B0B7B5D2C11","subject":"Hi","results":{"delivered":5}}]}
        """
        let ws = try TolerantDecoding.decodeWorkspace(Data(json.utf8))
        XCTAssertEqual(ws.profile.artistName, "Old File")
        XCTAssertEqual(ws.profile.links.website, "https://example.com")
        XCTAssertEqual(ws.profile.country, "US", "Missing fields take their defaults")
        XCTAssertEqual(ws.profile.availability.workDays, [2, 3, 4, 5, 6])
        XCTAssertEqual(ws.tasks.first?.title, "Old task")
        XCTAssertEqual(ws.tasks.first?.status, .todo)
        XCTAssertNil(ws.tasks.first?.due, "Missing optionals stay empty")
        XCTAssertEqual(ws.releases.first?.tracks.first?.writers.first?.share, 100)
        XCTAssertEqual(ws.subscribers.first?.status, .unsubscribed, "Status is preserved")
        XCTAssertEqual(ws.subscribers.first?.consent?.method, .webForm)
        XCTAssertNil(ws.subscribers.first?.consent?.capturedAt)
        XCTAssertEqual(ws.campaigns.first?.results?.delivered, 5)
        XCTAssertNil(ws.campaigns.first?.sentAt)
        XCTAssertTrue(ws.contacts.isEmpty, "Missing lists start empty, with no sample records")
        XCTAssertTrue(ws.actionLog.isEmpty)
    }

    func testCurrentFilesRoundTripUnchanged() throws {
        var ws = Workspace.onboarded()
        ws.subscribers = [Subscriber(email: "a@example.com", consent: ConsentRecord(method: .doubleOptIn, capturedAt: TestDates.now))]
        ws.tasks = [TaskItem(title: "T", due: TestDates.now)]
        let data = try JSONCoding.encoder.encode(ws)
        // Saved dates are whole seconds, so compare with a plain decode of the same file.
        XCTAssertEqual(try TolerantDecoding.decodeWorkspace(data), try JSONCoding.decode(Workspace.self, from: data))
    }

    func testUndoWorksForRecordsSavedBeforeAFieldExisted() throws {
        var ws = Workspace.onboarded()
        let id = UUID()
        let oldTaskJSON = Data(#"{"id":"\#(id.uuidString)","title":"From an old version"}"#.utf8)
        try ws.setRecord(kind: .tasks, id: id, data: oldTaskJSON)
        XCTAssertEqual(ws.tasks.first?.title, "From an old version")
    }

    func testPersistenceRoundTripAndRecoveryFromBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("am-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let persistence = Persistence(rootURL: dir)
        guard case .fresh = persistence.load() else { return XCTFail("Expected a fresh workspace") }

        var ws = Workspace.onboarded()
        ws.tasks = [TaskItem(title: "Saved")]
        try persistence.save(ws)
        guard case .loaded(let loaded) = persistence.load() else { return XCTFail("Expected to load") }
        XCTAssertEqual(loaded.tasks.first?.title, "Saved")

        persistence.makeDailyBackupIfNeeded(now: TestDates.now)
        XCTAssertEqual(persistence.backupFiles().count, 1)

        // Corrupt the main file: the app sets it aside and loads the newest backup.
        try Data("not json".utf8).write(to: persistence.workspaceURL)
        guard case .recovered(let recovered, let movedTo, _) = persistence.load() else { return XCTFail("Expected recovery") }
        XCTAssertEqual(recovered.tasks.first?.title, "Saved")
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedTo.path), "The unreadable file is kept, not deleted")
    }

    func testDataMovesFromTheOldFolderName() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("am-rename-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let legacy = base.appendingPathComponent(Persistence.legacyFolderName)
        let current = base.appendingPathComponent(Persistence.folderName)
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent("Media"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: legacy.appendingPathComponent("workspace.json"))
        try Data("photo".utf8).write(to: legacy.appendingPathComponent("Media/a.jpg"))
        // The new folder may already exist (empty) from an earlier launch.
        try FileManager.default.createDirectory(at: current.appendingPathComponent("Media"), withIntermediateDirectories: true)

        Persistence.migrate(from: legacy, to: current)
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.appendingPathComponent("workspace.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.appendingPathComponent("Media/a.jpg").path))

        // Never overwrites data already in the new folder.
        try Data("{\"new\":1}".utf8).write(to: current.appendingPathComponent("workspace.json"))
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: legacy.appendingPathComponent("workspace.json"))
        Persistence.migrate(from: legacy, to: current)
        XCTAssertEqual(try String(contentsOf: current.appendingPathComponent("workspace.json"), encoding: .utf8), "{\"new\":1}")
    }

    func testBackupsArePruned() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("am-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let persistence = Persistence(rootURL: dir)
        try persistence.save(Workspace())
        for offset in 0..<(Persistence.maxBackups + 5) {
            persistence.makeDailyBackupIfNeeded(now: TestDates.now.adding(days: offset))
        }
        XCTAssertEqual(persistence.backupFiles().count, Persistence.maxBackups)
    }
}
