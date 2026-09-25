import SwiftUI

enum BankAction: String, CaseIterable, Identifiable {
    case copy = "Copy", move = "Move", swap = "Swap", clear = "Clear"
    var id: String { rawValue }
}

extension Library {
    func assignedCount(_ bank: String) -> Int { (1...12).filter { session.pads["\(bank)-\($0)"] != nil }.count }
    func emptyPadCount(_ bank: String) -> Int {
        (1...12).filter { session.pads["\(bank)-\($0)"] == nil && connectedCard?.contains("\(bank)-\($0)") != true }.count
    }
    func fillSelected() {
        let placed = assignGroup(selectedSamples.map(\.id), startingAt: "\(bank)-1", restoringSelectionOnUndo: true)
        selection.subtract(placed)
        if let selected, placed.contains(selected) { self.selected = nil }
    }
    @discardableResult func changeBank(_ action: BankAction, source: String, destination: String) -> Bool {
        guard !busy, writable, banks.contains(source),
              action == .clear || (banks.contains(destination) && source != destination),
              action == .swap || assignedCount(source) > 0 else { return false }
        let before = snapshot
        let originalPads = session.pads
        let originalModes = session.modes ?? [:]
        func replace(_ target: String, with origin: String?) {
            for pad in 1...12 {
                let key = "\(target)-\(pad)"
                session.pads.removeValue(forKey: key)
                session.modes?.removeValue(forKey: key)
                if let origin, let id = originalPads["\(origin)-\(pad)"] {
                    session.pads[key] = id
                    if let mode = originalModes["\(origin)-\(pad)"] {
                        if session.modes == nil { session.modes = [:] }
                        session.modes?[key] = mode
                    }
                }
            }
        }
        switch action {
        case .copy: replace(destination, with: source)
        case .move: replace(destination, with: source); replace(source, with: nil)
        case .swap: replace(destination, with: source); replace(source, with: destination)
        case .clear: replace(source, with: nil)
        }
        recordEdit(before, "\(action.rawValue) bank")
        save()
        status = action == .clear ? "Cleared bank \(source) assignments. Sounds stay in your library." : "\(action.rawValue) completed: bank \(source) → \(destination)."
        return true
    }
}

struct BankActionPanel: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) var dismiss
    let source: String
    @State private var action: BankAction = .copy
    @State private var destination: String
    init(source: String) {
        self.source = source
        _destination = State(initialValue: banks.first { $0 != source } ?? "B")
    }
    var summary: String {
        let count = library.assignedCount(source)
        let other = library.assignedCount(destination)
        switch action {
        case .copy: return "Copy \(count) assignments from bank \(source) to \(destination), replacing its \(other) assignments. Bank \(source) stays as it is."
        case .move: return "Move \(count) assignments from bank \(source) to \(destination), replacing its \(other) assignments and clearing bank \(source)."
        case .swap: return "Exchange bank \(source)’s \(count) assignments with bank \(destination)’s \(other) assignments."
        case .clear: return "Remove all \(count) assignments from bank \(source). The sounds stay in your library."
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Bank \(source) actions").font(.title2.bold())
            Picker("Action", selection: $action) { ForEach(BankAction.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            if action != .clear {
                Picker("Destination", selection: $destination) {
                    ForEach(banks.filter { $0 != source }, id: \.self) { bank in
                        Text("Bank \(bank) · \(library.assignedCount(bank)) assigned pads").tag(bank)
                    }
                }
            }
            Text(summary).fixedSize(horizontal: false, vertical: true)
            Text("Pad positions and stereo/mono settings travel together. This changes your kit’s assignments only; sounds already on the SD card are not copied or erased. You can undo this action.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(action == .clear ? "Clear bank \(source)" : "\(action.rawValue) \(source) → \(destination)") {
                    if library.changeBank(action, source: source, destination: destination) { dismiss() }
                }.disabled(library.busy || !library.writable || (action != .swap && library.assignedCount(source) == 0) || (action == .swap && library.assignedCount(source) + library.assignedCount(destination) == 0))
            }
        }.padding(24).frame(width: 450)
    }
}
