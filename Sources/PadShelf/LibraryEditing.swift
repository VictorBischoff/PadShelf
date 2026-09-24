import SwiftUI

struct SavedKit: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var pads: [String: UUID]
    var modes: [String: String]
    var samples: [Sample]
}
struct EditSnapshot {
    var session: Session
    var classificationUndo: [UUID: Sample]
}
struct HistoryEntry {
    var name: String
    var snapshot: EditSnapshot
}

extension Library {
    var textEditor: NSTextView? { (NSApp.keyWindow?.firstResponder as? NSTextView).flatMap { $0.isEditable ? $0 : nil } }
    func undoCommand() { if let editor = textEditor { editor.undoManager?.undo() } else { undoEdit() } }
    func redoCommand() { if let editor = textEditor { editor.undoManager?.redo() } else { redoEdit() } }
    var snapshot: EditSnapshot { EditSnapshot(session: session, classificationUndo: classificationUndo) }
    var canUndo: Bool { !busy && writable && !undoHistory.isEmpty }
    var canRedo: Bool { !busy && writable && !redoHistory.isEmpty }
    func recordEdit(_ before: EditSnapshot, _ name: String) {
        guard before.session != session else { return }
        undoHistory.append(HistoryEntry(name: name, snapshot: before))
        if undoHistory.count > 100 { undoHistory.removeFirst() }
        redoHistory = []
    }
    func restore(_ snapshot: EditSnapshot) {
        stop()
        session = snapshot.session
        classificationUndo = snapshot.classificationUndo
        selection = selection.intersection(Set(session.samples.map(\.id)))
        if sample(selected) == nil { selected = nil }
        save()
    }
    func undoEdit() {
        guard canUndo, let entry = undoHistory.popLast() else { return }
        redoHistory.append(HistoryEntry(name: entry.name, snapshot: snapshot))
        restore(entry.snapshot); status = "Undid \(entry.name.lowercased())."
    }
    func redoEdit() {
        guard canRedo, let entry = redoHistory.popLast() else { return }
        undoHistory.append(HistoryEntry(name: entry.name, snapshot: snapshot))
        restore(entry.snapshot); status = "Redid \(entry.name.lowercased())."
    }
    func recategorize(_ ids: [UUID], as category: String) {
        guard !busy, writable, categories.contains(category) else { return }
        let before = snapshot
        let ids = Set(ids)
        var count = 0
        for i in session.samples.indices where ids.contains(session.samples[i].id) {
            session.samples[i].category = category
            session.samples[i].categoryIsManual = true
            classificationUndo.removeValue(forKey: session.samples[i].id)
            count += 1
        }
        recordEdit(before, "Change sound type"); save()
        status = "Set \(count) sounds to \(category)."
    }
    var savedKits: [SavedKit] { session.kits ?? [] }
    var activeKit: SavedKit? { savedKits.first { $0.id == session.activeKitID } }
    var kitChanged: Bool {
        guard let kit = activeKit else { return false }
        return kit.pads != session.pads || kit.modes != (session.modes ?? [:])
    }
    func kitSnapshot(name: String, id: UUID = UUID()) -> SavedKit {
        let ids = Set(session.pads.values)
        return SavedKit(id: id, name: name, pads: session.pads, modes: session.modes ?? [:], samples: session.samples.filter { ids.contains($0.id) })
    }
    func saveKit(named name: String) {
        guard !busy, writable else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard !savedKits.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            error = "A kit named ‘\(name)’ already exists. Choose another name or use Update current kit."; return
        }
        let before = snapshot
        let kit = kitSnapshot(name: name)
        session.kits = savedKits + [kit]; session.activeKitID = kit.id
        recordEdit(before, "Save kit"); save(); status = "Saved kit ‘\(name)’."
    }
    func updateKit() {
        guard !busy, writable, let kit = activeKit, let index = session.kits?.firstIndex(where: { $0.id == kit.id }) else { return }
        let before = snapshot
        session.kits?[index] = kitSnapshot(name: kit.name, id: kit.id)
        recordEdit(before, "Update kit"); save(); status = "Updated kit ‘\(kit.name)’."
    }
    func loadKit(_ id: UUID) {
        guard !busy, writable, let kit = savedKits.first(where: { $0.id == id }) else { return }
        let before = snapshot
        let existing = Set(session.samples.map(\.id))
        session.samples += kit.samples.filter { !existing.contains($0.id) }
        session.pads = kit.pads; session.modes = kit.modes; session.activeKitID = id
        recordEdit(before, "Load kit"); save(); status = "Loaded ‘\(kit.name)’. Undo returns to your previous arrangement."
    }
    func deleteKit(_ id: UUID) {
        guard !busy, writable else { return }
        let before = snapshot
        session.kits = savedKits.filter { $0.id != id }
        if session.activeKitID == id { session.activeKitID = nil }
        recordEdit(before, "Delete kit"); save()
    }
    func newKit() {
        guard !busy, writable else { return }
        let before = snapshot
        session.pads = [:]; session.modes = [:]; session.activeKitID = nil
        recordEdit(before, "New kit"); save(); status = "Started an empty kit. Undo restores your previous arrangement."
    }
}

struct KitPanel: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    var duplicateName: Bool { library.savedKits.contains { $0.name.localizedCaseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Saved kits").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            Text("Kits save all ten banks and stereo/mono settings. Your sound library is shared. Loading a kit is undoable.").foregroundStyle(.secondary)
            HStack {
                TextField("New kit name", text: $name).textFieldStyle(.roundedBorder)
                Button("Save as new kit") { library.saveKit(named: name); name = "" }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || duplicateName)
            }
            if duplicateName { Text("That name is already used. Choose another name or update the current kit.").font(.caption).foregroundStyle(.orange) }
            if let kit = library.activeKit {
                HStack {
                    Text("Current: \(kit.name)\(library.kitChanged ? " · Modified" : "")").lineLimit(1)
                    Spacer()
                    Button("Update current kit") { library.updateKit() }
                }
            }
            List(library.savedKits) { kit in
                HStack {
                    VStack(alignment: .leading) { Text(kit.name); Text("\(kit.pads.count) assigned pads").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Load") { library.loadKit(kit.id); dismiss() }
                    Button("Delete", role: .destructive) { library.deleteKit(kit.id) }
                }
            }.frame(minHeight: 120, maxHeight: .infinity)
            HStack { Button("Start empty kit") { library.newKit(); dismiss() }; Spacer(); Text("Kit edits can be undone.").font(.caption).foregroundStyle(.secondary) }
        }.padding(24).frame(width: 560, height: 480).disabled(library.busy || !library.writable)
    }
}
