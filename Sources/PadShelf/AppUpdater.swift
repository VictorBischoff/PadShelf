import SwiftUI
import AppKit
import CryptoKit

struct ReleaseVersion: Comparable, Equatable {
    let parts: [Int]
    init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(pieces.count), pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }), pieces.allSatisfy({ Int($0) != nil }) else { return nil }
        parts = pieces.map { Int($0)! } + (pieces.count == 2 ? [0] : [])
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}
struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let digest: String?
        let size: Int
    }
    let tag_name: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    func installer(repository: String) throws -> Asset {
        guard !draft, !prerelease, ReleaseVersion(tag_name) != nil,
              let asset = assets.first(where: { $0.name == "PadShelf-macOS.dmg" }),
              asset.browser_download_url.scheme == "https",
              asset.browser_download_url.host == "github.com",
              asset.browser_download_url.user == nil,
              asset.browser_download_url.password == nil,
              asset.browser_download_url.port == nil,
              asset.browser_download_url.path == "/\(repository)/releases/download/\(tag_name)/PadShelf-macOS.dmg",
              asset.size > 0, asset.size < 500_000_000 else {
            throw AppFailure(message: "This release does not contain a supported PadShelf installer.")
        }
        guard let digest = asset.digest, digest.hasPrefix("sha256:"), digest.count == 71,
              digest.dropFirst(7).allSatisfy({ $0.isHexDigit && $0.isASCII }) else {
            throw AppFailure(message: "GitHub has not supplied a checksum for this installer yet. Try again later or view the release on GitHub.")
        }
        return asset
    }
    static func verify(_ data: Data, asset: Asset) throws {
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.count == asset.size, "sha256:" + checksum == asset.digest?.lowercased() else {
            throw AppFailure(message: "The downloaded installer failed verification. It has not been opened. Please try again.")
        }
    }
}

@MainActor final class AppUpdater: ObservableObject {
    nonisolated static let repository = "VictorBischoff/PadShelf"
    nonisolated static let releasesURL = URL(string: "https://github.com/\(repository)/releases")!
    @Published var presented = false
    @Published var working = false
    @Published var message = "Check GitHub for the latest PadShelf release."
    @Published var release: GitHubRelease?
    @Published var installerURL: URL?
    var installedVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }
    func check() {
        presented = true
        guard !working else { return }
        working = true; release = nil; installerURL = nil; message = "Checking GitHub…"
        Task {
            defer { working = false }
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
                request.setValue("PadShelf/\(installedVersion)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw AppFailure(message: "GitHub returned an unexpected response.") }
                if http.statusCode == 404 { throw AppFailure(message: "No published release is available yet.") }
                if http.statusCode == 403 || http.statusCode == 429 { throw AppFailure(message: "GitHub's request limit was reached. Try again later.") }
                guard http.statusCode == 200 else { throw AppFailure(message: "GitHub could not check for updates (HTTP \(http.statusCode)).") }
                let candidate = try JSONDecoder().decode(GitHubRelease.self, from: data)
                guard !candidate.draft, !candidate.prerelease, let remote = ReleaseVersion(candidate.tag_name), let local = ReleaseVersion(installedVersion) else { throw AppFailure(message: "Could not compare the release versions.") }
                if remote > local {
                    _ = try candidate.installer(repository: Self.repository)
                    release = candidate; message = "PadShelf \(candidate.tag_name) is available. You have \(installedVersion)."
                } else { message = "You're up to date. PadShelf \(installedVersion) is installed." }
            } catch { message = error.localizedDescription }
        }
    }
    func download() {
        guard !working, let release else { return }
        working = true; message = "Downloading and verifying the update…"
        Task {
            defer { working = false }
            do {
                let asset = try release.installer(repository: Self.repository)
                let (temporary, response) = try await URLSession.shared.download(for: URLRequest(url: asset.browser_download_url, timeoutInterval: 120))
                defer { try? FileManager.default.removeItem(at: temporary) }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AppFailure(message: "The installer could not be downloaded. Please try again.") }
                try GitHubRelease.verify(Data(contentsOf: temporary, options: .mappedIfSafe), asset: asset)
                let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                let destination = folder.appendingPathComponent("PadShelf-\(release.tag_name)-\(UUID().uuidString.prefix(6)).dmg")
                try FileManager.default.moveItem(at: temporary, to: destination)
                installerURL = destination
                message = "Download verified. Quit PadShelf, then drag the new app into Applications and choose Replace. Your library and pad assignments are kept."
                NSWorkspace.shared.activateFileViewerSelecting([destination])
                if !NSWorkspace.shared.open(destination) { message = "Download verified. Open the installer in Downloads, quit PadShelf, then replace the app in Applications." }
            } catch { message = error.localizedDescription }
        }
    }
}

struct UpdateView: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "arrow.down.circle").font(.largeTitle).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("PadShelf updates").font(.title2.bold())
                    Text("GitHub · \(AppUpdater.repository)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(updater.message).fixedSize(horizontal: false, vertical: true)
            if updater.working { ProgressView().controlSize(.small) }
            if let notes = updater.release?.body, !notes.isEmpty {
                ScrollView { Text(notes).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.frame(maxHeight: 130)
            }
            HStack {
                Link("View releases", destination: AppUpdater.releasesURL)
                Spacer()
                Button("Close") { updater.presented = false }.disabled(updater.working)
                if updater.release != nil && updater.installerURL == nil {
                    Button("Download update") { updater.download() }.buttonStyle(.borderedProminent).tint(accent).disabled(updater.working)
                } else if !updater.working && updater.installerURL == nil {
                    Button("Check again") { updater.check() }
                }
            }
        }.padding(24).frame(width: 460).preferredColorScheme(.dark).interactiveDismissDisabled(updater.working)
    }
}
