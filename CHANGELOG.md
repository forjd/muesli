# Changelog

## 0.1.0 - 2026-04-25

Initial public release.

- Native macOS SwiftUI voice-to-text app.
- Local Parakeet transcription through FluidAudio.
- Support for Parakeet TDT 0.6B v3 and v2.
- Recording history with transcript editing, copy, delete, benchmark, and export.
- Global dictation hotkey with toggle, push-to-talk, and hybrid modes.
- Custom dictation hotkeys.
- Automatic clipboard copy and Accessibility-based paste into the previous app.
- First-run readiness check for microphone, Accessibility, model, and hotkey state.
- App icon and signed macOS app bundle packaging.

This build is signed with a local/developer signing identity when no
`MUESLI_CODESIGN_IDENTITY` is provided. It is not notarized.
