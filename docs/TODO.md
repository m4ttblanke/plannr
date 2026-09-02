# Plannr — TODO

Working list of known problems and planned features. Last updated: September 1, 2026.

---

## Problems to fix

### High priority

- **Confirm the Gemini model name on the live backend.**
  `backend/app.py` calls `model='gemini-3.7-flash'`. Verify a real syllabus
  parses end-to-end against production after each deploy — a wrong model id
  fails 100% and the core feature does nothing.

### Medium priority

- **No way to edit a class schedule after creation.**
  `AddClassView` now has the structured `ClassSchedulePicker`, but
  `ClassEditView` only *displays* the schedule string. Add the picker there too
  (needs it to accept an initial value, or to store structured schedule data on
  the `Class` model).

- **Schedule is display-only.** The `Class.schedule` string is never used to
  place recurring class meetings on Google Calendar. If we want that, persist
  structured `Weekday` + time (and section) on the model and generate events.

- **"Current Term" settings do nothing.** Profile → Settings collects a term
  label + start/end dates that nothing consumes. Either wire it up (default
  class end dates, constrain syllabus date inference to the term window) or
  remove the section.

- **OCR is not enabled in production.** The Render Python runtime has no
  `tesseract` / `poppler` binaries and there is no `Aptfile` / Dockerfile, so
  OCR of scanned-only PDFs fails in prod ("Could not extract text from PDF").
  Add an `Aptfile` (`tesseract-ocr`, `poppler-utils`) or switch to a Docker
  deploy. Text-layer PDFs are unaffected.

- **iOS 64-notification cap.** `NotificationManager.sync` schedules one local
  notification per event; a student with many upcoming deadlines silently loses
  reminders past 64. Schedule only the nearest N and reschedule as they pass.

- **401 interceptor is not fully global.** `AuthManager.send()` covers the sync
  paths and the launch `/me` call, but a 401 from any other/future authenticated
  request would not trigger the session-expired sign-out. Route all authed
  requests through `send()`.

- **Account deletion, slow-success edge case.** If `DELETE /account` succeeds
  server-side but the response times out, the client reports failure and keeps
  local data even though the account is gone. Rare; low urgency.

### Low priority / cleanup

- `EventEditView` "type" is a free-text field — no dropdown, so values
  (homework/exam/quiz/lab/other) are not standardized.
- `WeeklyDashboardView.statCard` has a dead ternary
  (`isPercentage ? "\(count)" : "\(count)"`).
- `WeeklyDashboardView.getWeekendEvents()` is unused; `dayColumn` has an empty
  `.onTapGesture {}`.
- `Info.plist` has a stray empty `<dict/>` in `CFBundleURLTypes`.
- `UISegmentedControl.appearance()` is mutated globally inside `.onAppear` in two
  views — an app-wide side effect.
- `CalendarPreviewView` main event list uses `ForEach(events.indices, id: \.self)`
  — fragile if the list length ever changes.
- Bundle-ID mismatch: app target is `com.matthewblanke.plannr`; the test targets
  and `Info.plist` `CFBundleURLName` say `com.plannr.app`. Confirm intentional.
- Deprecated `onChange(of:perform:)` (iOS 17) warnings in ~4 views.
- `SyllabusUploadView.swift` — `var parsedEv` is never mutated (compiler warning).
- The iOS test suite covers almost nothing real — no tests for the reconcile /
  sync-body / color-hex / date-math logic.
- Landing-page "What's next" ticker ignores `prefers-reduced-motion`.

---

## Upcoming features

### Pre-launch polish

- **Crash reporting** (Sentry or Firebase Crashlytics) — highest-value beta add;
  testers will report "it crashed" with no stack trace otherwise.
- **First-run onboarding** — 3 cards: upload → review & edit → sync.
- **"Try a sample syllabus"** button on the empty state so a new user sees the
  whole flow without hunting for a PDF.
- **Phased progress during parsing** — "Waking server… → Reading PDF… →
  Extracting events…" instead of one spinner (the cold start looks like a hang).
- **Sync resilience** — retry with backoff on transient failures. (The
  delete-and-recreate behavior is fixed: sync is now an incremental
  patch/insert/delete diff against the existing calendar.)
- **Editable schedule after creation** (see Medium-priority bug).
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
