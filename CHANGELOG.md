# Changelog

## Unreleased

- Added a visible privacy mode for local-only dictation and documented the
  planned local and remote post-processing privacy states.
- Encrypted saved transcript metadata and stored recording files with a
  Keychain-backed local storage key.
- Added configurable retention controls for automatically deleting old
  recordings, transcript text, or both.
- Added dictation storage modes for never saving audio or saving nothing after
  paste/copy.
- Added offline mode that blocks recording and transcription until the selected
  model is already cached locally.
- Added actionable issue banners for microphone, Accessibility, model load,
  paste, and hotkey failures.
- Added global dictation feedback events and background notifications for
  recording, transcription, failures, and paste completion.
- Added optional sound effects for recording start, stop, cancellation, failure,
  and paste feedback.
- Documented configurable dictation modes for toggle, push-to-talk, and hybrid
  workflows.
- Added a floating recording overlay with elapsed time, audio level, mode,
  privacy state, stop, and cancel controls.
- Added replacement rules for deterministic transcript cleanup, with a promotion
  action for the last manual transcript edit.
- Added a custom dictionary correction layer for preferred words, names, product
  terms, acronyms, and domain vocabulary.
- Added profile-specific custom dictionaries with built-in General, Work, Code,
  Medical, and Legal profiles plus custom profile creation.

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
