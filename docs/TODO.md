# Plannr — TODO

Working list of known problems and planned features. Last updated: September 2, 2026.

---

## Problems to fix

### High priority


### Medium priority

- **OCR is not enabled in production.** The Render Python runtime has no
  `tesseract` / `poppler` binaries and there is no `Aptfile` / Dockerfile, so
  OCR of scanned-only PDFs fails in prod ("Could not extract text from PDF").
  Add an `Aptfile` (`tesseract-ocr`, `poppler-utils`) or switch to a Docker
  deploy. Text-layer PDFs are unaffected.

---

## Upcoming features

### Pre-launch polish

- ~~**Sync resilience** — retry with backoff on transient failures.~~ — done.
  `AuthManager.send` (the one network choke point, so this covers sync, meeting
  sync, syllabus parse, export, visibility) now retries up to 3 attempts on
  HTTP 5xx / 429 or a connection-level `URLError` (timeout, connection lost,
  host unreachable — e.g. a Render dyno waking), with exponential backoff +
  jitter and `Retry-After` support. 401 / other 4xx / non-`URLError` throws are
  not retried. (The delete-and-recreate behavior was already fixed: sync is an
  incremental patch/insert/delete diff.)
  Retries are safe now that inserts are idempotent: `/calendar/sync` stamps each
  event with the client's `local_id` (`plannrLocalId` extended property) and
  looks it up before inserting, so a retried request patches the event it
  already created instead of duplicating it (`test_calendar_sync.py`).
  And a sync that still fails all its retries no longer waits for the user:
  `NetworkMonitor` + a foreground hook re-fire `ClassAutoResync` for any class
  with `hasUnsyncedChanges` when connectivity returns (silent, no UI).
- ~~**Restore a sync session.**~~ — done (events only, per the v1 note).
  `SyncSessionsView` gained a **Restore this version** action per session
  (confirm dialog; disabled on the session that matches the current state).
  `ClassRestore.plan` reconciles the snapshot against the current events
  (`EventReconciler` with a new `preferParsedOverEdited` flag — the snapshot
  wins over a local edit but keeps the Google event id for a patch), then the
  push reuses the normal `/calendar/sync` full-sync path (patch / insert /
  delete, no rebuild). The restore is stored locally first (so a sync failure
  just leaves it pending for the reconnect auto-resync) and appended to
  `syncHistory`, so it's itself undoable. Status / color / schedule / meetings
  are untouched.
- Haptics on accept / decline / sync success.
- App icon and launch screen pass (currently generated defaults).
- Backend `/health` endpoint + an uptime monitor (also keeps the free dyno warm,
  which improves cold-start and OAuth reliability).
- Accessibility pass — Dynamic Type, VoiceOver labels on icon-only buttons,
  contrast on gray-on-black captions.

### Product roadmap (from the landing page "What's next")

- Canvas integration — pull assignments and due dates straight from Canvas.
- Apple Calendar support (Google Calendar only today).
- AI workload estimation — estimate time each assignment will take.
- Conflict detection — flag weeks/days with overlapping deadlines.
- Grade-weight integration — prioritize by impact on final grade.
- Daily agenda — recommend what to work on each day.
- Workload feedback — improve estimates from how long work actually took.
- Project breakdown — split large projects into subtasks and milestones.
- Syllabus Q&A — answer questions about deadlines and course info.
- Natural-language calendar editing — edit the schedule by typing.
- Deadline verification — flag uncertain deadlines for confirmation.
- Shared study groups — coordinate schedules and study sessions with classmates.
