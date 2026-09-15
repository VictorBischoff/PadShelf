import Foundation

let categories = ["Kick", "Snare", "Clap", "Rimshot", "Hi-hat", "Open hi-hat", "Closed hi-hat", "Crash", "Ride", "Splash", "China", "Cymbal", "Bell", "Cowbell", "Tom", "Shaker", "Tambourine", "Conga", "Bongo", "Percussion", "Bass", "Melodic", "Vocal", "FX", "Unsorted"]

/// Filename vocabulary, not audio-content recognition. Specific instruments outrank
/// generic kit/loop/808 hints; whole tokens prevent matches like "bride" → "Ride".
enum SoundClassifier {
    struct Rule {
        let category: String
        let score: Int
        let aliases: [String]
    }
    static let rules: [Rule] = [
        .init(category: "Cowbell", score: 120, aliases: ["cowbell", "cowbells", "cow bell", "cow bells"]),
        .init(category: "Tambourine", score: 115, aliases: ["tambourine", "tambourines", "tamb", "tambhat", "tamb hat"]),
        .init(category: "Open hi-hat", score: 115, aliases: ["openhat", "open hat", "open hats", "open hihat", "open hi hat", "open hh", "hat open", "hihat open", "hi hat open", "hh open", "ohh", "oh"]),
        .init(category: "Closed hi-hat", score: 115, aliases: ["closedhat", "closed hat", "closed hats", "closed hihat", "closed hi hat", "closed hh", "hat closed", "hihat closed", "hi hat closed", "hh closed", "chh", "ch"]),
        .init(category: "Ride", score: 110, aliases: ["ride", "rides", "ridebell", "ride bell", "ridecymbal", "ride cymbal"]),
        .init(category: "Crash", score: 110, aliases: ["crash", "crashes", "crashcymbal", "crash cymbal", "crsh"]),
        .init(category: "Splash", score: 110, aliases: ["splash", "splashes", "splashcymbal", "splash cymbal"]),
        .init(category: "China", score: 110, aliases: ["china", "chinacymbal", "china cymbal"]),
        .init(category: "Rimshot", score: 110, aliases: ["rimshot", "rimshots", "rim shot", "rim", "sidestick", "side stick", "crossstick", "cross stick"]),
        .init(category: "Clap", score: 105, aliases: ["clap", "claps", "handclap", "hand clap", "clp"]),
        .init(category: "Kick", score: 105, aliases: ["kick", "kicks", "kik", "bd", "bassdrum", "bass drum"]),
        .init(category: "Snare", score: 105, aliases: ["snare", "snares", "snr", "sd"]),
        .init(category: "Hi-hat", score: 100, aliases: ["hihat", "hihats", "hi hat", "hi hats", "hat", "hats", "hh", "pedalhat", "pedal hat"]),
        .init(category: "Bell", score: 100, aliases: ["bell", "bells", "chime", "chimes", "glock", "glockenspiel", "tubular bell", "tubular bells", "agogo"]),
        .init(category: "Tom", score: 100, aliases: ["tom", "toms", "tomtom", "tom tom", "floortom", "floor tom", "racktom", "rack tom"]),
        .init(category: "Shaker", score: 100, aliases: ["shaker", "shakers", "shk", "maraca", "maracas", "cabasa"]),
        .init(category: "Conga", score: 100, aliases: ["conga", "congas", "tumba", "quinto"]),
        .init(category: "Bongo", score: 100, aliases: ["bongo", "bongos"]),
        .init(category: "Cymbal", score: 80, aliases: ["cymbal", "cymbals", "cym", "cymb", "cymbale"]),
        .init(category: "Percussion", score: 60, aliases: ["perc", "percussion", "triangle", "clave", "claves", "woodblock", "wood block", "guiro", "djembe", "timbale", "timbales", "tabla"]),
        .init(category: "Bass", score: 55, aliases: ["bass", "sub", "subbass", "sub bass"]),
        .init(category: "Melodic", score: 55, aliases: ["melodic", "melody", "piano", "keys", "chord", "chords", "guitar", "synth", "strings", "string", "organ", "flute", "pad", "pluck", "marimba", "vibes", "vibraphone"]),
        .init(category: "Vocal", score: 70, aliases: ["vocal", "vocals", "vox", "voice", "acapella", "acappella", "a cappella"]),
        .init(category: "FX", score: 65, aliases: ["fx", "sfx", "riser", "impact", "sweep", "noise", "woosh", "whoosh"]),
        .init(category: "Bass", score: 10, aliases: ["808"]),
        .init(category: "Melodic", score: 5, aliases: ["loop", "loops"])
    ]
    static func tokens(_ value: String) -> [String] {
        let camel = value.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "([A-Z]+)([A-Z][a-z])", with: "$1 $2", options: .regularExpression)
        let separated = camel.replacingOccurrences(of: "([a-zA-Z])([0-9])|([0-9])([a-zA-Z])", with: "$1$3 $2$4", options: .regularExpression)
        return separated.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
    static func match(_ value: String) -> (category: String, score: Int)? {
        let words = tokens(value)
        var best: (category: String, score: Int)?
        for rule in rules {
            let matches = rule.aliases.contains { alias in
                let phrase = alias.split(separator: " ").map(String.init)
                guard phrase.count <= words.count else { return false }
                return (0...(words.count - phrase.count)).contains { start in Array(words[start..<(start + phrase.count)]) == phrase }
            }
            if matches, rule.score > (best?.score ?? 0) { best = (rule.category, rule.score) }
        }
        return best
    }
    static func classify(_ name: String, folders: [String] = []) -> String {
        let filenameMatch = match(name)
        if let filenameMatch, filenameMatch.score >= 50 { return filenameMatch.category }
        // Parent folder first. Generic names like 001.wav or loop_01.wav benefit
        // from sample-pack folders, but explicit instrument names always win.
        for folder in folders.prefix(3) {
            if let candidate = match(folder), candidate.score >= 50 { return candidate.category }
        }
        return filenameMatch?.category ?? "Unsorted"
    }
}
func classify(_ name: String) -> String { SoundClassifier.classify(name) }

enum SampleSort: String, CaseIterable, Identifiable {
    case name = "Name", type = "Sound type", shortest = "Shortest first", longest = "Longest first"
    var id: String { rawValue }
    func ordered(_ samples: [Sample]) -> [Sample] {
        samples.sorted { lhs, rhs in
            if self == .type, lhs.category != rhs.category { return (categories.firstIndex(of: lhs.category) ?? categories.count) < (categories.firstIndex(of: rhs.category) ?? categories.count) }
            if self == .shortest, lhs.duration != rhs.duration { return lhs.duration < rhs.duration }
            if self == .longest, lhs.duration != rhs.duration { return lhs.duration > rhs.duration }
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            return comparison == .orderedSame ? lhs.id.uuidString < rhs.id.uuidString : comparison == .orderedAscending
        }
    }
}
