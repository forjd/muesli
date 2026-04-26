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
- Added voice-activity-driven live chunk rotation so streaming transcription
  prefers natural speech pauses while retaining a maximum chunk length fallback
  and failed-chunk retry support.
- Added replacement rules for deterministic transcript cleanup, with a promotion
  action for the last manual transcript edit.
- Added a custom dictionary correction layer for preferred words, names, product
  terms, acronyms, and domain vocabulary.
- Added profile-specific custom dictionaries with built-in General, Work, Code,
  Medical, and Legal profiles plus custom profile creation.
- Documented FluidAudio vocabulary boosting limits and clarified that current
  dictionaries are post-transcription correction layers, not model adaptation.
- Added optional FluidAudio CTC vocabulary boosting for final-pass transcription
  using the selected dictionary profile, with offline-safe fallback to regular
  transcription and deterministic cleanup.
- Added optional fuzzy dictionary suggestions per profile, with transcript-level
  review before applying near-match replacements.
- Added audio file import for existing WAV, M4A, MP3, AIFF, and CAF recordings.
- Added Markdown, DOCX, and clipboard-template transcript exports.
- Added search and status filtering across saved recordings and transcripts.
- Added a JSON CLI command contract with `spec`, stable envelopes, warnings, and
  actionable fix fields.
- Added batch audio import and visible transcript batch export workflows.
- Added first CLI workflows for file transcription, named dictionary profiles,
  and file-based transcript export.
- Added the first meeting workflow slice with meeting-tagged recordings,
  FluidAudio offline speaker diarization for timed live transcript segments,
  anonymous speaker labels, and speaker-separated exports.
- Added meeting source metadata, optional system-audio capture through
  ScreenCaptureKit, and Settings/readiness controls for speaker diarization
  model loading.
- Added meeting audio import, separate system-audio transcript capture for
  meeting recordings, and built-in Markdown meeting notes templates.
- Added live LS-EEND speaker diarization during meeting recording and PDF export
  for built-in meeting notes templates.

## [0.2.0](https://github.com/forjd/muesli/compare/v0.1.2...v0.2.0) (2026-04-26)


### Features

* add custom dictionary corrections ([958d3ee](https://github.com/forjd/muesli/commit/958d3ee5d998db95c43f1370129355b8e95002ab))
* add dictation storage modes ([95bec7a](https://github.com/forjd/muesli/commit/95bec7a703a808415ae64d0f8fd343034af41421))
* add dictionary profiles ([660ecbe](https://github.com/forjd/muesli/commit/660ecbe06c33dab176b4f6b4c4b1bc4cd782b174))
* add explicit offline mode ([beac981](https://github.com/forjd/muesli/commit/beac9814c39a75c56af6e5bc595c5b3fe197234a))
* add global dictation feedback ([daa1470](https://github.com/forjd/muesli/commit/daa1470de912f8bb9a2889f85c804e0789702e68))
* add menu bar controls ([a068265](https://github.com/forjd/muesli/commit/a068265ba333ec0bdb30b3902dff45d1fb7bedcf))
* add optional dictation sound effects ([52e35fd](https://github.com/forjd/muesli/commit/52e35fdcffc2c121b389ea60591fc8391dd6c6a3))
* add privacy model and encrypted local storage ([21d31aa](https://github.com/forjd/muesli/commit/21d31aa4f1a71412c4ece344f7ed6962dd4b4a10))
* add recording overlay ([a17c6bc](https://github.com/forjd/muesli/commit/a17c6bc6856288b3af92c9838b854b24dbfe879c))
* add retention controls ([e501944](https://github.com/forjd/muesli/commit/e5019442b397c7e9ce6874d75e046a8af99ab5e6))
* add transcript replacement rules ([c9fa373](https://github.com/forjd/muesli/commit/c9fa373cece8f79f59060adf730cb2b5a98219e9))
* add VAD chunk rotation ([866c2af](https://github.com/forjd/muesli/commit/866c2afb257a7e470909081fa37d6f7617f76aca))
* improve recoverable error states ([e47d01e](https://github.com/forjd/muesli/commit/e47d01e7d9d5ef85e9f1b0f77495a4733c37dc20))

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
