import XCTest
import AVFoundation
@testable import PadShelf
final class LibraryTests: XCTestCase {
    func testFilenameTypes() {
        XCTAssertEqual(classify("808_kick_01"), "Kick")
        XCTAssertEqual(classify("closed-hihat"), "Closed hi-hat")
        XCTAssertEqual(classify("warm_piano_loop"), "Melodic")
        XCTAssertEqual(classify("recording_07"), "Unsorted")
    }
    @MainActor func testBatchImportAssignmentsAndPersistence() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let sources = temp.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        for name in ["kick.wav", "piano.wav"] {
            let file = try AVAudioFile(forWriting: sources.appendingPathComponent(name), settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
            buffer.frameLength = 4800
            for c in 0..<2 { for i in 0..<4800 { buffer.floatChannelData![c][i] = Float(sin(Double(i) * 0.1)) * 0.1 } }
            try file.write(from: buffer)
        }
        let storage = temp.appendingPathComponent("Library")
        let library = Library(storage: storage)
        library.importFiles([sources])
        for _ in 0..<200 { if !library.busy { break }; try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertFalse(library.busy)
        XCTAssertNil(library.error)
        XCTAssertEqual(library.session.samples.count, 2)
        let kick = try XCTUnwrap(library.session.samples.first { $0.category == "Kick" })
        library.assign(kick.id, to: "A-1")
        library.assign(kick.id, to: "B-12")
        library.setMode("Mono", key: "A-1")
        library.setMode("Stereo", key: "B-12")
        try FileManager.default.removeItem(at: sources)
        let loaded = Library(storage: storage)
        XCTAssertEqual(loaded.session.pads["A-1"], kick.id)
        XCTAssertEqual(loaded.mode("A-1"), "Mono")
        XCTAssertEqual(loaded.mode("B-12"), "Stereo")
        XCTAssertTrue(FileManager.default.fileExists(atPath: loaded.url(kick).path))
        loaded.recategorize(kick.id, "Percussion")
        XCTAssertEqual(loaded.sample(kick.id)?.category, "Percussion")
        loaded.remove(kick.id)
        XCTAssertTrue(loaded.session.pads.isEmpty)
    }
    @MainActor func testBankModeScopePersistenceAndPadOverride() throws {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storage) }
        let library = Library(storage: storage)
        let mono = Sample(id: UUID(), name: "Kick", file: "kick.wav", category: "Kick", duration: 1, rate: 44100, channels: 1)
        let stereo = Sample(id: UUID(), name: "Keys", file: "keys.wav", category: "Melodic", duration: 1, rate: 44100, channels: 2)
        library.session.samples = [mono, stereo]
        library.assign(mono.id, to: "A-1")
        library.assign(stereo.id, to: "A-12")
        library.assign(stereo.id, to: "B-1")
        XCTAssertEqual(library.bankMode("A"), "Mixed")
        library.setBankMode("Mono", bank: "A")
        XCTAssertEqual(library.mode("A-12"), "Mono")
        XCTAssertEqual(library.bankMode("A"), "Mono")
        XCTAssertEqual(library.mode("B-1"), "Stereo")
        XCTAssertNil(library.session.modes?["A-2"])
        let loaded = Library(storage: storage)
        XCTAssertEqual(loaded.bankMode("A"), "Mono")
        loaded.setBankMode("Stereo", bank: "A")
        XCTAssertEqual(loaded.mode("A-1"), "Stereo")
        XCTAssertEqual(loaded.bankMode("A"), "Stereo")
        loaded.setMode("Mono", key: "A-12")
        XCTAssertEqual(loaded.bankMode("A"), "Mixed")
        XCTAssertEqual(loaded.bankMode("C"), "Empty")
        loaded.setBankMode("Mono", bank: "C")
        XCTAssertNil(loaded.session.modes?["C-1"])
    }
    func testOldSessionCanDecodeWithoutModes() throws {
        let old = Data("{\"samples\":[],\"pads\":{}}".utf8)
        XCTAssertNil(try JSONDecoder().decode(Session.self, from: old).modes)
    }
}
