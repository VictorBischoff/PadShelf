import XCTest
import SwiftUI
@testable import PadShelf

final class SortingTests: XCTestCase {
    func testPackNamesAndInstrumentPriority() {
        let examples = [
            "KID-BBapKit-Bells-1": "Bell", "KID-BBapKit-Openhat-2": "Open hi-hat",
            "KID-BBapKit-Tambhat-1": "Tambourine", "KID-BBapKit-Tamb": "Tambourine",
            "TR909_CH_01": "Closed hi-hat", "909_OH02": "Open hi-hat",
            "Hat_Closed_03": "Closed hi-hat", "SoftRideBell_02": "Ride",
            "808_kick_01": "Kick", "808_cow_bell": "Cowbell", "808Snare02": "Snare",
            "CRASH_Cymbal_24": "Crash", "Ride_Cym_01": "Ride", "ChinaCymbal01": "China",
            "Splash03": "Splash", "cymbals_09": "Cymbal", "tubular_bells": "Bell",
            "FloorTom_01": "Tom", "HandClap01": "Clap", "snare_rimshot": "Rimshot",
            "cabasa_loop": "Shaker", "congas": "Conga", "bongos_02": "Bongo",
            "piano_loop_808": "Melodic", "sub_bass": "Bass", "808": "Bass"
        ]
        for (name, expected) in examples { XCTAssertEqual(classify(name), expected, name) }
    }
    func testNoSubstringFalsePositivesAndFolderFallback() {
        for name in ["bride", "crashing", "bellows", "tomorrow", "submarine", "hatred", "kickstarter", "chordless", "recording07"] {
            XCTAssertEqual(classify(name), "Unsorted", name)
        }
        XCTAssertEqual(SoundClassifier.classify("001", folders: ["Crashes", "Cymbals"]), "Crash")
        XCTAssertEqual(SoundClassifier.classify("loop_01", folders: ["Bells"]), "Bell")
        XCTAssertEqual(SoundClassifier.classify("snare01", folders: ["Kicks"]), "Snare")
    }
    @MainActor func testResortingPreservesManualAndLegacyChoicesAndCanUndo() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = Library(storage: root)
        func sound(_ name: String, _ category: String, manual: Bool? = nil) -> Sample {
            Sample(id: UUID(), name: name, file: "test.wav", category: category, duration: 1, rate: 44100, channels: 2, categoryIsManual: manual)
        }
        let bell = sound("Kit_Bells_1", "Unsorted")
        let legacy = sound("Crash01", "Percussion")
        let automatic = sound("OpenHat02", "Hi-hat", manual: false)
        let manual = sound("Ride01", "FX", manual: true)
        library.session.samples = [bell, legacy, automatic, manual]
        library.assign(bell.id, to: "A-1")
        library.reclassify()
        XCTAssertEqual(library.sample(bell.id)?.category, "Bell")
        XCTAssertEqual(library.sample(legacy.id)?.category, "Percussion")
        XCTAssertEqual(library.sample(automatic.id)?.category, "Open hi-hat")
        XCTAssertEqual(library.sample(manual.id)?.category, "FX")
        XCTAssertEqual(library.session.pads["A-1"], bell.id)
        library.recategorize(bell.id, "Melodic")
        library.undoReclassification()
        XCTAssertEqual(library.sample(bell.id)?.category, "Melodic") // A later manual edit wins.
        XCTAssertEqual(library.sample(automatic.id)?.category, "Hi-hat")
        library.reclassify(includeManual: true)
        XCTAssertEqual(library.sample(legacy.id)?.category, "Crash")
        XCTAssertEqual(library.sample(manual.id)?.category, "Ride")
        library.undoReclassification()
        let loaded = Library(storage: root)
        XCTAssertEqual(loaded.sample(manual.id)?.categoryIsManual, true)
        XCTAssertEqual(loaded.sample(manual.id)?.category, "FX")
        XCTAssertNil(loaded.sample(legacy.id)?.categoryIsManual)
    }
    func testListSortOptionsAndNaturalOrder() {
        let short = Sample(id: UUID(), name: "sound10", file: "x", category: "Bell", duration: 1, rate: 44100, channels: 1)
        let long = Sample(id: UUID(), name: "sound2", file: "y", category: "Kick", duration: 3, rate: 44100, channels: 1)
        XCTAssertEqual(SampleSort.name.ordered([short, long]).first?.id, long.id)
        XCTAssertEqual(SampleSort.type.ordered([short, long]).first?.id, long.id)
        XCTAssertEqual(SampleSort.shortest.ordered([long, short]).first?.id, short.id)
        XCTAssertEqual(SampleSort.longest.ordered([short, long]).first?.id, long.id)
    }
    @MainActor func testFooterExpandsForNarrowWindowAndLongStatus() throws {
        let message = "Write interrupted. Keep this card out of the sampler until restored using /Users/Musician/Library/Application Support/PadShelf/Card backups/Card backup 12345/Recovery.txt."
        func size(_ width: CGFloat, _ text: String) throws -> CGSize {
            let renderer = ImageRenderer(content: StatusFooter(status: text, busy: false).frame(width: width))
            return try XCTUnwrap(renderer.nsImage).size
        }
        let narrow = try size(340, message)
        let wide = try size(1200, message)
        let short = try size(340, "Ready.")
        XCTAssertEqual(narrow.width, 340)
        XCTAssertGreaterThan(narrow.height, wide.height)
        XCTAssertGreaterThan(narrow.height, short.height)
        XCTAssertGreaterThan(narrow.height, 60)
    }
}
