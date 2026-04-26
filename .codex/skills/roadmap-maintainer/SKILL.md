---
name: roadmap-maintainer
description: Use when updating, reviewing, prioritizing, or turning ideas into tasks for this repository's ROADMAP.md. Applies to roadmap status markers, dependency-aware ordering, scope clarification, completion criteria, and keeping README.md or CHANGELOG.md aligned with shipped roadmap work.
---

# Roadmap Maintainer

Use this skill when the user asks to add to, revise, prioritize, review, or turn
items from `ROADMAP.md` into implementation tasks.

## Workflow

1. Read `ROADMAP.md` before changing roadmap content.
2. Preserve dependency-aware priority order unless the user asks to reorganize
   it.
3. Place new items in the earliest section where their prerequisites are
   already represented.
4. Clarify vague ideas into implementation-facing roadmap bullets.
5. Prefer small, independently shippable items over broad bundled initiatives.
6. Check for duplicates before adding new items.
7. Keep wording high level, but include enough scope to avoid later ambiguity.

## Status Markers

- Use `[ ]` for planned work.
- Use `[~]` for work in progress.
- Use `[x]` for shipped work.
- Use `[?]` for research or decision items.
- Check completed items off in place instead of moving them to a separate
  completed section.

## Prioritization Rules

Order work to minimize blockers, dependencies, and conflicts:

1. Privacy, storage, data model, and documentation foundations.
2. Recording reliability and user feedback.
3. Transcript correction, dictionaries, and profile primitives.
4. File workflows, search, import/export, batch jobs, and CLI.
5. Local and remote post-processing providers.
6. Advanced transcription and app-aware workflows.
7. Distribution, updates, onboarding, CI, and operational polish.

If a feature affects privacy, storage, transcript metadata, import/export, CLI,
or post-processing, make sure the relevant foundation is already captured before
placing the feature later in the roadmap.

## Completion Hygiene

When a roadmap item ships:

- Mark it `[x]` in `ROADMAP.md`.
- Add or update user-facing documentation in `README.md` when users need to know
  how to use the behavior.
- Add a `CHANGELOG.md` entry for shipped user-facing behavior when appropriate.
- Prune completed roadmap items only after the shipped behavior is documented.

## Task Breakdown Guidance

When turning roadmap items into tasks, include:

- Prerequisites and dependencies.
- Suggested implementation order.
- Acceptance criteria.
- Privacy/security implications.
- Documentation and changelog updates.
- Focused verification steps.
