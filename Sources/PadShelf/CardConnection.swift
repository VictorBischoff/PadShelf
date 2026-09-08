import AppKit
import Foundation

extension Library {
    var connectedCard: SXCard? { cards.first { $0.id == cardID } }
    func startCardMonitoring() {
        refreshCards()
        cardTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshCards() }
        }
    }
    func refreshCards() {
        guard !scanningCards, !busy else { return }
        scanningCards = true
        Task {
            let found = await Task.detached(priority: .utility) {
                let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: [.skipHiddenVolumes]) ?? []
                return volumes.compactMap { try? SXCard.read($0) }.sorted { $0.root.path < $1.root.path }
            }.value
            cards = found
            if !found.contains(where: { $0.id == cardID }) { cardID = found.count == 1 ? found[0].id : "" }
            scanningCards = false
        }
    }
    func writeCard() {
        guard !busy, let card = connectedCard else { return }
        let assignments = session.pads.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }.compactMap { key, id -> CardAssignment? in
            guard let sample = sample(id) else { return nil }
            return CardAssignment(key: key, source: url(sample), mono: mode(key) == "Mono")
        }
        guard !assignments.isEmpty else { return }
        let overwrite = assignments.filter { card.contains($0.key) }.count
        let alert = NSAlert()
        alert.messageText = "Write \(assignments.count) pads to \(card.name)?"
        alert.informativeText = "Pads: \(assignments.map(\.key).joined(separator: ", "))\n\n\(overwrite) existing card pads will be replaced. Pads without a local assignment stay as they are on the card. Stereo/Mono settings will be applied. A backup of affected files is saved on your Mac first.\n\nKeep the card connected until writing finishes."
        alert.addButton(withTitle: "Write SD card"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let backups = root.appendingPathComponent("Card backups", isDirectory: true)
        busy = true; stop(); status = "Preparing audio and backing up card files…"
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { try CardWriter.write(card: card, assignments: assignments, backupRoot: backups) }.value
                lastCardBackup = result.backup
                status = "Wrote and verified \(result.count) pads. Eject the card before moving it to the sampler."
            } catch { self.error = error.localizedDescription; status = "Card write did not complete. See the error for recovery details." }
            busy = false; refreshCards()
        }
    }
    func ejectCard() {
        guard !busy, let card = connectedCard else { return }
        stop(); busy = true; status = "Ejecting \(card.name)…"
        Task {
            do {
                try await Task.detached(priority: .userInitiated) { try NSWorkspace.shared.unmountAndEjectDevice(at: card.root) }.value
                status = "Card ejected. Insert it into the powered-off SP-404SX, then turn it on."
            } catch { self.error = "Could not eject the card: \(error.localizedDescription)" }
            busy = false; refreshCards()
        }
    }
}
