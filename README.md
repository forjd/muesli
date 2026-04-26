# Muesli

Muesli is a native macOS voice-to-text app built with SwiftUI. It records audio,
transcribes it locally with NVIDIA Parakeet through
[FluidAudio](https://github.com/FluidInference/FluidAudio), and can paste a
finished dictation back into the app you were using.

The app is intentionally local-first: recordings stay on disk, transcription runs
on-device, and FluidAudio caches the Parakeet Core ML model artifacts after the
first load.

See [ROADMAP.md](ROADMAP.md) for planned product directions.

## Features

- Local Parakeet transcription through FluidAudio.
- Model picker for Parakeet TDT 0.6B v3 and v2.
- Live recording view with level meter and stabilized partial transcript.
- Saved recording history with transcript editing.
- One-shot global dictation using `Command-Shift-D`.
- Menu bar controls for dictation, recording, model selection, and settings.
- Export transcripts as plain text, JSON, or SRT.
- Development launcher that creates a stable local signing identity so macOS
  permissions survive rebuilds.

## Requirements

- macOS 14 or newer.
- Xcode command line tools or Xcode with Swift 5.9 support.
- Microphone permission for recording.
- Accessibility permission for global dictation paste.
- Network access on first model use so FluidAudio can download model artifacts.

## Quick Start

```bash
git clone https://github.com/forjd/muesli.git
cd muesli
./script/build_and_run.sh
```

The first launch may take longer because Swift Package Manager resolves
FluidAudio and FluidAudio downloads the selected Parakeet model. Later launches
reuse the cached build and model files.

## Installing Release Builds

Release archives are signed but not notarized yet. If macOS blocks a downloaded
release build, remove the quarantine attribute after unzipping it:

```bash
xattr -dr com.apple.quarantine /Applications/Muesli.app
open /Applications/Muesli.app
```

Adjust the path if you run Muesli from somewhere other than `/Applications`.
This only bypasses the Gatekeeper quarantine warning; Microphone and
Accessibility permissions still need to be granted in System Settings.

## Permissions

Muesli needs two macOS permissions:

- **Microphone**: required to record audio.
- **Accessibility**: required for the `Command-Shift-D` dictation workflow to
  paste text into the app that was active when recording started.

For Accessibility, add this app bundle:

```text
/path/to/muesli/dist/Muesli.app
```

The development launcher signs the app with a local project-specific signing
identity. If you previously granted Accessibility to an older build, remove it
from System Settings and add the current `dist/Muesli.app` once.

## Usage

Run the app:

```bash
./script/build_and_run.sh
```

Use the main window or menu bar item to record, transcribe, export, copy,
delete, and edit transcripts.

Use global dictation:

1. Click into a text field in another app.
2. Press `Command-Shift-D` to start recording.
3. Speak.
4. Press `Command-Shift-D` again to stop, transcribe, and paste.

## Development

Build without launching:

```bash
swift build
```

Launch with app logs:

```bash
./script/build_and_run.sh --logs
```

Launch with focused Muesli telemetry:

```bash
./script/build_and_run.sh --telemetry
```

Verify that the app can build, sign, and launch:

```bash
./script/build_and_run.sh --verify
```

Run focused logic tests:

```bash
swift run MuesliTests
```

GitHub Actions also runs `swift build` and `swift run MuesliTests` on pushes,
pull requests, and manual CI workflow dispatches.

## Packaging

Create a release app bundle and zip archive:

```bash
./script/package_release.sh
```

The script writes artifacts to `dist/release/`, verifies the app signature, and
generates release notes. Set `MUESLI_VERSION` to override the default release
version, and set `MUESLI_CODESIGN_IDENTITY` to sign with a distribution identity.

In GitHub Actions, archives use ad-hoc signing unless
`MUESLI_CODESIGN_IDENTITY` is configured. Local builds without
`MUESLI_CODESIGN_IDENTITY` use Muesli's local development identity. Archives are
not notarized yet.

## GitHub Releases

Releases are automated from Conventional Commits with
[release-please](https://github.com/googleapis/release-please-action).

The normal release flow is:

1. Merge feature and fix commits into `main` using Conventional Commit messages.
2. GitHub Actions opens or updates a release PR that bumps `version.txt` and
   updates `CHANGELOG.md`.
3. Merge the release PR when ready.
4. GitHub Actions creates the GitHub release, builds the signed macOS archive,
   and uploads the zip plus SHA-256 file to the release.

You can also run the `Release` workflow manually from GitHub Actions with a
version number. Manual runs can build artifacts only or publish a release for the
current commit.

## Model Cache

FluidAudio manages the Parakeet model cache. Muesli checks whether the selected
model is already cached and shows the difference between downloading model files
and loading cached files.

If you switch models, the new model may need to download once. After that,
transcription should warm from the local cache.

## Project Structure

```text
Sources/Muesli/App/              App entry point and global hotkey wiring
Sources/Muesli/Models/           Recording and transcript models
Sources/Muesli/Services/         Audio recording, Parakeet, transcript helpers
Sources/Muesli/Stores/           App state, persistence, exports, paste flow
Sources/Muesli/Views/            SwiftUI interface
Resources/Muesli.icns            App icon used by the local app bundle
logo.icon/                       Source icon package
logo Exports/                    Exported PNG source artwork
script/build_and_run.sh          Build, sign, launch, and telemetry helper
script/package_release.sh        Release app bundle and zip archive helper
```

## Notes

Muesli is currently a developer-oriented macOS app. Release archives can be
created locally, but they are not notarized unless you provide your own Apple
Developer signing and notarization workflow. The local scripts create
development signing material under `.dev-certs/`, which is ignored by Git.
