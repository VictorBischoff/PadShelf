import AppKit

extension Library {
    var selectedSamples: [Sample] { visible.filter { selection.contains($0.id) } }

    func select(_ id: UUID, extending: Bool = false, range: Bool = false) {
        let ids = visible.map(\.id)
        guard let end = ids.firstIndex(of: id) else { return }
        if range, let anchor = selected, let start = ids.firstIndex(of: anchor) {
            let rangeIDs = Set(ids[min(start, end)...max(start, end)])
            selection = extending ? selection.union(rangeIDs) : rangeIDs
        } else {
            if extending {
                if !selection.insert(id).inserted { selection.remove(id) }
            } else { selection = [id] }
            selected = id
        }
    }

    func dragText(for id: UUID) -> String {
        if !selection.contains(id) { select(id) }
        let ids = selectedSamples.map(\.id)
        // One payload preserves visible list order across asynchronous drag loading.
        return ids.count == 1 ? ids[0].uuidString : "padshelf-samples:" + ids.map(\.uuidString).joined(separator: ",")
    }

    func receiveSampleText(_ text: String, target: String) {
        if let id = UUID(uuidString: text) { assign(id, to: target); return }
        let prefix = "padshelf-samples:"
        guard text.hasPrefix(prefix) else { return }
        let components = text.dropFirst(prefix.count).split(separator: ",")
        let ids = components.compactMap { UUID(uuidString: String($0)) }
        guard ids.count == components.count, !ids.isEmpty else { return }
        assignGroup(ids, startingAt: target)
    }

    @discardableResult func assignGroup(_ ids: [UUID], startingAt target: String, restoringSelectionOnUndo: Bool = false) -> [UUID] {
        let parts = target.split(separator: "-")
        guard !busy, writable, parts.count == 2, banks.contains(String(parts[0])),
              let start = Int(parts[1]), (1...12).contains(start) else { return [] }
        guard !ids.isEmpty else { return [] }
        let bank = String(parts[0])
        var seen = Set<UUID>()
        let sounds = ids.filter { sample($0) != nil && seen.insert($0).inserted }
        let empty = (start...12).map { "\(bank)-\($0)" }.filter {
            session.pads[$0] == nil && connectedCard?.contains($0) != true
        }
        let before = restoringSelectionOnUndo ? snapshotIncludingSelection : snapshot
        let assignments = Array(zip(sounds, empty))
        for (id, key) in assignments { session.pads[key] = id }
        recordEdit(before, "Assign selected sounds")
        if !assignments.isEmpty { save() }
        let skipped = sounds.count - assignments.count
        status = "Assigned \(assignments.count) sounds to bank \(bank)." +
            (skipped > 0 ? " Skipped \(skipped): no remaining empty pads. Skipped sounds stay in your library." : "")
        return assignments.map { $0.0 }
    }
}
