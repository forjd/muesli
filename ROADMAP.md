# Roadmap

This roadmap is intentionally high level. It captures the product directions
that seem most valuable for Muesli without committing to dates or release
numbers.

The order below prioritizes work that reduces later rework: privacy/storage
foundations first, then transcription and workflow primitives, then provider and
distribution features that depend on those foundations.

## 1. Privacy, Storage, and Data Model Foundations

- [x] Define a clear privacy model with visible states for local-only dictation,
  local transcription with local AI post-processing, and remote post-processing.
- [x] Document what data stays local, what can leave the machine when optional
  integrations are enabled, and where local files are stored.
- [x] Encrypt local storage for recordings, transcripts, transcript metadata, and
  settings that may contain sensitive text. Store provider API keys separately
  in Keychain.
- [x] Add retention controls for automatically deleting recordings, transcripts, or
  both after a configurable period.
- [x] Add a "never save audio" mode for dictation workflows. Temporary audio may be
  used while recording/transcribing, but should be deleted after success,
  cancellation, and recoverable failures. Make transcript saving a separate
  choice so users can keep only the final transcript or keep nothing after
  paste/export.
- [x] Add an explicit offline mode that prevents user content from leaving the
  machine, blocks remote post-processing, and disables optional network features
  once required models are cached. Before models are cached, show a clear
  download exception instead of silently using the network.

## 2. Recording Reliability and Feedback

- [x] Improve error states for missing microphone permission, missing Accessibility
  permission, failed model load, failed paste, and unavailable hotkeys.
- [x] Improve global dictation feedback when recording starts, stops, transcribes,
  fails, or pastes into another app.
- [x] Add optional sound effects for recording start, stop, cancellation, and
  failure states.
- [x] Add configurable recording modes for toggle, push-to-talk, and one-shot
  dictation workflows.
- [x] Add a lightweight screen overlay while recording, including elapsed time,
  audio level, active mode, privacy state, and clear stop/cancel affordances.
  Decide whether it should appear above full-screen apps.
- [x] Add VAD-driven chunk rotation so live transcription splits audio at natural
  speech pauses instead of fixed intervals. Preserve privacy/storage guarantees
  for generated chunks and surface partial-failure recovery.

## 3. Transcription Correction and Profiles

- [x] Add replacement rules for deterministic cleanup, such as expanding shorthand,
  fixing repeated mistranscriptions, or enforcing punctuation and casing. Let
  users promote manual transcript edits into future replacement suggestions.
- [x] Add a custom dictionary for preferred words, names, product terms, acronyms,
  and domain-specific vocabulary. Treat the first version as a correction layer
  unless FluidAudio or Parakeet exposes direct vocabulary biasing.
- [x] Support profile-specific dictionaries so users can switch between general,
  work, code, medical, legal, or project-specific vocabularies.
- [x] Investigate whether FluidAudio or the underlying Parakeet model supports any
  practical form of vocabulary biasing or adaptation, and document the limits
  before presenting it as model teaching in the UI.
- [x] Add optional FluidAudio CTC vocabulary boosting for final-pass transcription
  using the selected dictionary profile, with clear download, latency, and
  streaming-accuracy limits. Keep replacement rules as a fallback correction
  layer.
- [ ] Add optional fuzzy dictionary matching with conservative thresholds,
  per-profile enablement, and visible review of proposed replacements before
  applying broad automatic corrections.

## 4. File Workflows and Automation

- [ ] Add audio file import for transcribing existing recordings. Define supported
  formats, whether imported files are copied into Muesli storage, and how
  imported audio follows encryption, retention, and never-save-audio settings.
- [ ] Add richer export options for Markdown, DOCX, and clipboard templates.
- [ ] Add search and filtering across saved recordings and transcripts.
- [ ] Add a machine-readable JSON command contract for the CLI, including a
  `spec` command, stable success/error envelopes, schema version, warnings, and
  actionable `fix` fields for failures.
- [ ] Add batch import and export for processing multiple recordings or transcripts,
  with progress reporting, partial failure handling, and optional
  post-processing.
- [ ] Add a command-line interface for scripting transcription, export, and
  automation workflows. The first version should support transcribing files,
  exporting transcripts, and using named profiles without requiring the main UI.

## 5. Post-Processing Providers

- [ ] Add optional transcript post-processing through local AI providers such as
  Ollama.
- [ ] Provide configurable post-processing presets, such as clean dictation,
  preserve exact wording, turn into notes, format as email, summarize, or fix
  punctuation only.
- [ ] Keep a local audit trail of post-processing actions, including provider,
  preset, timestamp, and whether transcript content left the machine.
- [ ] Add optional remote provider support for OpenAI, Anthropic, and OpenRouter.
- [ ] Make provider use explicit per workflow and default remote providers to off so
  privacy-sensitive users do not accidentally send transcripts to a remote
  service.

## 6. Advanced Transcription and App-Aware Workflows

- [ ] Add a dedicated meeting mode that captures microphone and system audio as
  separate sources, stores their privacy/retention metadata, and keeps dictation
  workflows separate from meeting sessions.
- [ ] Add meeting transcription primitives on top of meeting mode: VAD-aware
  chunking, speaker diarization, speaker-separated transcript formatting, and
  meeting-specific export hooks.
- [ ] Add meeting notes workflows with built-in and custom templates, explicit
  post-processing provider selection, regeneration with a different template,
  and export to Markdown/PDF.
- [ ] Add optional calendar-aware meeting assistance, including upcoming-meeting
  detection, meeting URL extraction, and clear join-only, record-only, and
  join-and-record actions.
- [ ] Add speaker diarization for meetings, interviews, and other multi-speaker
  recordings. Start with anonymous speaker labels and speaker-separated
  formatting, then investigate persistent speaker naming later.
- [ ] Add configurable automatic actions after transcription, such as copy, paste,
  save only, export, post-process, or delete source audio.
- [ ] Add app-specific dictation behavior for common targets such as editors,
  browsers, chat apps, and document tools.

## 7. Distribution and Operations

- [ ] Keep CI focused on build health, logic tests, packaging, and release artifact
  integrity.
- [ ] Add a model management view for cached and available models, including
  background download, delete, selected-model switching, cache size, offline-mode
  compatibility, and download failure recovery.
- [ ] Improve first-run onboarding for permissions, model download, offline mode,
  and global hotkey setup.
- [ ] Add a live dictation test to onboarding that verifies the full record,
  transcribe, copy/paste, permission, hotkey, and selected-model pipeline before
  marking setup complete.
- [ ] Add notarization support for release builds.
- [?] Add automatic updates for installed release builds. Evaluate Sparkle against
  GitHub Releases-based updating, including stable and beta channel support.
- [ ] Add crash/error reporting that is local-first by default and opt-in for any
  external telemetry.

## Open Questions

- FluidAudio supports CTC-based custom vocabulary boosting/rescoring, including
  Parakeet TDT 0.6B via a separate CTC encoder. It is not model training or
  adaptation, and Muesli dictionaries remain a post-transcription correction
  layer until that rescoring path is implemented.
- Should encrypted storage be enabled by default, optional, or tied to a privacy
  mode?
- Which post-processing provider should be implemented first: Ollama for
  local-first users, or a remote API for higher-quality transformations?
- How much UI should live in the menu bar versus the main window once overlay
  recording and post-processing controls exist?

## Roadmap Maintenance

- Keep items in dependency-aware priority order.
- Use `[ ]` for planned work, `[~]` for work in progress, `[x]` for shipped
  work, and `[?]` for research or decision items.
- Check completed items off in place instead of moving them to a separate
  section.
- Record shipped user-facing changes in `CHANGELOG.md`.
- Prune completed roadmap items only after the shipped behavior is documented in
  `README.md` or another appropriate user-facing document.
