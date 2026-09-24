import XCTest
@testable import PadShelf

final class EditingTests: XCTestCase {
    @MainActor func withLibrary(_ run: (Library, [UUID]) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = Library(storage: root)
        library.session.samples = (1...3).map { Sample(id: UUID(), name: "Sound\($0)", file: "\($0).wav", category: "Unsorted", duration: 1, rate: 44100, channels: 2) }
        try run(library, library.session.samples.map(\.id))
    }
    @MainActor func testBulkCategoryIsOneUndoableManualEdit() throws {
        try withLibrary { library, ids in
            library.recategorize(Array(ids.prefix(2)), as: "Breaks")
            XCTAssertEqual(library.undoHistory.count, 1)
            XCTAssertEqual(library.sample(ids[0])?.categoryIsManual, true)
            XCTAssertEqual(library.sample(ids[1])?.category, "Breaks")
            XCTAssertEqual(library.sample(ids[2])?.category, "Unsorted")
            library.undoEdit()
            XCTAssertEqual(library.sample(ids[0])?.category, "Unsorted")
            XCTAssertNil(library.sample(ids[0])?.categoryIsManual)
            library.redoEdit()
            XCTAssertEqual(library.sample(ids[1])?.category, "Breaks")
            XCTAssertEqual(Library(storage: library.root).sample(ids[1])?.category, "Breaks")
        }
    }
    @MainActor func testGroupHistoryModesAndRedoBranch() throws {
        try withLibrary { library, ids in
            library.assignGroup(ids, startingAt: "A-10")
            XCTAssertEqual(library.undoHistory.count, 1)
            library.setBankMode("Mono", bank: "A")
            library.undoEdit(); XCTAssertEqual(library.mode("A-10"), "Stereo")
            library.undoEdit(); XCTAssertTrue(library.session.pads.isEmpty)
            library.redoEdit(); XCTAssertEqual(library.session.pads.count, 3)
            library.clear(10); XCTAssertFalse(library.canRedo)
            library.undoEdit(); XCTAssertEqual(library.session.pads["A-10"], ids[0])
            let before = library.session
            library.busy = true; library.undoEdit(); library.redoEdit()
            library.recategorize(ids, as: "Kick"); library.newKit()
            XCTAssertEqual(library.session, before)
        }
    }
    @MainActor func testKitsPersistLoadRestoreRemovedSamplesAndUndoSwitch() throws {
        try withLibrary { library, ids in
            library.assign(ids[0], to: "A-1"); library.setMode("Mono", key: "A-1")
            library.assign(ids[1], to: "J-12")
            library.saveKit(named: "First")
            let first = try XCTUnwrap(library.activeKit?.id)
            library.newKit(); library.assign(ids[2], to: "B-2")
            library.saveKit(named: "Second")
            let second = try XCTUnwrap(library.activeKit?.id)
            library.remove(ids[0])
            let loaded = Library(storage: library.root)
            XCTAssertEqual(loaded.savedKits.count, 2)
            loaded.loadKit(first)
            XCTAssertNotNil(loaded.sample(ids[0]))
            XCTAssertEqual(loaded.session.pads["A-1"], ids[0])
            XCTAssertEqual(loaded.mode("A-1"), "Mono")
            XCTAssertEqual(loaded.session.pads["J-12"], ids[1])
            XCTAssertFalse(loaded.kitChanged)
            loaded.undoEdit()
            XCTAssertEqual(loaded.session.activeKitID, second)
            XCTAssertEqual(loaded.session.pads, ["B-2": ids[2]])
            loaded.redoEdit(); XCTAssertEqual(loaded.session.activeKitID, first)
            loaded.setMode("Stereo", key: "A-1"); XCTAssertTrue(loaded.kitChanged)
            loaded.updateKit(); XCTAssertFalse(loaded.kitChanged)
            loaded.undoEdit(); XCTAssertTrue(loaded.kitChanged)
            loaded.deleteKit(first); XCTAssertEqual(loaded.savedKits.count, 1)
            loaded.undoEdit(); XCTAssertEqual(loaded.savedKits.count, 2)
        }
    }
    @MainActor func testKitNamesAndLegacySession() throws {
        let old = try JSONDecoder().decode(Session.self, from: Data("{\"samples\":[],\"pads\":{}}".utf8))
        XCTAssertNil(old.kits)
        try withLibrary { library, _ in
            library.saveKit(named: "  Test  ")
            library.saveKit(named: "test")
            XCTAssertEqual(library.savedKits.count, 1)
            XCTAssertEqual(library.savedKits.first?.name, "Test")
            XCTAssertNotNil(library.error)
            library.saveKit(named: "  "); XCTAssertEqual(library.savedKits.count, 1)
            library.undoEdit(); XCTAssertTrue(library.savedKits.isEmpty)
            library.redoEdit(); XCTAssertEqual(library.savedKits.count, 1)
        }
    }
}
