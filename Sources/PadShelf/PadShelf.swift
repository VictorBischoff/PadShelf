import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

let accent = Color(red: 0.96, green: 0.40, blue: 0.22)
let surface = Color(red: 0.105, green: 0.115, blue: 0.125)
let banks = Array("ABCDEFGHIJ").map(String.init)
func categoryColor(_ category: String) -> Color {
    switch category { case "Kick": return accent; case "Snare": return .yellow; case "Hi-hat", "Open hi-hat", "Closed hi-hat": return .mint; case "Crash", "Ride", "Splash", "China", "Cymbal": return .teal; case "Bell", "Cowbell": return .orange; case "Clap", "Rimshot": return .yellow; case "Percussion", "Tom", "Shaker", "Tambourine", "Conga", "Bongo": return .green; case "Breaks": return .orange; case "Bass": return .purple; case "Melodic": return .cyan; case "Vocal": return .pink; case "FX": return .indigo; default: return .gray }
}
struct Sample: Identifiable, Codable {
    var id: UUID
    var name: String
    var file: String
    var category: String
    var duration: Double
    var rate: Double
    var channels: Int
    var categoryIsManual: Bool? = nil
    var sourceFolders: [String]? = nil
}
struct Session: Codable { var samples: [Sample] = []; var pads: [String: UUID] = [:]; var modes: [String: String]? = [:] }
struct AppFailure: LocalizedError { var message: String; var errorDescription: String? { message } }

@MainActor final class Library: ObservableObject {
    @Published var session = Session()
    @Published var category = "All sounds"
    @Published var search = ""
    @Published var sort: SampleSort = .name
    @Published var classificationUndo: [UUID: Sample] = [:]
    @Published var bank = "A"
    @Published var selected: UUID?
    @Published var playing: UUID?
    @Published var busy = false
    @Published var status = "Your next beat starts here."
    @Published var error: String?
    @Published var cards: [SXCard] = []
    @Published var cardID = ""
    @Published var lastCardBackup: URL?
    var cardTimer: Timer?
    var scanningCards = false
    let root: URL
    var player: AVAudioPlayer?
    var playbackTimer: Timer?
    var writable = true
    init(storage: URL? = nil) {
        root = storage ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PadShelf", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("Audio"), withIntermediateDirectories: true)
            let url = root.appendingPathComponent("Library.json")
            if FileManager.default.fileExists(atPath: url.path) { session = try JSONDecoder().decode(Session.self, from: Data(contentsOf: url)) }
        } catch { writable = false; self.error = "Could not open your library. Existing data has been preserved. \(error.localizedDescription)" }
        if storage == nil { startCardMonitoring() }
    }
    var visible: [Sample] { sort.ordered(session.samples.filter { (category == "All sounds" || $0.category == category) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }) }
    func url(_ sample: Sample) -> URL { root.appendingPathComponent("Audio").appendingPathComponent(sample.file) }
    func sample(_ id: UUID?) -> Sample? { session.samples.first { $0.id == id } }
    func key(_ pad: Int) -> String { "\(bank)-\(pad)" }
    func save() {
        guard writable else { return }
        do { try JSONEncoder().encode(session).write(to: root.appendingPathComponent("Library.json"), options: .atomic) }
        catch { self.error = "Could not save the library: \(error.localizedDescription)" }
    }
    func chooseImport() {
        let p = NSOpenPanel(); p.title = "Import sounds or sample folders"; p.allowsMultipleSelection = true; p.canChooseDirectories = true; p.canChooseFiles = true
        if p.runModal() == .OK { importFiles(p.urls) }
    }
    func importFiles(_ urls: [URL], target: String? = nil) {
        guard !busy, writable else { return }
        busy = true; status = "Importing sounds…"
        let destination = root.appendingPathComponent("Audio")
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> ([Sample], [String]) in
                var files: [URL] = []; var added: [Sample] = []; var failures: [String] = []
                let extensions = ["wav", "wave", "aif", "aiff", "mp3", "m4a", "aac", "caf", "flac"]
                for url in urls {
                    if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                            files += e.compactMap { $0 as? URL }.filter { extensions.contains($0.pathExtension.lowercased()) }
                        }
                    } else { files.append(url) }
                }
                var seen = Set<String>()
                for file in files.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) where seen.insert(file.standardizedFileURL.path).inserted {
                    do {
                        let audio = try AVAudioFile(forReading: file)
                        guard audio.length > 0, audio.processingFormat.channelCount <= 2 else { throw AppFailure(message: "Only nonempty mono or stereo audio is supported") }
                        let id = UUID(); let filename = id.uuidString + "." + file.pathExtension
                        var parent = file.deletingLastPathComponent()
                        var folders: [String] = []
                        for _ in 0..<3 { if parent.path == "/" { break }; folders.append(parent.lastPathComponent); parent.deleteLastPathComponent() }
                        try FileManager.default.copyItem(at: file, to: destination.appendingPathComponent(filename))
                        added.append(Sample(id: id, name: file.deletingPathExtension().lastPathComponent, file: filename, category: SoundClassifier.classify(file.deletingPathExtension().lastPathComponent, folders: folders), duration: Double(audio.length) / audio.processingFormat.sampleRate, rate: audio.processingFormat.sampleRate, channels: Int(audio.processingFormat.channelCount), categoryIsManual: false, sourceFolders: folders))
                    } catch { failures.append("\(file.lastPathComponent): \(error.localizedDescription)") }
                }
                return (added, failures)
            }.value
            session.samples += result.0
            if let target, let first = result.0.first { session.pads[target] = first.id }
            save(); busy = false; status = "Imported \(result.0.count) sounds" + (result.1.isEmpty ? ". Ready to arrange." : "; \(result.1.count) could not be read.")
            if !result.1.isEmpty { error = result.1.prefix(8).joined(separator: "\n") }
        }
    }
    func preview(_ sample: Sample) {
        if playing == sample.id { stop(); return }
        do {
            stop(); player = try AVAudioPlayer(contentsOf: url(sample)); player?.play(); playing = sample.id
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                Task { @MainActor in if self?.player?.isPlaying == false { self?.stop() } }
            }
        } catch { self.error = error.localizedDescription }
    }
    func stop() { player?.stop(); playing = nil; playbackTimer?.invalidate(); playbackTimer = nil }
    func assign(_ id: UUID, to key: String) { guard sample(id) != nil, !busy else { return }; session.pads[key] = id; save(); status = "Assigned sound to \(key)." }
    func mode(_ key: String) -> String { session.modes?[key] ?? (sample(session.pads[key])?.channels == 1 ? "Mono" : "Stereo") }
    func setMode(_ mode: String, key: String) { if session.modes == nil { session.modes = [:] }; session.modes?[key] = mode; save() }
    func bankMode(_ bank: String) -> String {
        let modes = Set((1...12).compactMap { pad -> String? in
            let key = "\(bank)-\(pad)"
            return session.pads[key] == nil ? nil : mode(key)
        })
        return modes.isEmpty ? "Empty" : modes.count == 1 ? modes.first! : "Mixed"
    }
    func setBankMode(_ mode: String, bank: String) {
        guard !busy, writable, banks.contains(bank), ["Stereo", "Mono"].contains(mode) else { return }
        if session.modes == nil { session.modes = [:] }
        var count = 0
        for pad in 1...12 {
            let key = "\(bank)-\(pad)"
            if session.pads[key] != nil { session.modes?[key] = mode; count += 1 }
        }
        guard count > 0 else { return }
        save()
        status = "Bank \(bank): \(count) assigned pads set to \(mode.lowercased())."
    }
    func clear(_ pad: Int) { session.pads.removeValue(forKey: key(pad)); save() }
    func recategorize(_ id: UUID, _ value: String) { if let i = session.samples.firstIndex(where: { $0.id == id }) { session.samples[i].category = value; session.samples[i].categoryIsManual = true; classificationUndo.removeValue(forKey: id); save() } }
    func reclassify(includeManual: Bool = false) {
        guard !busy, writable else { return }
        classificationUndo = [:]
        for i in session.samples.indices {
            let sample = session.samples[i]
            let eligible = sample.categoryIsManual == false || (sample.categoryIsManual == nil && sample.category == "Unsorted")
            guard includeManual || eligible else { continue }
            let updated = SoundClassifier.classify(sample.name, folders: sample.sourceFolders ?? [])
            guard updated != sample.category || sample.categoryIsManual != false else { continue }
            classificationUndo[sample.id] = sample
            session.samples[i].category = updated
            session.samples[i].categoryIsManual = false
        }
        save(); status = "Re-sorted \(classificationUndo.count) sounds. Pad assignments are unchanged."
    }
    func confirmReclassifyAll() {
        let alert = NSAlert(); alert.messageText = "Re-sort all sounds?"
        alert.informativeText = "This replaces all sound categories, including your manual choices, using filename and saved folder hints. Pad assignments stay in place. You can undo this re-sort."
        alert.addButton(withTitle: "Re-sort all"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { reclassify(includeManual: true) }
    }
    func undoReclassification() {
        guard !busy, writable else { return }
        for i in session.samples.indices {
            if let original = classificationUndo[session.samples[i].id] {
                session.samples[i].category = original.category
                session.samples[i].categoryIsManual = original.categoryIsManual
            }
        }
        classificationUndo = [:]; save(); status = "Previous sound categories restored."
    }
    func remove(_ id: UUID) {
        if playing == id { stop() }
        session.samples.removeAll { $0.id == id }; session.pads = session.pads.filter { $0.value != id }; if selected == id { selected = nil }; save()
    }
    func receive(_ providers: [NSItemProvider], target: String? = nil) -> Bool {
        guard !busy else { return false }
        if let item = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }), let target {
            item.loadObject(ofClass: NSString.self) { object, _ in
                if let text = object as? String, let id = UUID(uuidString: text) { Task { @MainActor in self.assign(id, to: target) } }
            }; return true
        }
        let items = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !items.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for item in items {
                let url: URL? = await withCheckedContinuation { continuation in
                    item.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, _ in
                        if let data = value as? Data { continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil)) }
                        else { continuation.resume(returning: value as? URL) }
                    }
                }
                if let url { urls.append(url) }
            }
            importFiles(urls, target: target)
        }; return true
    }
    func export() {
        guard !busy, !session.pads.isEmpty else { return }
        let panel = NSOpenPanel(); panel.title = "Choose a destination for your WAV kit"; panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.prompt = "Export kit"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let samples = session.samples; let assignments = session.pads; let modes = session.modes ?? [:]; let source = root.appendingPathComponent("Audio")
        busy = true; status = "Converting kit to 44.1 kHz / 16-bit WAV…"
        Task {
            do {
                let output = try await Task.detached(priority: .userInitiated) { () throws -> URL in
                    let folder = destination.appendingPathComponent("PadShelf Kit \(UUID().uuidString.prefix(8))", isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                    do {
                        var map = "Bank,Pad,Sample,Channels,File\n"
                        for bank in banks {
                            for pad in 1...12 {
                                let key = "\(bank)-\(pad)"
                                guard let id = assignments[key], let sample = samples.first(where: { $0.id == id }) else { continue }
                                let bankFolder = folder.appendingPathComponent("Bank \(bank)")
                                try FileManager.default.createDirectory(at: bankFolder, withIntermediateDirectories: true)
                                let filename = String(format: "%@%02d.wav", bank, pad)
                                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
                                let mode = modes[key] ?? (sample.channels == 1 ? "Mono" : "Stereo")
                                process.arguments = ["-f", "WAVE", "-d", "LEI16@44100", "-c", mode == "Mono" ? "1" : "2", "--mix", source.appendingPathComponent(sample.file).path, bankFolder.appendingPathComponent(filename).path]
                                let pipe = Pipe(); process.standardError = pipe
                                try process.run(); let diagnostic = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                                guard process.terminationStatus == 0 else { throw AppFailure(message: "Conversion failed for \(sample.name): \(String(data: diagnostic, encoding: .utf8) ?? "Unknown error")") }
                                map += "\(bank),\(pad),\"\(sample.name.replacingOccurrences(of: "\"", with: "\"\""))\",\(mode),Bank \(bank)/\(filename)\n"
                            }
                        }
                        try map.write(to: folder.appendingPathComponent("Pad Map.csv"), atomically: true, encoding: .utf8)
                        let instructions = """
                        PadShelf — WAV kit
                        Audio: 44.1 kHz, signed 16-bit PCM WAV; per-pad mono/stereo settings applied. Stereo sources are downmixed for mono; mono sources selected as stereo use two matching channels.
                        Pad Map.csv records your intended assignments. Empty pads have no files.

                        This is a WAV export, not a directly playable SP-404SX SD-card image.
                        File names do not automatically assign pads on the hardware.
                        Use Roland Wave Converter to assign these WAV files according to the pad map,
                        or use the SP-404SX manual import procedure, choosing each destination pad.
                        For manual import, copy WAVs into ROLAND/IMPORT on a card formatted by the
                        SP-404SX. Follow the owner's manual; import one sound at a time if you need
                        to preserve gaps in the layout. Do not replace the card's system files.
                        https://www.roland.com/global/support/by_product/sp-404sx/owners_manuals/
                        """
                        try instructions.write(to: folder.appendingPathComponent("Read Me.txt"), atomically: true, encoding: .utf8)
                        return folder
                    } catch { try? FileManager.default.removeItem(at: folder); throw error }
                }.value
                status = "Kit exported. WAV files and pad map are ready."; NSWorkspace.shared.activateFileViewerSelecting([output])
            } catch { self.error = error.localizedDescription; status = "Export failed. Your library is unchanged." }
            busy = false
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var library: Library
    @State private var libraryDrop = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.3x3.fill").font(.title2).foregroundStyle(accent)
                Text("PAD / SHELF").font(.system(size: 19, weight: .heavy, design: .monospaced)).tracking(2)
                Text("SAMPLE WORKSPACE").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(.secondary).padding(.leading, 16)
                Spacer()
                if library.busy { ProgressView().controlSize(.small) }
                Button { library.chooseImport() } label: { Label("Import sounds", systemImage: "plus") }.keyboardShortcut("i", modifiers: .command)
                Button { library.export() } label: { Label("Export WAV kit", systemImage: "square.and.arrow.up") }.tint(accent).buttonStyle(.borderedProminent).disabled(library.session.pads.isEmpty || library.busy)
            }.padding(22).background(surface)
            Divider()
            cardConnection
            Divider()
            HStack(spacing: 0) {
                sidebar.frame(width: 176)
                Divider()
                soundList.frame(minWidth: 285, idealWidth: 340, maxWidth: 420)
                Divider()
                ScrollView { pads }.frame(minWidth: 460, maxWidth: .infinity)
            }
            Divider()
            StatusFooter(status: library.status, busy: library.busy)
        }.background(Color(red: 0.07, green: 0.08, blue: 0.09)).preferredColorScheme(.dark)
        .frame(minWidth: 1000, minHeight: 600)
        .alert("PadShelf", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) { Button("OK") { library.error = nil } } message: { Text(library.error ?? "") }
    }
    var cardConnection: some View {
        HStack(spacing: 12) {
            Image(systemName: "sdcard").foregroundStyle(library.connectedCard == nil ? Color.gray : Color.green)
            if library.cards.isEmpty {
                Text("Insert an SD card formatted by the SP-404SX").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Picker("SD card", selection: $library.cardID) {
                    Text("Select card").tag("")
                    ForEach(library.cards) { card in Text(card.name).tag(card.id) }
                }.frame(maxWidth: 220).disabled(library.busy)
                if let card = library.connectedCard {
                    Text("\(card.occupied) pads on card").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let backup = library.lastCardBackup {
                Button("Show backup") { NSWorkspace.shared.activateFileViewerSelecting([backup]) }
            }
            Button { library.refreshCards() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh connected cards").disabled(library.busy)
            Button("Eject") { library.ejectCard() }.disabled(library.connectedCard == nil || library.busy)
            Button { library.writeCard() } label: { Label("Write SD card", systemImage: "sdcard.fill") }
                .buttonStyle(.borderedProminent).tint(accent)
                .disabled(library.connectedCard == nil || library.session.pads.isEmpty || library.busy)
        }.controlSize(.small).padding(.horizontal, 22).padding(.vertical, 10).background(surface.opacity(0.65))
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("YOUR LIBRARY").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary).padding(.bottom, 14)
            categoryRow("All sounds", icon: "square.stack.3d.up")
            Divider().padding(.vertical, 12)
            Text("SOUND TYPE").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary).padding(.bottom, 9)
            ScrollView { VStack(spacing: 5) { ForEach(categories, id: \.self) { category in categoryRow(category, icon: "circle.fill") } } }
            Spacer()
            Image(systemName: "internaldrive").font(.title2).foregroundStyle(.secondary)
            Text("Made for your Mac.").font(.system(size: 12, weight: .medium))
            Text("Your sounds stay local.").font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(16).background(surface.opacity(0.4))
    }
    func categoryRow(_ category: String, icon: String) -> some View {
        Button { library.category = category } label: {
            HStack {
                Image(systemName: icon).font(.system(size: category == "All sounds" ? 13 : 7)).foregroundStyle(categoryColor(category)).frame(width: 18)
                Text(category).font(.system(size: 12))
                Spacer()
                Text("\(category == "All sounds" ? library.session.samples.count : library.session.samples.filter { $0.category == category }.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(.horizontal, 8).padding(.vertical, 9).background(library.category == category ? Color.white.opacity(0.08) : .clear).clipShape(RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }
    var soundList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text(library.category).font(.system(size: 22, weight: .semibold)); Spacer(); Text("\(library.visible.count)").foregroundStyle(.secondary) }.padding(.bottom, 5)
            Text("Preview a sound. Drag it to a pad.").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("Search sounds", text: $library.search).textFieldStyle(.roundedBorder).padding(.top, 14).padding(.bottom, 10)
            HStack {
                Picker("Sort", selection: $library.sort) { ForEach(SampleSort.allCases) { Text($0.rawValue).tag($0) } }.frame(maxWidth: 185)
                Spacer(minLength: 4)
                Menu("Re-sort") {
                    Button("Unsorted & automatic categories") { library.reclassify() }
                    Button("All sounds, including manual…") { library.confirmReclassifyAll() }
                    Divider()
                    Button("Undo last re-sort") { library.undoReclassification() }.disabled(library.classificationUndo.isEmpty)
                }.fixedSize().disabled(library.busy || library.session.samples.isEmpty)
            }.controlSize(.small).padding(.bottom, 12)
            if library.visible.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "waveform.badge.plus").font(.system(size: 36, weight: .light)).foregroundStyle(accent)
                    Text(library.session.samples.isEmpty ? "Bring your sounds." : "No matching sounds").font(.headline)
                    Text(library.session.samples.isEmpty ? "Drop files or folders here, or import a whole sample pack at once." : "Try another category or search.").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if library.session.samples.isEmpty { Button("Import sounds…") { library.chooseImport() } }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(library.visible) { sample in
                            HStack(spacing: 10) {
                                Button { library.preview(sample) } label: { Image(systemName: library.playing == sample.id ? "stop.fill" : "play.fill").font(.system(size: 10)).foregroundStyle(categoryColor(sample.category)).frame(width: 30, height: 32).background(categoryColor(sample.category).opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 6)) }.buttonStyle(.plain)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(sample.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text("\(sample.category.uppercased())  ·  \(sample.duration, specifier: "%.2f")s").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "line.3.horizontal").font(.system(size: 10)).foregroundStyle(.tertiary)
                            }.padding(9).background(library.selected == sample.id ? Color.white.opacity(0.10) : surface).clipShape(RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle()).onTapGesture { library.selected = sample.id }
                            .onDrag { library.selected = sample.id; return NSItemProvider(object: sample.id.uuidString as NSString) }
                            .contextMenu {
                                Button("Preview") { library.preview(sample) }
                                Menu("Sound type") { ForEach(categories, id: \.self) { category in Button(category) { library.recategorize(sample.id, category) } } }
                                Divider()
                                Button("Remove from library & pads", role: .destructive) { library.remove(sample.id) }
                            }
                        }
                    }
                }
            }
            Divider().padding(.top, 12)
            Text("Types use filenames and folder hints.\nRight-click to set a type; Re-sort to update.").font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 12)
        }.padding(20).background(libraryDrop ? accent.opacity(0.06) : .clear)
        .onDrop(of: [UTType.fileURL], isTargeted: $libraryDrop) { library.receive($0) }
    }
    var pads: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) { Text("Build your bank.").font(.system(size: 27, weight: .semibold)); Text("SP-404SX layout  /  12 pads per bank").font(.system(size: 12)).foregroundStyle(.secondary) }
                Spacer()
                Text("\((1...12).filter { library.session.pads[library.key($0)] != nil }.count) / 12").font(.system(size: 12, design: .monospaced)).foregroundStyle(accent).padding(9).background(accent.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 5))
            }
            HStack(spacing: 5) {
                ForEach(banks, id: \.self) { bank in
                    Button { library.bank = bank } label: { Text(bank).font(.system(size: 12, weight: .bold, design: .monospaced)).frame(maxWidth: .infinity).frame(height: 32).background(library.bank == bank ? accent : Color.white.opacity(0.05)).foregroundStyle(library.bank == bank ? .black : .white).clipShape(RoundedRectangle(cornerRadius: 5)) }.buttonStyle(.plain)
                }
            }
            HStack {
                Text("BANK \(library.bank) OUTPUT").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Set assigned pads to Stereo") { library.setBankMode("Stereo", bank: library.bank) }
                    Button("Set assigned pads to Mono") { library.setBankMode("Mono", bank: library.bank) }
                } label: {
                    Text(library.bankMode(library.bank)).font(.system(size: 11, weight: .medium))
                }.fixedSize().disabled(library.busy || library.bankMode(library.bank) == "Empty")
                .help("Apply Stereo or Mono to every assigned pad in this bank. You can still change individual pads afterward.")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(1...12, id: \.self) { pad in PadView(pad: pad).id(library.key(pad)) }
            }
            HStack { Image(systemName: "cursorarrow.motionlines"); Text("Drag to assign · Click to preview · Right-click to clear") }.font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Image(systemName: "waveform").font(.title2).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) { Text(library.sample(library.playing)?.name ?? "Ready when you are.").font(.system(size: 12, weight: .medium)).lineLimit(1); Text(library.playing == nil ? "Choose any sound or assigned pad to listen." : "PREVIEWING  /  ORIGINAL AUDIO").font(.system(size: 10)).foregroundStyle(.secondary) }
                Spacer()
                if library.playing != nil { Button { library.stop() } label: { Image(systemName: "stop.fill") } }
            }.padding(14).background(surface).clipShape(RoundedRectangle(cornerRadius: 8))
            Text("Write SD card applies your assignments directly to the sampler card. Unassigned pads keep their card sounds. Preview uses the original audio.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(24)
    }
}
struct PadView: View {
    @EnvironmentObject var library: Library
    let pad: Int
    @State private var targeted = false
    var sample: Sample? { library.sample(library.session.pads[library.key(pad)]) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(String(format: "%02d", pad)).font(.system(size: 11, weight: .semibold, design: .monospaced)); Spacer(); Circle().fill(sample.map { categoryColor($0.category) } ?? Color.white.opacity(0.1)).frame(width: 5, height: 5) }.foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let sample {
                Text(sample.name).font(.system(size: 12, weight: .medium)).lineLimit(2)
                HStack {
                    Text(sample.category.uppercased()).font(.system(size: 8, design: .monospaced)).foregroundStyle(categoryColor(sample.category))
                    Spacer(minLength: 0)
                    Menu { ForEach(["Stereo", "Mono"], id: \.self) { mode in Button { library.setMode(mode, key: library.key(pad)) } label: { if library.mode(library.key(pad)) == mode { Label(mode, systemImage: "checkmark") } else { Text(mode) } } } } label: { Text(library.mode(library.key(pad))).font(.system(size: 9, weight: .medium)) }.menuStyle(.borderlessButton).fixedSize().help("Choose the exported channel format for this pad")
                }
            } else { Text(library.connectedCard?.contains(library.key(pad)) == true ? "On card · kept" : "+ Drop sound").font(.system(size: 11)).foregroundStyle(.tertiary); Spacer(minLength: 0) }
        }.padding(12).frame(maxWidth: .infinity).frame(height: 76)
        .background(targeted ? accent.opacity(0.18) : sample == nil ? Color.white.opacity(0.025) : surface)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(targeted || (sample != nil && library.playing == sample?.id) ? accent : Color.white.opacity(sample == nil ? 0.06 : 0.15), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { if let sample { library.preview(sample) } }
        .onDrop(of: [UTType.plainText, UTType.fileURL], isTargeted: $targeted) { library.receive($0, target: library.key(pad)) }
        .contextMenu {
            if let id = library.selected { Button("Assign selected sound") { library.assign(id, to: library.key(pad)) } }
            if let sample { Button("Preview") { library.preview(sample) }; Button("Clear pad", role: .destructive) { library.clear(pad) } }
        }
        .accessibilityLabel("Bank \(library.bank), pad \(pad), \(sample?.name ?? "empty")")
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
@main struct PadShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var library = Library()
    @StateObject var updater = AppUpdater()
    var body: some Scene {
        WindowGroup("PadShelf") { ContentView().environmentObject(library).sheet(isPresented: $updater.presented) { UpdateView(updater: updater) } }.defaultSize(width: 1120, height: 860)
        .commands { CommandGroup(after: .appInfo) { Button("Check for Updates…") { updater.check() }.disabled(library.busy || updater.working) }; CommandGroup(replacing: .newItem) { Button("Import sounds…") { library.chooseImport() }.keyboardShortcut("i"); Button("Export WAV kit…") { library.export() }.keyboardShortcut("e").disabled(library.session.pads.isEmpty || library.busy) }; CommandGroup(after: .pasteboard) { Button("Stop preview") { library.stop() }.keyboardShortcut(".") } }
    }
}
