# Changelog

## [0.1.2](https://github.com/forjd/muesli/compare/v0.1.1...v0.1.2) (2026-04-25)


### Bug Fixes

* avoid keychain signing on ci releases ([229eb3b](https://github.com/forjd/muesli/commit/229eb3b8f95aac5b61ecdce429a74e332dcef9ae))

## [0.1.1](https://github.com/forjd/muesli/compare/v0.1.0...v0.1.1) (2026-04-25)


### Bug Fixes

* read release version from version file ([15aad7a](https://github.com/forjd/muesli/commit/15aad7af0d7f92c7dcbba385f4d475054617e656))

## 0.1.0 - 2026-04-25

Initial public release.

- Native macOS SwiftUI voice-to-text app.
- Local Parakeet transcription through FluidAudio.
- Support for Parakeet TDT 0.6B v3 and v2.
- Recording history with transcript editing, copy, delete, and export.
- Global dictation hotkey with toggle, push-to-talk, and hybrid modes.
- Custom dictation hotkeys.
- Automatic clipboard copy and Accessibility-based paste into the previous app.
- First-run readiness check for microphone, Accessibility, model, and hotkey state.
- App icon and signed macOS app bundle packaging.

This build is signed with a local/developer signing identity when no
`MUESLI_CODESIGN_IDENTITY` is provided. It is not notarized.
