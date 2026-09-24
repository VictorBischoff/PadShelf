import XCTest
import AppKit
@testable import PadShelf

final class SelectionTests: XCTestCase {
    @MainActor func withLibrary(_ action: (Library) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = Library(storage: root)
        library.session.samples = (1...5).map { Sample(id: UUID(), name: "sound\($0)", file: "test.wav", category: "Breaks", duration: Double($0), rate: 44100, channels: 2) }
        try action(library)
    }

    @MainActor func testSelectionRangeToggleAndDragOrder() throws {
        try withLibrary { library in
            let ids = library.visible.map(\.id)
            library.select(ids[1]); library.select(ids[3], range: true)
            XCTAssertEqual(library.selection, Set(ids[1...3]))
            library.select(ids[2], extending: true)
            XCTAssertEqual(library.selection, [ids[1], ids[3]])
            library.sort = .longest
            let text = library.dragText(for: ids[1])
            library.receiveSampleText(text, target: "B-1")
            XCTAssertEqual(library.session.pads["B-1"], ids[3])
            XCTAssertEqual(library.session.pads["B-2"], ids[1])
            XCTAssertEqual(library.dragText(for: ids[0]), ids[0].uuidString)
            XCTAssertEqual(library.selection, [ids[0]])
            library.remove(ids[0]); XCTAssertTrue(library.selection.isEmpty)
        }
    }

    @MainActor func testGroupDropSkipsOccupiedPadsAndOverflowAndPersists() throws {
        try withLibrary { library in
            let ids = library.visible.map(\.id)
            library.assign(ids[4], to: "A-10")
            library.assign(ids[4], to: "B-1")
            library.setMode("Mono", key: "A-10")
            library.assignGroup(Array(ids.prefix(4)), startingAt: "A-9")
            XCTAssertEqual(library.session.pads["A-9"], ids[0])
            XCTAssertEqual(library.session.pads["A-10"], ids[4])
            XCTAssertEqual(library.session.pads["A-11"], ids[1])
            XCTAssertEqual(library.session.pads["A-12"], ids[2])
            XCTAssertEqual(library.session.pads["B-1"], ids[4])
            XCTAssertNil(library.session.pads["A-1"])
            XCTAssertEqual(library.mode("A-10"), "Mono")
            XCTAssertTrue(library.status.contains("Skipped 1"))
            XCTAssertEqual(library.session.samples.count, 5)
            let loaded = Library(storage: library.root)
            XCTAssertEqual(loaded.session.pads, library.session.pads)
            let before = library.session.pads
            library.assignGroup(ids, startingAt: "A-9")
            XCTAssertEqual(library.session.pads, before)
            XCTAssertTrue(library.status.contains("Skipped 5"))
        }
    }

    @MainActor func testDragProviderLoadsMultipleSamples() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = Library(storage: root)
        library.session.samples = (1...3).map { Sample(id: UUID(), name: "sample\($0)", file: "test.wav", category: "Breaks", duration: 1, rate: 44100, channels: 2) }
        let ids = library.visible.map(\.id)
        library.selection = Set(ids)
        let provider = NSItemProvider(object: library.dragText(for: ids[0]) as NSString)
        XCTAssertTrue(library.receive([provider], target: "C-11"))
        for _ in 0..<100 {
            if library.session.pads.count == 2 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(library.session.pads["C-11"], ids[0])
        XCTAssertEqual(library.session.pads["C-12"], ids[1])
        XCTAssertTrue(library.status.contains("Skipped 1"))
    }

    @MainActor func testGroupDropRejectsInvalidInputAndBusyWrites() throws {
        try withLibrary { library in
            let id = library.visible[0].id
            library.assignGroup([id], startingAt: "A-13")
            library.receiveSampleText("padshelf-samples:\(id),bad", target: "A-1")
            library.busy = true; library.assignGroup([id], startingAt: "A-1")
            library.busy = false; library.writable = false
            library.assignGroup([id], startingAt: "A-1")
            XCTAssertTrue(library.session.pads.isEmpty)
            library.writable = true
            library.assignGroup([id, id, UUID()], startingAt: "A-1")
            XCTAssertEqual(library.session.pads.count, 1)
        }
    }
}
