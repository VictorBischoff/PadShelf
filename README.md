<p align="center">
  <img src="Assets/AppIcon.png" width="160" alt="PadShelf app icon">
</p>

# PadShelf

A native macOS sample organizer and pad arranger for the **Roland SP-404SX**. Import a sample pack, sort sounds by type, drag them onto pads, and write a sampler-ready SD card.

Built with Swift, SwiftUI, AppKit and AVFoundation. Runs on **macOS 13 or later**, on Apple silicon and Intel Macs. No third-party runtime dependencies or account required.

## Features

- **Batch import:** select multiple files or drop whole folders into the library.
- **Sound categories:** kick, snare, hi-hat, percussion, bass, melodic, vocal, FX and unsorted; suggestions come from filenames and are editable.
- **Pad arrangement:** ten banks, A–J, with twelve pads each. Drag sounds onto pads or use the assignment context menu.
- **Audio preview:** audition samples from the library or assigned pads.
- **Stereo/Mono:** choose per pad or apply to every assigned pad in a bank.
- **Direct SD-card writing:** automatic card detection, Roland sample headers, hardware filenames and pad metadata.
- **Backups and verification:** local backups before replacement, verified writes, and rollback on recoverable write failures.
- **WAV kit export:** bank folders with 44.1 kHz / 16-bit PCM WAV files and a CSV pad map.
- **Local storage:** managed audio copies and automatically saved assignments.

## Get started

Open the disk image and drag `PadShelf.app` to Applications, or open the app directly from the ZIP. The packaged app is locally signed; it is not an Apple-notarized release.

1. Click **Import sounds**, select multiple audio files or a folder, or drop files onto the sound list.
2. Filter by type or search by filename. Right-click a sound to change its category.
3. Click a play button to preview. Drag sounds to pads in banks A–J. Dragging onto an occupied pad replaces that local assignment.
4. Choose **Stereo** or **Mono** on each pad, or use **Bank Output** to update all currently assigned pads in that bank. Individual overrides remain available. **Mixed** means a bank contains both formats.
5. Insert an SD card formatted by the SP-404SX. The app detects it automatically. Select the destination if multiple cards are connected.
6. Click **Write SD card**, review the pad list, and confirm. Wait for verification, then click **Eject**. Insert the card into the powered-off sampler and turn it on.

Files written by **Write SD card** are assigned directly; a separate hardware WAV-import step is not required.

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

## Tests

```sh
swift test
```

Eight automated tests cover batch import, category changes, managed copies, persistence, per-pad and bank-wide channel settings, direct card writing on temporary replicas, header validation, preservation of other pads, rollback, concurrent card changes and malformed input. The optional ninth test skips unless a card path is provided:

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
Tests/PadShelfTests/             Library and card-writer tests
scripts/build-icon.sh           macOS icon packaging
scripts/package-dmg.sh          Installable disk image packaging
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
