import XCTest
import AVFoundation
@testable import PadShelf

final class CardTests: XCTestCase {
    func testMountedCardReadOnlyWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["PADSHELF_TEST_CARD"] else { throw XCTSkip("No card selected for read-only verification") }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let card = try SXCard.read(url)
        XCTAssertEqual(card.identity, try SXCard.read(url).identity)
        XCTAssertEqual(card.metadata.count, 3840)
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: [.skipHiddenVolumes]) ?? []
        XCTAssertTrue(volumes.compactMap { try? SXCard.read($0) }.contains { $0.root.standardizedFileURL.path == url.standardizedFileURL.path })
    }
    func fixture() throws -> (root: URL, card: SXCard, audio: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cardRoot = root.appendingPathComponent("Test SD")
        let directory = cardRoot.appendingPathComponent("ROLAND/SP-404SX/SMPL")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Golden blank record matched against a sampler-formatted card, without modifying it.
        let record: [UInt8] = [0,0,2,0, 0,0,2,0, 0,0,2,0, 0,0,2,0, 127,0,0,1,0,1,2,0, 0,0,4,176, 0,0,4,176]
        var metadata = Data(); for _ in 0..<120 { metadata.append(contentsOf: record) }
        try metadata.write(to: directory.appendingPathComponent("PAD_INFO.BIN"))
        try Data("pattern sentinel".utf8).write(to: directory.appendingPathComponent("STPINFO.BIN"))
        let audio = root.appendingPathComponent("input.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        do {
            let file = try AVAudioFile(forWriting: audio, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
            buffer.frameLength = 4800
            for c in 0..<2 { for i in 0..<4800 { buffer.floatChannelData![c][i] = Float(sin(Double(i) * (c == 0 ? 0.1 : 0.2))) * 0.2 } }
            try file.write(from: buffer)
        }
        return (root, try SXCard.read(cardRoot), audio)
    }
    func testDirectWriteFormatAndPreservation() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let untouched = f.card.directory.appendingPathComponent("B0000002.WAV")
        try Data("untouched audio".utf8).write(to: untouched)
        let oldAIFF = f.card.directory.appendingPathComponent("A0000001.AIF")
        try Data("old AIFF audio".utf8).write(to: oldAIFF)
        let result = try CardWriter.write(card: f.card, assignments: [CardAssignment(key: "A-1", source: f.audio, mono: true), CardAssignment(key: "J-12", source: f.audio, mono: false)], backupRoot: f.root.appendingPathComponent("Backups"))
        XCTAssertEqual(result.count, 2)
        let metadata = try Data(contentsOf: f.card.directory.appendingPathComponent("PAD_INFO.BIN"))
        XCTAssertEqual(metadata.count, 3840)
        XCTAssertEqual(metadata[32..<(119*32)], f.card.metadata[32..<(119*32)])
        for (index, name, channels) in [(0,"A0000001.WAV",1), (119,"J0000012.WAV",2)] {
            let url = f.card.directory.appendingPathComponent(name)
            let wave = try Data(contentsOf: url)
            XCTAssertEqual(String(data: wave[38..<42], encoding: .ascii), "RLND")
            XCTAssertEqual(String(data: wave[46..<54], encoding: .ascii), "roifspsx")
            XCTAssertEqual(wave[54], 4); XCTAssertEqual(wave[58], UInt8(index))
            XCTAssertEqual(String(data: wave[504..<508], encoding: .ascii), "data")
            XCTAssertEqual(wave.count, 512 + 4410 * channels * 2)
            XCTAssertEqual(metadata.big32(index * 32), 512)
            XCTAssertEqual(metadata.big32(index * 32 + 4), UInt32(wave.count))
            XCTAssertEqual(metadata[index * 32 + 22], UInt8(channels))
            let audio = try AVAudioFile(forReading: url)
            XCTAssertEqual(audio.processingFormat.sampleRate, 44100)
            XCTAssertEqual(audio.processingFormat.channelCount, UInt32(channels))
            XCTAssertEqual(audio.length, 4410)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldAIFF.path))
        XCTAssertEqual(try Data(contentsOf: untouched), Data("untouched audio".utf8))
        XCTAssertEqual(try Data(contentsOf: f.card.directory.appendingPathComponent("STPINFO.BIN")), Data("pattern sentinel".utf8))
        XCTAssertEqual(try Data(contentsOf: result.backup.appendingPathComponent("Original files/A0000001.AIF")), Data("old AIFF audio".utf8))
        XCTAssertEqual(try Data(contentsOf: result.backup.appendingPathComponent("Original files/PAD_INFO.BIN")), f.card.metadata)
        XCTAssertEqual(try SXCard.read(f.card.root).occupied, 2)
    }
    func testCommitFailureRestoresOriginals() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let existing = f.card.directory.appendingPathComponent("A0000001.WAV")
        try Data("original audio".utf8).write(to: existing)
        XCTAssertThrowsError(try CardWriter.write(card: f.card, assignments: [CardAssignment(key: "A-1", source: f.audio, mono: true)], backupRoot: f.root.appendingPathComponent("Backups"), afterFile: { _ in throw AppFailure(message: "Injected write failure") }))
        XCTAssertEqual(try Data(contentsOf: existing), Data("original audio".utf8))
        XCTAssertEqual(try Data(contentsOf: f.card.directory.appendingPathComponent("PAD_INFO.BIN")), f.card.metadata)
    }
    func testConcurrentCardChangeAbortsBeforeCommit() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        var changed = f.card.metadata; changed[16] = 100
        XCTAssertThrowsError(try CardWriter.write(card: f.card, assignments: [CardAssignment(key: "A-1", source: f.audio, mono: true)], backupRoot: f.root.appendingPathComponent("Backups"), beforeCommit: {
            try changed.write(to: f.card.directory.appendingPathComponent("PAD_INFO.BIN"))
        }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.card.directory.appendingPathComponent("A0000001.WAV").path))
        XCTAssertEqual(try Data(contentsOf: f.card.directory.appendingPathComponent("PAD_INFO.BIN")), changed)
    }
    func testInvalidCardAndInputFailWithoutChangingLiveFiles() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        XCTAssertThrowsError(try CardWriter.write(card: f.card, assignments: [CardAssignment(key: "A-1", source: f.root.appendingPathComponent("missing.wav"), mono: false)], backupRoot: f.root.appendingPathComponent("Backups")))
        XCTAssertEqual(try Data(contentsOf: f.card.directory.appendingPathComponent("PAD_INFO.BIN")), f.card.metadata)
        XCTAssertThrowsError(try SXFormat.encode(Data(repeating: 0, count: 60), index: 0))
        XCTAssertNil(SXFormat.index("K-1")); XCTAssertNil(SXFormat.index("A-0"))
        try Data([0]).write(to: f.card.directory.appendingPathComponent("PAD_INFO.BIN"))
        XCTAssertThrowsError(try SXCard.read(f.card.root))
    }
}
