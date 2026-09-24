<p align="center">
  <img src="Assets/AppIcon.png" width="160" alt="PadShelf app icon">
</p>

# PadShelf

A native macOS sample organizer and pad arranger for the **Roland SP-404SX**. Import a sample pack, sort sounds by type, drag them onto pads, and write a sampler-ready SD card.

Built with Swift, SwiftUI, AppKit and AVFoundation. Runs on **macOS 13 or later**, on Apple silicon and Intel Macs. No third-party runtime dependencies or account required.

## Features

- **Batch import:** select multiple files or drop whole folders into the library.
- **Sound categories:** kick, snare, clap, rimshot, generic/open/closed hi-hat, crash, ride, splash, china, cymbal, bell, cowbell, tom, shaker, tambourine, conga, bongo, percussion, breaks, bass, melodic, vocal, FX and unsorted. Suggestions use filename tokens and folder hints and remain editable.
- **Bulk category editing:** select sounds, then use Set selected sound type to change them together. Each bulk change is one undoable manual edit.
- **Undo/redo:** reverse imports, removals, category changes, pad assignments, channel settings and kit edits with the arrow buttons or Command-Z / Shift-Command-Z. The last 100 edits are available during the current app session; a new edit clears redo. Undo does not reverse SD-card writes or exported files.
- **Saved kits:** save named arrangements of all ten banks and their stereo/mono settings. Load, update, delete or start an empty kit from Saved kits. Changes are marked Modified until you update the kit. The library is shared; kits retain references to managed sounds, and loading restores sounds removed from the library. Switching kits is undoable.
- **Multi-selection:** use checkboxes, Command-click, Shift-click ranges, or Select all. Drag a selected row to place the group in list order into empty pads from the drop position through pad 12 of that bank. Occupied pads (including known card sounds) are preserved; excess samples are skipped and remain in the library. A single-sound drag can still replace a pad.
- **Pad arrangement:** ten banks, A–J, with twelve pads each. Drag sounds onto pads or use the assignment context menu.
- **Audio preview:** audition samples from the library or assigned pads.
- **Stereo/Mono:** choose per pad or apply to every assigned pad in a bank.
- **Direct SD-card writing:** automatic card detection, Roland sample headers, hardware filenames and pad metadata.
- **Backups and verification:** local backups before replacement, verified writes, and rollback on recoverable write failures.
- **WAV kit export:** bank folders with 44.1 kHz / 16-bit PCM WAV files and a CSV pad map.
- **Flexible layout:** the footer wraps long messages, while pad and category panels scroll in shorter windows.
- **List sorting:** natural filename order, sound type, shortest first or longest first.
- **Local storage:** managed audio copies and automatically saved assignments.

## Install and update

[Download the latest release](https://github.com/VictorBischoff/PadShelf/releases/latest).

In the app, choose **PadShelf → Check for Updates…**. If a newer stable release exists, click **Download update**. PadShelf downloads the installer from this repository, verifies its size and GitHub SHA-256 checksum, and opens it. Quit the old app, drag the new app into Applications and choose Replace. Your local sample library and settings remain in Application Support.

Update checks run only when requested. They do not interrupt imports or SD-card writes. Downloads that fail verification are not opened. GitHub outages, request limits and missing releases are reported in the update window. This is an installer-assisted update; the app does not silently replace itself.

## Get started

Open the disk image and drag `PadShelf.app` to Applications, or open the app directly from the ZIP. The packaged app is locally signed; it is not an Apple-notarized release.

1. Click **Import sounds**, select multiple audio files or a folder, or drop files onto the sound list.
2. Filter by type or search by filename. Right-click a sound to change its category.
3. Click a play button to preview. Drag sounds to pads in banks A–J. Dragging onto an occupied pad replaces that local assignment.
4. Choose **Stereo** or **Mono** on each pad, or use **Bank Output** to update all currently assigned pads in that bank. Individual overrides remain available. **Mixed** means a bank contains both formats.
5. Insert an SD card formatted by the SP-404SX. The app detects it automatically. Select the destination if multiple cards are connected.
6. Click **Write SD card**, review the pad list, and confirm. Wait for verification, then click **Eject**. Insert the card into the powered-off sampler and turn it on.

Files written by **Write SD card** are assigned directly; a separate hardware WAV-import step is not required.

### Smarter categories and sorting

The classifier recognizes complete words, common abbreviations (`BD`, `SD`, `OH`, `CH`, `CYM`), plurals, camel case and names joined to numbers. Specific sounds outrank generic hints: `808_kick` is Kick, `RideBell` is Ride, and `CowBell` is Cowbell. `Bells`, `Openhat`, `Tamb` and `Tambhat` are recognized. Breaks recognizes names such as `Amen_Break`, `DrumBreak`, `breakbeat` and `BRK`, plus Breaks folder hints. Explicit single-hit names such as `kick_from_break` stay in their instrument category. It does not inspect audio content.

When a filename has no clear instrument, up to three parent-folder names are used as hints, nearest folder first. Folder hints are captured on new imports. Explicit filename instruments always win over folder labels.

Use **Sort** above the sound list to order by Name, Sound type, Shortest first or Longest first. Use **Re-sort → Unsorted & automatic categories** to apply the improved classifier to existing sounds without changing recorded manual choices. Older library entries did not track whether categories were manual, so their existing non-Unsorted categories are preserved by this option. To reclassify those too, choose **All sounds, including manual…** and review the confirmation.

**Undo last re-sort** restores previous categories during the current session, while preserving individual manual edits made afterward. Pad assignments and channel settings are unaffected. Right-click category changes are marked as manual.

### Audio formats and preview

Inputs: WAV, AIFF, MP3, M4A, AAC, CAF and FLAC where macOS can decode them. Only nonempty mono and stereo files are supported.

Output: 44.1 kHz, signed 16-bit PCM WAV. Mono downmixes stereo sources; Stereo duplicates a mono source into two channels. **Preview plays the original source**, so export channel settings do not change the preview.

### Existing card sounds

Pads without a local assignment display **On card · kept** when occupied on the connected card. These sounds and their metadata remain unchanged. Patterns are preserved. Clearing a local pad does not erase its existing card sound.

This version does not load existing card audio into the editable library and does not format cards. Format new cards in the SP-404SX. Blank or invalid cards are not offered as write destinations; write-protected cards report an error.

### Generic WAV export

**Export WAV kit** creates a new folder containing bank folders, converted WAVs, `Pad Map.csv` and import instructions. Empty pads are omitted. This route does not write card metadata; use **Write SD card** for direct sampler use.

## Library storage and recovery

The app stores data in:

```text
~/Library/Application Support/PadShelf/
├── Audio/          # Managed copies of imported samples
├── Library.json    # Sample categories, pad assignments and channel settings
└── Card backups/   # Originals, manifests and recovery instructions
```

Original audio files are never edited. Removing a library entry clears its pad assignments but leaves its managed audio copy on disk. Reimporting a file in a later batch creates another entry.

Before replacing card data, PadShelf backs up affected files locally. **Show backup** reveals the latest successful backup. Every backup contains `Manifest.json` and `Recovery.txt`.

Conversion and staging finish before live samples are replaced. The writer checks for card changes, verifies file contents and attempts rollback on failure. Card removal or power loss during replacement can require manual recovery. Keep the card connected while writing and use **Eject** afterward.

## Build from source

Requirements: macOS with Xcode or Swift developer tools supporting Swift 5.9 or newer, plus Apple's bundled `sips`, `iconutil`, `afconvert` and `codesign` tools.

```sh
./build.sh
```

This generates the app icon sizes, builds a universal binary for Apple silicon and Intel, and creates `../PadShelf.app` with a local signature.

To create a disk image with an Applications shortcut:

```sh
./scripts/package-dmg.sh
```

This creates `../PadShelf-macOS.dmg`.

For development:

```sh
swift run PadShelf
```

For the full app icon and bundle behavior, use `./build.sh` and open the resulting app bundle.

## Fetch source updates

For a local source checkout with Git and Apple's developer tools installed:

```sh
./scripts/update.sh
```

The script requires a clean `main` branch, fetches `origin/main`, merges only when it can fast-forward, runs tests and builds a new installer. It never discards local changes or forces a merge.

## Publish a release

The GitHub repository is [VictorBischoff/PadShelf](https://github.com/VictorBischoff/PadShelf). Release creation requires the GitHub CLI signed in with repository write access.

1. Change `VERSION` to a new stable version such as `1.4.1`, and commit your changes on `main`.
2. Run `./scripts/release.sh`.

The script fetches the latest source, runs tests, builds and verifies the universal app and disk image, pushes `main` and an annotated `vVERSION` tag, and creates a GitHub release with `PadShelf-macOS.dmg` and `PadShelf-macOS.zip`. GitHub supplies the digest used by the in-app checker. Published stable releases become available through **Check for Updates**. Keep those asset names unchanged.

If a release upload is interrupted after pushing its tag, use `gh release create` or the GitHub release page to finish publishing that existing tag. The script deliberately refuses to replace an existing local tag.

## Tests

```sh
swift test
```

Twenty-four automated tests cover batch import, category changes, managed copies, persistence, per-pad and bank-wide channel settings, direct card writing on temporary replicas, header validation, preservation of other pads, rollback, concurrent card changes and malformed input. Update-specific tests check version ordering, release-origin restrictions and checksum failure handling. Classifier tests cover sample-pack names, false-positive prevention, folder fallback, re-sort undo and list ordering. A footer layout test checks that long status text grows vertically at narrow widths. The optional twenty-fifth test skips unless a card path is provided:

```sh
PADSHELF_TEST_CARD='/Volumes/SP-404SX' swift test --filter CardTests.testMountedCardReadOnlyWhenProvided
```

That optional test only reads the selected card. All write and rollback tests use disposable temporary directories.

The app's card detection and controls have been visually checked, and the user has reported that the SD-card workflow works. Automated format/recovery tests pass; the developer has not independently verified sampler playback.

## Project structure

```text
Assets/                         App icon source, macOS icon and generation notes
Sources/PadShelf/
  PadShelf.swift                App interface, sample library and WAV export
  CardConnection.swift          Card detection, write review and eject controls
  CardWriter.swift              Roland file encoding, backup, write and rollback
  AppUpdater.swift              GitHub release checks and verified installer downloads
  SoundClassifier.swift         Instrument vocabulary and list sorting
  StatusFooter.swift            Adaptive status footer
Tests/PadShelfTests/             Library and card-writer tests
scripts/build-icon.sh           macOS icon packaging
scripts/package-dmg.sh          Installable disk image packaging
scripts/update.sh               Fetch source and rebuild
scripts/release.sh              Test, build and publish a GitHub release
VERSION                         Release version used in the app bundle
build.sh                        Universal app build and local signing
Package.swift                   Swift package definition
```

## App artwork

[AppIcon.png](Assets/AppIcon.png) is the master app image. [PadShelf.icns](Assets/PadShelf.icns) is the macOS icon used in the application bundle. The generation method and exact prompt are documented in [Assets/README.md](Assets/README.md).

## Format references

- [Roland sample filenames and card layout](https://support.roland.com/hc/en-us/articles/201977469-SP-404SX-Exporting-Samples)
- [SP-404SX sample-format research](https://gist.github.com/threedaymonk/701ca30e5d363caa288986ad972ab3e0)
- [Wave Converter 1.01 Roland-header details](https://github.com/uttori/uttori-audio-wave)
- [Super Pads card-writer reference](https://github.com/MatthewCallis/super-pads)

PadShelf is an independent project and is not affiliated with Roland.
