# Engram

Native macOS spaced-repetition study app, open source. Two jobs: **retain**
knowledge over time (FSRS v5 scheduling) and **sustain focus** while studying
(integrated focus mode). Local-first: your data lives on your disk, no
accounts, no networking.

> To rename the app: `Sources/Presentation/EngramApp.swift` (`AppInfo.name`)
> and `project.yml` — nowhere else.

## Features

- **FSRS v5 scheduling** — ported from py-fsrs 4.1.2 and validated against
  generated reference vectors; per-deck target retention.
- **Notes, not just cards** — typed multi-field notes with templates (one
  "Basic" type today, cloze/reversed slot in later), markdown rendering,
  free-form tags, live preview.
- **Decks with subdecks** (`Math::Algebra`), per-deck daily limits and
  retention, roll-up due counts in the sidebar.
- **Review sessions** by deck, tag, or everything: front → reveal → four
  ratings with their predicted intervals. `Space` reveals, `1–4` grade.
- **Quick Add** (`⌘⇧N`) — small window to file a note without navigating.
- **Note browser** — text + tag search, edit and delete in place.
- **Focus mode** — Pomodoro or deep work wrapped around a study queue, goals
  (minutes or cards), menu bar timer, optional Do Not Disturb hook, break/goal
  notifications.
- **Stats** — reviews per day, cards by state, real retention, due forecast,
  focus minutes per day.
- **Daily reminder** — one configurable local notification, opt-out respected.
- **Local-first** — a versioned SwiftData store in Application Support; no
  account, no telemetry, no network.

## Screenshots

<!-- TODO(owner): add screenshots -->

## Build

```sh
brew install xcodegen
xcodegen generate
open Engram.xcodeproj   # run the Engram scheme
```

## Tests

The core (Domain + Application) is a plain Swift package — no Xcode needed:

```sh
swift test
```

The FSRS engine is validated against reference vectors generated from
**py-fsrs 4.1.2** (FSRS v5) with `1e-4` tolerance. To regenerate them:

```sh
python3 -m venv venv && venv/bin/pip install "fsrs==4.*"
venv/bin/python Scripts/generate_fsrs_vectors.py > Tests/DomainTests/FSRSTestVectors.swift
```

## Architecture

Four layers, dependency rule points inward. Domain imports nothing but Foundation.

```
Sources/
├── Domain/           # pure Swift: entities, FSRS engine, repository protocols
├── Application/      # use cases: review session, decks, stats, focus
├── Infrastructure/   # SwiftData repos, notifications, system focus (M2+)
└── Presentation/     # SwiftUI app (Xcode target; the rest is the SPM package)
```

Extensibility seams (implemented as abstractions from day one — the MVP ships
one variant of each, the code depends only on the abstraction):

1. **NoteType** — a card is not front+back; notes have N typed fields, templates generate cards (`NoteType.makeCards`).
2. **ContentType / ContentRenderer** — markdown now, LaTeX/code/images plug in as renderers.
3. **StudySession** — SRS review is one study mode; cram/quiz implement the same protocol.
4. **Decks + tags + CardQuery** — subdecks, free tags; smart decks = saved queries.
5. **Quick Add** — single write path in `DeckService.addNote`.
6. **Per-deck FSRS config** — `DeckConfig` on every deck.
7. **DistractionBlocker** — MVP triggers macOS DND; system-wide blocking is a future implementation.

## Focus & Do Not Disturb

Focus mode (Pomodoro or deep work, optional goal, optional deck/tag to study
inside the block) lives in the sidebar's **Focus** entry, with a live timer in
the menu bar. Everything below is optional — the session works without any of it.

macOS exposes no public API to toggle a Focus filter, so Engram drives two
**Shortcuts you create yourself** (Shortcuts.app → new shortcut → *Set Focus*):

| Shortcut name | What it should do |
| --- | --- |
| `Engram Focus On` | Turn Do Not Disturb (or your own Focus) **on** |
| `Engram Focus Off` | Turn it **off** |

Name them exactly like that. Engram runs them via `/usr/bin/shortcuts` when a
focus block starts and ends. Only the focus engine calls this — the UI never
toggles it directly (seam 7, `DistractionBlocker`).

It degrades gracefully at every step: shortcuts missing, `shortcuts` CLI
unavailable, permission denied or a shortcut that hangs (it is killed after a
few seconds) are all swallowed silently. You lose the Do Not Disturb switch,
never the session.

Same for the rest: notifications (block ends, break reminders, goal reached) are
skipped if permission is denied, and ambient sound is disabled in the UI until
`ambience-rain` / `ambience-whiteNoise` / `ambience-cafe` loops are bundled in
the app target.

## Status (milestones)

- [x] **M0** — scaffold: XcodeGen project, SPM core, app opens a window
- [x] **M1** — FSRS v5 engine, ported from py-fsrs 4.1.2 (9 replay scenarios, 1e-4)
- [x] **M2** — SwiftData persistence, versioned schema, cascade rules
- [x] **M3** — decks/notes/tags UI, Quick Add, browser
- [x] **M4** — review session UI with keyboard shortcuts
- [x] **M5** — focus mode (Pomodoro/deep work, DND hook, menu bar timer, goals)
- [x] **M6** — stats (Swift Charts) + daily reminder
- [x] **M7** — polish, error surface, app icon, accessibility pass

The MVP is complete. 34 tests across engine, services and persistence.

## Post-MVP roadmap / known gaps

Every gap is marked `TODO(owner):` at the exact seam it plugs into. Current inventory:

**Content & study**
- LaTeX renderer (KaTeX in WKWebView) at `ContentRenderer`; `.code`/`.image` content types.
- New note types (reversed, cloze, typed answer) — re-sync generated cards on edit.
- Smart decks: saved `CardQuery` filters as sidebar entries.
- Daily limits should subtract cards already studied today.
- Per-deck optimized FSRS weights (needs the review log history — already recorded).

**Focus**
- Bundle 2–3 royalty-free ambience loops (`ambience-rain` / `-whiteNoise` / `-cafe`).
- System-wide app/website blocking via Family Controls / Network Extension (second `DistractionBlocker` implementation; needs Apple entitlements).

**App**
- System-wide global hotkey for Quick Add.
- Refresh the daily notification body with the real due count on app close.
- Tag token field with completion.
- App Sandbox + entitlements, real bundle id prefix, screenshots for this README.

### Notes for contributors/agents

- Never read `card.front` — there is none. Go through `note.fields` via the
  `NoteType` (`frontFields`/`backFields`).
- Never render raw strings — go through `FieldContentView`/`ContentRenderer`.
- Never assume study == SRS — go through `StudySession`.
- The FSRS engine must keep passing the reference vectors; if you touch
  `FSRS.swift`, regenerate nothing — fix the code.
- `~/Proyectos/AgenticNotch` is a good local reference for menu-bar app
  patterns, but it is **GPL-3**: learn from it, do not copy code into this MIT repo.

## License

MIT — see [LICENSE](LICENSE).
