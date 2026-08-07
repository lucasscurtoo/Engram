# Recall

Native macOS spaced-repetition study app, open source. Two jobs: **retain**
knowledge over time (FSRS v5 scheduling) and **sustain focus** while studying
(integrated focus mode). Local-first: your data lives on your disk, no
accounts, no networking.

> Working title. Rename in `Sources/Presentation/RecallApp.swift` (`AppInfo.name`)
> and `project.yml` — nowhere else.

## Build

```sh
brew install xcodegen
xcodegen generate
open Recall.xcodeproj   # run the Recall scheme
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

macOS exposes no public API to toggle a Focus filter, so Recall drives two
**Shortcuts you create yourself** (Shortcuts.app → new shortcut → *Set Focus*):

| Shortcut name | What it should do |
| --- | --- |
| `Recall Focus On` | Turn Do Not Disturb (or your own Focus) **on** |
| `Recall Focus Off` | Turn it **off** |

Name them exactly like that. Recall runs them via `/usr/bin/shortcuts` when a
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
- [x] **M1** — FSRS v5 engine, ported from py-fsrs 4.1.2, tests green (15 tests, 9 replay scenarios)
- [ ] **M2** — SwiftData persistence (contracts in `Sources/Infrastructure/Persistence/`)
- [ ] **M3** — decks/notes/tags UI, Quick Add, browser
- [ ] **M4** — review session UI (service logic already implemented + tested)
- [ ] **M5** — focus mode (Pomodoro/deep work, DND, ambience, menu bar timer)
- [ ] **M6** — stats (Swift Charts) + daily reminder
- [ ] **M7** — polish + release

See `RECALL_PROJECT_BRIEF.md` (owner's copy) for the full contract. Grep
`TODO(owner):` for every pending seam.

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
