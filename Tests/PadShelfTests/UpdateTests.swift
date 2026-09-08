import XCTest
import CryptoKit
@testable import PadShelf
final class UpdateTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertLessThan(ReleaseVersion("1.9.0")!, ReleaseVersion("v1.10.0")!)
        XCTAssertEqual(ReleaseVersion("1.4"), ReleaseVersion("v1.4.0"))
        XCTAssertLessThan(ReleaseVersion("1.99.99")!, ReleaseVersion("2.0.0")!)
        for invalid in ["", "1..2", "1.4.0-beta", "vnext", "1.2.3.4", "-1.2.0"] { XCTAssertNil(ReleaseVersion(invalid)) }
    }
    func release(url: String = "https://github.com/VictorBischoff/PadShelf/releases/download/v1.4.0/PadShelf-macOS.dmg", digest: String? = nil, prerelease: Bool = false) -> GitHubRelease {
        let data = Data("installer fixture".utf8)
        let expected = "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return GitHubRelease(tag_name: "v1.4.0", body: nil, draft: false, prerelease: prerelease, assets: [.init(name: "PadShelf-macOS.dmg", browser_download_url: URL(string: url)!, digest: digest ?? expected, size: data.count)])
    }
    func testRejectsUntrustedAssetsAndPrereleases() {
        for url in ["http://github.com/VictorBischoff/PadShelf/releases/download/v1.4.0/PadShelf-macOS.dmg", "https://example.com/PadShelf-macOS.dmg", "https://github.com/other/PadShelf/releases/download/v1.4.0/PadShelf-macOS.dmg"] {
            XCTAssertThrowsError(try release(url: url).installer(repository: AppUpdater.repository))
        }
        XCTAssertThrowsError(try release(digest: "sha256:invalid").installer(repository: AppUpdater.repository))
        XCTAssertThrowsError(try release(prerelease: true).installer(repository: AppUpdater.repository))
    }
    func testChecksumAndSizeVerification() throws {
        let asset = try release().installer(repository: AppUpdater.repository)
        XCTAssertNoThrow(try GitHubRelease.verify(Data("installer fixture".utf8), asset: asset))
        XCTAssertThrowsError(try GitHubRelease.verify(Data("tampered! fixture".utf8), asset: asset))
        XCTAssertThrowsError(try GitHubRelease.verify(Data(), asset: asset))
    }
}
