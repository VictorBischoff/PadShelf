import Foundation
import CryptoKit
import Darwin

struct SXCard: Identifiable {
    let root: URL
    let identity: String
    let metadata: Data
    var id: String { root.path }
    var name: String { root.lastPathComponent }
    var directory: URL { root.appendingPathComponent("ROLAND/SP-404SX/SMPL", isDirectory: true) }
    var occupied: Int { (0..<120).filter { metadata.big32($0 * 32 + 4) > metadata.big32($0 * 32) }.count }
    func contains(_ key: String) -> Bool {
        guard let index = SXFormat.index(key) else { return false }
        return metadata.big32(index * 32 + 4) > metadata.big32(index * 32)
    }
    static func read(_ root: URL) throws -> SXCard {
        let directory = root.appendingPathComponent("ROLAND/SP-404SX/SMPL")
        guard directory.resolvingSymlinksInPath().standardizedFileURL.path == directory.standardizedFileURL.path else { throw AppFailure(message: "The sample directory must not be a symbolic link.") }
        let path = directory.appendingPathComponent("PAD_INFO.BIN")
        guard path.resolvingSymlinksInPath().path == path.path else { throw AppFailure(message: "The pad metadata must not be a symbolic link.") }
        let data = try Data(contentsOf: path)
        guard data.count == 3840 else { throw AppFailure(message: "This card does not have valid SP-404SX pad metadata. Format it in the sampler first.") }
        for index in 0..<120 {
            let base = index * 32
            guard data.big32(base + 4) >= data.big32(base), data[base + 21] <= 1, [1, 2].contains(data[base + 22]) else { throw AppFailure(message: "Invalid SP-404SX pad record \(index + 1). Card writing is unavailable.") }
        }
        let values = try root.resourceValues(forKeys: [.volumeUUIDStringKey, .fileResourceIdentifierKey])
        let identity = (values.volumeUUIDString ?? root.path) + ":" + String(describing: values.fileResourceIdentifier)
        return SXCard(root: root, identity: identity, metadata: data)
    }
}

extension Data {
    func big32(_ offset: Int) -> UInt32 { (0..<4).reduce(0) { ($0 << 8) | UInt32(self[offset + $1]) } }
    func little32(_ offset: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(self[offset + $1]) << ($1 * 8) } }
    func little16(_ offset: Int) -> Int { Int(self[offset]) | (Int(self[offset + 1]) << 8) }
    mutating func put32(_ value: UInt32, _ offset: Int, big: Bool = false) {
        for i in 0..<4 { self[offset + i] = UInt8(truncatingIfNeeded: value >> ((big ? 3 - i : i) * 8)) }
    }
    mutating func put16(_ value: Int, _ offset: Int) { self[offset] = UInt8(truncatingIfNeeded: value); self[offset + 1] = UInt8(truncatingIfNeeded: value >> 8) }
    mutating func putText(_ text: String, _ offset: Int) { replaceSubrange(offset..<(offset + text.utf8.count), with: text.utf8) }
}

enum SXFormat {
    static func index(_ key: String) -> Int? {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let bank = banks.firstIndex(of: String(parts[0])), let pad = Int(parts[1]), (1...12).contains(pad) else { return nil }
        return bank * 12 + pad - 1
    }
    static func filename(_ index: Int, extension ext: String = "WAV") -> String { String(format: "%@%07d.%@", banks[index / 12], index % 12 + 1, ext) }
    // Roland Wave Converter 1.01 layout: 18-byte fmt, 458-byte RLND payload,
    // roifspsx, 04 00 00 00, zero-based pad index, PCM data at byte 512.
    static func encode(_ wave: Data, index: Int) throws -> (data: Data, channels: Int) {
        guard (0..<120).contains(index), wave.count >= 44, String(data: wave[0..<4], encoding: .ascii) == "RIFF", String(data: wave[8..<12], encoding: .ascii) == "WAVE", Int(wave.little32(4)) + 8 == wave.count else { throw AppFailure(message: "Invalid converted WAV header.") }
        var offset = 12; var pcm: Range<Int>?; var channels = 0
        while offset + 8 <= wave.count {
            let size = Int(wave.little32(offset + 4)); let start = offset + 8
            guard size <= wave.count - start else { throw AppFailure(message: "Truncated WAV chunk.") }
            let tag = String(data: wave[offset..<(offset + 4)], encoding: .ascii)
            if tag == "fmt " {
                guard size >= 16, wave.little16(start) == 1, wave.little32(start + 4) == 44100, wave.little16(start + 14) == 16 else { throw AppFailure(message: "Card audio must be 44.1 kHz, 16-bit PCM.") }
                channels = wave.little16(start + 2)
                guard [1,2].contains(channels), wave.little16(start + 12) == channels * 2 else { throw AppFailure(message: "Invalid channel format.") }
            }
            if tag == "data" { pcm = start..<(start + size) }
            offset = start + size + size % 2
        }
        guard let pcm, channels > 0, !pcm.isEmpty, pcm.count % (channels * 2) == 0, pcm.count < Int(UInt32.max) - 512 else { throw AppFailure(message: "Unsupported sample size or missing audio data.") }
        var output = Data(count: 512)
        output.putText("RIFF", 0); output.put32(UInt32(504 + pcm.count), 4); output.putText("WAVEfmt ", 8)
        output.put32(18, 16); output.put16(1, 20); output.put16(channels, 22); output.put32(44100, 24)
        output.put32(UInt32(44100 * channels * 2), 28); output.put16(channels * 2, 32); output.put16(16, 34)
        output.putText("RLND", 38); output.put32(458, 42); output.putText("roifspsx", 46); output[54] = 4; output[58] = UInt8(index)
        output.putText("data", 504); output.put32(UInt32(pcm.count), 508); output.append(wave[pcm])
        return (output, channels)
    }
    static func update(_ metadata: inout Data, index: Int, size: Int, channels: Int) {
        let base = index * 32
        for offset in [0,8] { metadata.put32(512, base + offset, big: true) }
        for offset in [4,12] { metadata.put32(UInt32(size), base + offset, big: true) }
        metadata[base + 21] = 1; metadata[base + 22] = UInt8(channels); metadata[base + 23] = 0
        metadata.put32(1200, base + 24, big: true); metadata.put32(1200, base + 28, big: true)
    }
}

struct CardAssignment { let key: String; let source: URL; let mono: Bool }
struct CardWriteResult { let backup: URL; let count: Int }
enum CardWriter {
    static func digest(_ url: URL) throws -> Data { Data(SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe))) }
    static func synchronizedCopy(_ source: URL, _ target: URL) throws {
        try FileManager.default.copyItem(at: source, to: target)
        let handle = try FileHandle(forWritingTo: target); defer { try? handle.close() }; try handle.synchronize()
        guard try digest(source) == digest(target) else { throw AppFailure(message: "File verification failed: \(target.lastPathComponent)") }
    }
    static func replace(_ source: URL, _ destination: URL) throws {
        guard rename(source.path, destination.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
    static func write(card: SXCard, assignments: [CardAssignment], backupRoot: URL, beforeCommit: (() throws -> Void)? = nil, afterFile: ((Int) throws -> Void)? = nil) throws -> CardWriteResult {
        let fm = FileManager.default
        let current = try SXCard.read(card.root)
        guard current.identity == card.identity, current.metadata == card.metadata, !assignments.isEmpty else { throw AppFailure(message: "The card changed. Refresh it before writing.") }
        let indices = assignments.compactMap { SXFormat.index($0.key) }
        guard indices.count == assignments.count, Set(indices).count == indices.count else { throw AppFailure(message: "Invalid or duplicate pad assignments.") }
        guard fm.isWritableFile(atPath: card.directory.path) else { throw AppFailure(message: "The card is read-only. Unlock its write-protect switch and reconnect it.") }
        let id = UUID().uuidString
        let backup = backupRoot.appendingPathComponent("Card backup \(id)", isDirectory: true)
        let stage = backup.appendingPathComponent("New files", isDirectory: true)
        let originals = backup.appendingPathComponent("Original files", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        try fm.createDirectory(at: originals, withIntermediateDirectories: true)
        var metadata = current.metadata
        var names = ["PAD_INFO.BIN"]; var replacements: [String] = []
        for (assignment, index) in zip(assignments, indices) {
            let filename = SXFormat.filename(index)
            replacements.append(filename)
            names += [filename, SXFormat.filename(index, extension: "AIF"), SXFormat.filename(index, extension: "AIFF")]
            let converted = stage.appendingPathComponent("converted.wav")
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
            process.arguments = ["-f", "WAVE", "-d", "LEI16@44100", "-c", assignment.mono ? "1" : "2", "--mix", assignment.source.path, converted.path]
            let pipe = Pipe(); process.standardError = pipe
            try process.run(); let message = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw AppFailure(message: "Could not convert \(assignment.key): \(String(data: message, encoding: .utf8) ?? "Audio conversion failed")") }
            let encoded = try SXFormat.encode(Data(contentsOf: converted, options: .mappedIfSafe), index: index)
            try encoded.data.write(to: stage.appendingPathComponent(filename), options: .atomic)
            SXFormat.update(&metadata, index: index, size: encoded.data.count, channels: encoded.channels)
            try fm.removeItem(at: converted)
        }
        try metadata.write(to: stage.appendingPathComponent("PAD_INFO.BIN"), options: .atomic)
        var hashes: [String: Data] = [:]
        for name in names {
            let source = card.directory.appendingPathComponent(name)
            guard source.resolvingSymlinksInPath().path == source.path else { throw AppFailure(message: "A card file is a symbolic link. Writing was stopped.") }
            if fm.fileExists(atPath: source.path) {
                try synchronizedCopy(source, originals.appendingPathComponent(name)); hashes[name] = try digest(source)
            }
        }
        let manifest: [String: Any] = ["card": card.root.path, "identity": card.identity, "affectedFiles": names, "originalFiles": Array(hashes.keys).sorted(), "pads": assignments.map(\.key)]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: backup.appendingPathComponent("Manifest.json"), options: .atomic)
        try "Recovery: copy every file in Original files back into ROLAND/SP-404SX/SMPL. Remove affectedFiles listed in Manifest.json that are absent from originalFiles. Restore PAD_INFO.BIN last. Only restore to the original card; this restores the affected pads to their state before this write.\n".write(to: backup.appendingPathComponent("Recovery.txt"), atomically: true, encoding: .utf8)
        // Stage on the card only after conversion and local backups finish. No live files are changed yet.
        let cardStage = card.root.appendingPathComponent(".PadShelf-stage-\(id)", isDirectory: true)
        guard try SXCard.read(card.root).identity == card.identity else { throw AppFailure(message: "The card was disconnected or replaced.") }
        try fm.createDirectory(at: cardStage, withIntermediateDirectories: false)
        defer { if (try? SXCard.read(card.root).identity) == card.identity { try? fm.removeItem(at: cardStage) } }
        for name in replacements + ["PAD_INFO.BIN"] { try synchronizedCopy(stage.appendingPathComponent(name), cardStage.appendingPathComponent(name)) }
        try beforeCommit?()
        let latest = try SXCard.read(card.root)
        guard latest.identity == card.identity, latest.metadata == current.metadata else { throw AppFailure(message: "The card changed while preparing audio. No live files were replaced.") }
        for name in names {
            let source = card.directory.appendingPathComponent(name)
            if let expected = hashes[name] {
                guard fm.fileExists(atPath: source.path), try digest(source) == expected else { throw AppFailure(message: "Card sample changed during preparation: \(name)") }
            } else if fm.fileExists(atPath: source.path) { throw AppFailure(message: "A new card sample appeared during preparation: \(name)") }
        }
        var touched: [String] = []
        do {
            for (i, name) in replacements.enumerated() {
                guard (try SXCard.read(card.root)).identity == card.identity else { throw AppFailure(message: "The card was disconnected.") }
                touched.append(name)
                try replace(cardStage.appendingPathComponent(name), card.directory.appendingPathComponent(name))
                for ext in ["AIF", "AIFF"] {
                    let alternate = SXFormat.filename(indices[i], extension: ext)
                    if fm.fileExists(atPath: card.directory.appendingPathComponent(alternate).path) { touched.append(alternate); try fm.removeItem(at: card.directory.appendingPathComponent(alternate)) }
                }
                try afterFile?(i)
            }
            touched.append("PAD_INFO.BIN")
            try replace(cardStage.appendingPathComponent("PAD_INFO.BIN"), card.directory.appendingPathComponent("PAD_INFO.BIN"))
            for name in replacements + ["PAD_INFO.BIN"] {
                guard try digest(card.directory.appendingPathComponent(name)) == digest(stage.appendingPathComponent(name)) else { throw AppFailure(message: "Written card verification failed: \(name)") }
            }
        } catch {
            let originalError = error
            do {
                guard (try SXCard.read(card.root)).identity == card.identity else { throw AppFailure(message: "Card unavailable for recovery") }
                for name in touched.filter({ $0 != "PAD_INFO.BIN" }) + (touched.contains("PAD_INFO.BIN") ? ["PAD_INFO.BIN"] : []) {
                    let target = card.directory.appendingPathComponent(name)
                    if hashes[name] != nil {
                        let recovery = cardStage.appendingPathComponent("restore-" + name)
                        try synchronizedCopy(originals.appendingPathComponent(name), recovery); try replace(recovery, target)
                    } else if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                }
                throw AppFailure(message: "Write failed; affected files were restored. \(originalError.localizedDescription) Backup: \(backup.path)")
            } catch let recoveryError as AppFailure where recoveryError.message.hasPrefix("Write failed;") { throw recoveryError }
            catch { throw AppFailure(message: "Write interrupted. Keep this card out of the sampler until restored using \(backup.path)/Recovery.txt. \(originalError.localizedDescription)") }
        }
        try "Verified successfully.\n".write(to: backup.appendingPathComponent("Complete.txt"), atomically: true, encoding: .utf8)
        return CardWriteResult(backup: backup, count: assignments.count)
    }
}
