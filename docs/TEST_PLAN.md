# Plannr — Full Manual Test Walkthrough

A single sit-down pass that exercises every feature. Work top to bottom; state
builds up as you go (sign in → class → syllabus → sync → re-upload → edit →
meetings → dashboard → settings → cleanup).

**Time:** ~35–45 min for the main run, plus ~15 min for the separate-setup
sections at the end.

Legend: `[ ]` do this · **Expect:** what should happen · 🔎 verify in Google
Calendar at [calendar.google.com](https://calendar.google.com).

---

## 0. Before you start

- [ ] **Backend is up.** Either the production API (`https://plannr-api.onrender.com`)
  or a local one:
  ```bash
  cd backend && source venv/bin/activate
  uvicorn app:app --reload      # needs Postgres running + backend/.env filled in
  ```
  Open `<backend>/docs` in a browser — you should see the Swagger UI.
- [ ] **`Plannr/Plannr/Config.swift`** `BACKEND_URL` points at that backend
  (trailing slash, e.g. `"http://localhost:8000/"` or the Render URL).
- [ ] **Google account** you can sign in with (and later revoke — don't use a
  primary account you can't afford to poke).
- [ ] **Two test syllabi:**
  - `syllabus_A.pdf` — a real course syllabus with a **text layer** (exported
    from Word/Google Docs, not a scan). 6–15 dated items. Ideally it also states
    the meeting times plainly (e.g. "Lecture: MWF 10:00–10:50am", "Discussion
    Thu 3:00–3:50pm", "Final Exam: <date>, <time>") so the schedule auto-fill in
    §1H can be checked.
  - `syllabus_A_v2.pdf` — a copy of A with: one assignment **added**, one
    **removed**, one assignment's **description changed** (same title & date),
    and one assignment **moved to a different date**. You'll use this for the
    re-upload test.
- [ ] Run on an **iOS 18+ Simulator** for the main run. Camera scanning needs a
  **real device** (covered in §2).
- [ ] Build & launch from Xcode (`Cmd+R`) or:
  ```bash
  xcodebuild -project Plannr/Plannr.xcodeproj -scheme Plannr \
    -destination 'platform=iOS Simulator,name=iPhone 16' build
  ```

---

## 1. The continuous run

### A. Sign in with Google

- [ ] Launch the app. **Expect:** the sign-in screen (star, tower art, "Plannr",
  "Syllabus to Schedule", "Sign in with Google", "Continue as Guest").
- [ ] Tap **Sign in with Google** → the system web sheet opens.
- [ ] **Cancel** it (swipe down / Cancel). **Expect:** back to sign-in, **no
  error message**, button not stuck on "Signing in...".
- [ ] Tap **Sign in with Google** again, complete consent.
  **Expect:** the sheet closes and you land on **My Classes** (or Week at a
  Glance if you already have classes).
- [ ] Open the profile avatar (top-right).
  **Expect:** your Google **name and email**, and after a moment your Google
  **profile photo** in the avatar (fetched on launch).
- [ ] Force-quit the app and relaunch.
  **Expect:** still signed in, straight past the sign-in screen.

### B. Add a class (with a structured schedule)

- [ ] Hamburger (≡, top-left) → **My Classes**. Tap **Add New Class**.
- [ ] Leave the name blank. **Expect:** "Add Class" is greyed out / disabled.
- [ ] Name it `CS 101`.
- [ ] In **Schedule (Optional)**: tap **M**, **W**, **F** chips (they turn
  blue). A **Class time** row appears — set it to **10:00 AM**.
- [ ] Toggle **Has a separate section / lab** on. Tap **Th**, set **Section
  time** to **3:00 PM**.
  **Expect:** a blue preview line reads `MWF 10:00 AM · Section Th 3:00 PM`.
- [ ] Set a **Class Color** (pick something distinct, e.g. purple).
- [ ] Tap **Add Class**.
  **Expect:** back on My Classes, a `CS 101` card with a purple bar, the
  schedule text, and an orange **NO SYLLABUS** badge / "Tap to upload syllabus".

### C. Upload a syllabus — PDF (text layer)

- [ ] Tap the `CS 101` card → **Class edit** screen. Tap **Upload New Syllabus**.
- [ ] Tap the dashed upload box → **Upload PDF** → pick `syllabus_A.pdf`.
  **Expect:** a spinner whose caption advances **Waking the server… →
  Reading your syllabus… → Extracting events…** (with 1/2/3 step dots filling
  in), plus the "first upload after a while" note. On a warm server it blows
  through the phases in a second or two; on a cold dyno it steps through them
  over ~30 s so it never looks frozen.
- [ ] **Expect:** you land on the **Calendar Preview** with a list of extracted
  events, each auto-**Accepted**, tagged by type (homework/exam/quiz/lab/other),
  and dates resolved (including any relative ones like "Week 3 Friday").

### D. Calendar Preview — edit, grid, export

- [ ] Toggle the **Week / Month** picker at the top; tap a day with a dot.
  **Expect:** the grid switches and the day's events show below.
- [ ] If the class has a schedule (§1B / §1H) **and** Settings →
  Class Meetings → *Show in Calendar* is on: the grid also carries the recurring
  lecture/section dots and a final-exam dot, and a selected meeting day lists a
  **"Meeting" / "Final" card with no Edit/Accept/Decline** below the grid. These
  are preview-only — they never appear in the accept/decline list and aren't part
  of Sync. With the setting off (default) they don't show.
- [ ] On one event tap **Edit** → change the **Title** and **Description**,
  spin the **Date** wheel forward a day, and open the **Type** menu (it's a
  picker now, not a text field — Homework / Exam / Quiz / Lab / Other) and pick
  a different one. **Save Changes**.
  **Expect:** the card reflects the new title/date/description/type, and the
  type chip / colour + any Week-at-a-Glance filter match the picked category.
- [ ] Tap **Decline** on one event (badge → "Declined"), then **Accept** it
  back.
- [ ] Toolbar **share icon** (top-right) → **Export as .ics (Calendar)**.
  **Expect:** a share sheet with an `events.ics` file. Save/AirDrop it and open
  it — it should import into a calendar app with all accepted events.
- [ ] Share icon → **Export as .csv (Spreadsheet)** → open it: columns
  `Title, Date, Type, Description`, one row per accepted event.

### E. First sync to Google Calendar

- [ ] Tap **Sync!** (bottom). **Expect:** "Syncing..." then an alert
  **"Successfully added all events to your Google Calendar"** / "Successfully
  synced N events!". Tap **OK**.
  **Expect:** you're back at the class list / edit screen; the class badge is
  now **ACTIVE** with "N events synced".
- [ ] 🔎 In Google Calendar: a **new secondary calendar named `CS 101`** in your
  chosen **color**, containing all the accepted events as **all-day** entries on
  the right dates (including the one you edited).

### F. Re-upload an updated syllabus (incremental reconcile)

This is the important one — sync must change only what changed.

- [ ] 🔎 First, in Google Calendar, open one of the synced events and add a
  **location** (e.g. "Room 2044") and a **note** in the description. Save.
- [ ] Back in the app: class → **Upload New Syllabus** → **Upload PDF** →
  `syllabus_A_v2.pdf`.
- [ ] On the Preview, sanity-check: the **added** assignment is present, the
  **removed** one is gone, the **description-changed** one shows the new text,
  the **moved** one shows the new date.
- [ ] Tap **Sync!** → OK.
- [ ] 🔎 In Google Calendar, on the `CS 101` calendar:
  - **Expect:** the added assignment now exists; the removed one is **gone**;
    **no duplicates** of anything.
  - **Expect:** the event you added a location/note to **still has that
    location and note** (sync patches, it doesn't delete-and-recreate).
  - The moved assignment: old date empty, new date has it.
- [ ] In the app, edit an event and re-upload once more (any version).
  **Expect:** your local edit is **preserved** in the Preview (not overwritten
  by the freshly parsed copy).

### G. Edit events after sync (ClassEditView)

- [ ] Open the class. In **Events (N)**:
  - Tap **Edit** on one → change something → Save. **Expect:** a yellow
    **EDITED** badge and the bottom button becomes **Re-sync (1) Change**.
  - Tap **Delete** on another → red **QUEUED** badge, strikethrough, button
    becomes **Undo**. Tap **Undo** → back to normal. Delete it again.
  - Bottom button now reads **Re-sync (2) Changes**.
- [ ] Tap **Re-sync (2) Changes**. **Expect:** "Syncing...", then a **"Sync
  Successful"** alert. Badges clear.
- [ ] 🔎 Google Calendar: the edited event updated in place (same event, changed
  fields); the deleted event **removed**.
- [ ] Tap the **color swatch**, pick a new color.
  **Expect (if already synced):** 🔎 the `CS 101` calendar's color changes in
  Google Calendar within a few seconds (silent, no alert).
- [ ] **End date** row → **Set** → pick a date **in the past** → back out and
  reopen the class. **Expect:** status auto-flips to **INACTIVE** (this also runs
  the INACTIVE side effects below). Set the end date back to the future (or clear
  it with the ✕) and set status back to **ACTIVE** via the badge menu.
- [ ] Tap **View Sync Sessions**. **Expect:** a list of "Session 1", "Session
  2"… each with a date and event count; tap one to expand its events.

### H. Class meetings on the calendar (new)

- [ ] **Schedule auto-fill from the syllabus.** If `syllabus_A.pdf` states the
  meeting times and you had **not** set a schedule on the class before uploading,
  the schedule row after the sync should read what the syllabus said (lecture
  days/time, section days/time). Tap **Edit** — the picker is pre-filled,
  including the **final-exam** date/time if the syllabus gave one. If you *did*
  set a schedule in §1B, it is kept as-is (the parser never overwrites it).
  Re-uploading a syllabus also keeps whatever schedule the class already has.
- [ ] In the class edit screen, the schedule row shows
  `MWF 10:00 AM · Section Th 3:00 PM` (yours from §1B, or the syllabus's). Tap
  **Edit** next to it → the schedule picker opens inline; change the class time
  to **11:00 AM** → tap **Done**. **Expect:** the row text updates.
- [ ] Turn **Add class meetings to Google Calendar** ON.
  **Expect:** a brief spinner, no error.
- [ ] 🔎 Google Calendar, `CS 101` calendar:
  - A **recurring weekly event "CS 101"** on **Mon/Wed/Fri at 11:00–11:50 AM**.
  - A **recurring weekly event "CS 101 (Section)"** on **Thu at
    3:00–3:50 PM**.
  - Recurrence runs until the class end date / term end (or open-ended if
    neither is set — see §2 note on Current Term).
- [ ] Toggle it **OFF**.
  **Expect:** 🔎 both recurring meeting events disappear from Google Calendar
  (the one-off assignment events stay).
- [ ] Toggle it **ON** again, then edit the schedule (remove the section).
  **Expect:** 🔎 the section recurring event is removed; the lecture one stays
  and reflects the change.
- [ ] With meeting sync **ON**, tap the **ACTIVE** badge → choose **INACTIVE**.
  **Expect:** the "Add class meetings to Google Calendar" toggle flips off.
  🔎 In Google Calendar: the recurring `CS 101` / `CS 101 (Section)` events are
  **gone**, and the **`CS 101` calendar is unchecked** (hidden) in the left
  sidebar — but still present under "Other calendars", not deleted. The one-off
  assignment events are untouched.
- [ ] Tap the badge again → **ACTIVE**. **Expect:** 🔎 the `CS 101` calendar is
  **re-checked** in the sidebar. (Meeting sync stays off — re-enable it manually
  with the toggle if you want the recurring events back.)

### I. Unified Calendar view

- [ ] Hamburger → **Calendar**.
- [ ] **Expect:** a horizontal **color legend** of your classes; a **Week/Month**
  grid with color-coded dots per class; tapping a day lists that day's events.
- [ ] Scroll to the list below the grid. **Expect:** its heading is **"This
  Week"** (or **"This Month"** in Month view), and it lists only events in the
  week/month the grid is currently showing — **not** every future event. Move the
  grid with the **‹ ›** arrows. **Expect:** the list follows the grid.
- [ ] Tap an event → an **Event Details** sheet (Date, Type, Description).
  **Done** to close.
- [ ] Back in a class, **Delete** (queue) an event without re-syncing, then
  return here. **Expect:** that queued-for-deletion event does **not** appear
  in the calendar or the list. (Undo it afterward.)
- [ ] (After §K turns on "Show in Calendar":) **Expect:** class meetings and the
  final exam for the visible week/month appear in a **separate "Class Meetings"
  group** below the assignments, and as extra dots on the grid.

### J. Week at a Glance

- [ ] Hamburger → **Week at a Glance**.
- [ ] Use the **‹ ›** arrows to move weeks. **Expect:** "This Week" / "Next
  Week" labels appear on the appropriate weeks; the range text updates.
- [ ] Tap the filter chips (**All / Exams / Homework / Labs / Quizzes /
  Other**). **Expect:** the Upcoming Events list filters by type.
- [ ] Toggle **Hide Completed** / **Show Completed**.
- [ ] In **Upcoming Events**, tap the circle on an event to mark it **complete**
  (title strikes through, circle fills green). Mark 2–3 complete.
  **Expect:** the "Completion" stat and "X/Y done" update.
- [ ] **Force-quit and relaunch the app**, come back to Week at a Glance.
  **Expect:** the events you marked complete are **still complete** (this
  persists now).
- [ ] Check the **stat cards** (This Week / Next Week / Completion), the **Week
  Overview** day columns (workload color + count badge + progress dots), and the
  **Weekend Preview** ("Free / Light / Busy Weekend", "Monday: …").
- [ ] Class meetings, default: with the setting **off** (default), there is **no
  "Class Meetings" group** in the list. (You'll turn it on in §K.)

### K. Profile & Settings

Open the profile avatar (top-right of any tab).

- [ ] **Photo:** tap the avatar → pick an image from Photos. **Expect:** it
  replaces the Google photo everywhere. Tap **Remove Custom Photo** → back to
  the Google photo.
- [ ] **Terms → Manage Terms → New Term.** Leave the name blank, pick
  **Quarter**, set a **Start date**, tap **Save**.
  **Expect:** the row shows a derived name ("Fall 2026" etc.), the date range,
  *10 weeks*, and "0 classes". Reopen it, switch to **Semester** → the length
  caption becomes 16 weeks; **Custom** → a weeks stepper appears.
- [ ] From Manage Terms, add a **second** term. Reopen the first and tap
  **Make Active Term** (or pick it in the My Classes switcher).
- [ ] Go to **My Classes**. The header under the title is a switcher — pick
  **All classes**, the term, **Unfiled**. **Expect:** the list filters, and the
  header shows the current scope.
- [ ] **Add New Class.** The **Term** row is always shown; its menu lists the
  terms plus **New Term…**. Tap **New Term…**, fill it in, **Save** → the new
  term is selected for this class. (Delete a term you created this way from
  Manage Terms afterwards to tidy up.)
- [ ] Create a class filed into a term that is **not** currently active, then
  **Sync!** it. **Expect:** after the sync completes, that term is now the
  **active term** (its name shows under the My Classes title; Calendar / Week
  at a Glance switch to it).
- [ ] Open the class's edit screen. **Expect:** a **Term** picker and an
  **End date** pre-filled to the term's end.
- [ ] Open a term in Manage Terms → **Archive term**. **Expect:** every class in
  it flips to **INACTIVE** (🔎 its recurring meetings leave Google Calendar and
  its calendar is unchecked).
- [ ] In Manage Terms, **delete** a term. **Expect:** its classes aren't deleted
  — they become **Unfiled**.
- [ ] **Deadline Reminders → Remind me:** pick "2 days before".
- [ ] **Class Meetings → Show in Week at a Glance:** turn it **ON**. Go back to
  **Week at a Glance**.
  **Expect:** under the **"All"** filter, a **"Class Meetings"** group lists this
  week's `CS 101` lecture(s)/section with day + time, a "Class" chip, and **no
  completion circle**. Switch to a specific filter (e.g. Exams) — the meetings
  **disappear**.
- [ ] **Class Meetings → Show in Calendar:** turn it **ON**. Go to
  **Calendar** (§I).
  **Expect:** the visible week/month's meetings and any final exam show in a
  **"Class Meetings"** group below the assignments, plus extra grid dots. Turn
  both toggles back off if you prefer the default.
- [ ] **Sync → Auto-sync changes:** turn ON. Go to a class, edit an event.
  **Expect:** it syncs immediately (no "Re-sync" button appears / it clears on
  its own). Turn auto-sync back off.
- [ ] **Sync → Auto-sync class meetings:** turn ON. Add a new class with a
  schedule (or upload a syllabus that states meeting times).
  **Expect:** the new class's **"Add class meetings to Google Calendar"** toggle
  is already ON when you open it, and 🔎 its recurring lecture/section events are
  in Google Calendar without you flipping anything. Classes that already existed
  are untouched. Turn the setting back off; existing on-classes stay on.
- [ ] **Notifications → Deadline reminders:** turn ON → grant the permission
  prompt. (If you deny it, **Expect:** a "Notifications Disabled" alert.)
- [ ] **Beta feedback** (hamburger menu → below the tab items): tap
  **Report an Issue**.
  **Expect:** a mail composer prefilled **To: mattheweblanke@gmail.com**,
  subject **"Plannr Beta — Issue Report"**, body with a "describe the
  issue / steps to reproduce" prompt + your app version / iOS version / device.
  (On a Simulator with no Mail account you get a "Report an Issue" alert with the
  address instead — that's the fallback.) Cancel out.
- [ ] Hamburger menu → **Suggest a Feature** (directly below "Report an Issue").
  **Expect:** the same composer but subject **"Plannr Beta — Feature
  Suggestion"** and a "what would you like / why" prompt. Fallback alert title is
  **"Suggest a Feature"**. Cancel out.

### L. Guest mode

- [ ] Profile → **Sign Out**.
- [ ] On the sign-in screen tap **Continue as Guest**.
  **Expect:** a yellow **"Guest Mode - data won't be saved between sessions"**
  banner.
- [ ] Add a class, upload `syllabus_A.pdf`. On the Preview, **Expect:** the
  bottom button says **Save Class** (not "Sync!"). Tap it.
- [ ] Open that class → **Expect:** no "Add class meetings to Google Calendar"
  toggle (guests can't sync). Editing events shows a **Save Changes** button
  instead of "Re-sync".
- [ ] From a Preview, use **Export as .ics** — **Expect:** it still works for a
  guest.
- [ ] **Force-quit and relaunch.** **Expect:** the guest class is **gone**
  (nothing persisted).
- [ ] Profile → **Exit Guest Mode** → sign back in with Google. Your real
  classes are back.

### M. Delete a class

- [ ] My Classes → tap the **trash** icon on a class you don't need → confirm
  **Delete**.
  **Expect:** it disappears from the list. 🔎 Its secondary Google Calendar is
  also deleted (best-effort — check it's gone).

### N. Wrap the run

- [ ] Everything above passed → the core app is exercised. Move to §2 for the
  bits that need special setup, or §4 to clean up.

---

## 2. Separate setups

### 2a. Camera document scan (real device only)

`VNDocumentCameraViewController` is unsupported on the Simulator.

- [ ] On a real iPhone: class → Upload New Syllabus → **Scan Document** → grant
  camera access → scan a printed syllabus page → the scan is OCR'd and parsed.
  **Expect:** events extracted (quality depends on the scan — flat, well-lit,
  straight-on works best).
- [ ] Also try **Upload from Photos** with a **photo of a syllabus** → same OCR
  path.
- [ ] Try **Enter Text Manually** → paste a few lines of syllabus text → it's
  turned into a PDF and parsed.

> Note: OCR is **not currently enabled on the production backend** (no
> `tesseract`/`poppler` binaries). Against production, a scanned-only PDF will
> return "Could not extract text from PDF". Test OCR against a **local** backend
> with `brew install tesseract poppler`.

### 2b. Upload guardrails & error paths

- [ ] Upload a **> 10 MB** PDF. **Expect:** "That file is X MB. Please upload a
  syllabus under 10 MB." (HTTP 413, no long spinner).
- [ ] Upload a PDF that is **not a syllabus** (e.g. a random article).
  **Expect:** "No events were found. Please ensure you are uploading a valid
  course syllabus and try again."
- [ ] With the backend **stopped**, upload something. **Expect:** a timeout
  message ("the server may be waking up… try again") rather than a hang or
  crash.

### 2c. Revoked / expired Google access

- [ ] While signed in, go to
  [myaccount.google.com/permissions](https://myaccount.google.com/permissions),
  find **Plannr**, and **Remove access**.
- [ ] Back in the app, trigger **any** backend action — re-sync a class, toggle
  class meetings, upload a syllabus, export, or just force-quit and relaunch (the
  launch `/me` check). Every one of these routes through `AuthManager.send`, so
  any of them catches the revoked token.
  **Expect:** you're **signed out** and land on the sign-in screen with
  **"Your Google session expired. Please sign in again."**
- [ ] Sign back in — everything works again.

### 2d. Local notifications

- [ ] Settings → Notifications **ON**, Deadline Reminders = **"Same day"**.
- [ ] Make sure a class has an event dated **tomorrow**.
- [ ] Change the event's reminder math to fire soon: easiest is to set Reminders
  to "Same day" and have an event **today** — the notification is scheduled for
  **9:00 AM** on the due date, so if it's before 9 AM you'll get it; otherwise
  temporarily edit `NotificationManager.schedule`'s hour, or just verify a
  request exists:
  ```
  In Xcode: pause the app, in the console run
  po try await UNUserNotificationCenter.current().pendingNotificationRequests()
  ```
  **Expect:** one pending request per upcoming event (up to **60** — the
  soonest ones), titled with the class name, body "… is due today" / "… is due
  in N days", ordered by fire date.
- [ ] Toggle notifications **off** → **Expect:** pending requests cleared.
- [ ] Background the app and bring it back to the foreground. **Expect:** the
  pending list is rebuilt (the "nearest 60" window is recomputed from now) —
  this is how reminders past the 64 cap eventually get scheduled. Selection math
  is covered by `NotificationManagerTests`.

### 2e. Landing page (`docs/`)

Open `docs/index.html` (locally: `python3 -m http.server` in `docs/`, then
visit `localhost:8000`).

- [ ] Page loads; on scroll the top nav **morphs into a floating pill**.
- [ ] Sections **fade/rise in** as they enter view.
- [ ] The **features** and **FAQ** accordions expand/collapse.
- [ ] The **"What's next"** ticker auto-scrolls, can be **dragged**, and
  includes a **"Canvas integration"** card. With the OS **Reduce Motion**
  setting on, it does **not** auto-scroll but is still draggable / scrollable.
- [ ] The **demo phone mockups** render crisply (no fuzzy text).
- [ ] **Privacy** and **Terms** links open; both show **"Last updated:
  August 30, 2026"** and contact **mattheweblanke@gmail.com**.
- [ ] "Get TestFlight Access" links to the Stripe payment link.

### 2f. TestFlight / Stripe flow (optional — needs Stripe test mode)

Follow the "Testing without real money" steps in `README.md`. Then:

- [ ] Pay with test card `4242 4242 4242 4242`. The redirect hits
  `/testflight/success?session_id=…`.
  **Expect:** a **"You're in!"** page with a **Join TestFlight** button (if
  `TESTFLIGHT_LINK` is set) — or "Payment confirmed! …still finishing setup".
- [ ] Visit `/testflight/success?session_id=bogus`.
  **Expect:** "We couldn't verify that" with the contact email.
- [ ] `stripe listen` window: **Expect:** a logged
  `TESTFLIGHT PAYMENT CONFIRMED` line (email masked).

### 2g. Backend directly (optional — `<backend>/docs`)

- [ ] `GET /me?email=you@example.com` for a signed-in user → 200 with name/pic;
  for an unknown email → 401.
- [ ] Hammer `POST /syllabus` >10×/min from one IP → **429** (rate limited).
- [ ] `DELETE /calendar?...&google_calendar_id=...` for a real calendar → 200
  and it's gone.
- [ ] `POST /calendar/visibility?email=...` with
  `{"google_calendar_id": "<real id>", "selected": false}` → 200
  `{"selected": false}` and 🔎 that calendar is unchecked in the sidebar; repeat
  with `true` to re-check it. A bogus calendar id → 200 `{"selected": ...,
  "skipped": true}` (not an error).

### 2h. Two Google accounts on one device (class scoping)

Needs a second Google account you can sign into.

- [ ] Signed in as **account A** with at least one class, note its name. Profile →
  **Sign Out**. Sign in as **account B**.
  **Expect:** **My Classes is empty** — B does not see A's classes.
- [ ] As B, add a class `B-only`. Sign out, sign back in as **A**.
  **Expect:** A sees its original class(es) and **not** `B-only`.
- [ ] Set a **custom profile photo** as A (Profile → tap avatar → pick an image).
  Sign out, sign in as B. **Expect:** B shows the Google photo, **not** A's custom
  one. Sign back in as A → the custom photo is still there.
- [ ] **Upgrade path:** on a build that already had classes from **before** this
  change, the first account you sign in as after updating keeps them; any *other*
  account signs in to an empty list. (One-time; can't be re-tested without
  reinstalling.)

---

## 3. Automated tests

- [ ] **Backend:**
  ```bash
  cd backend && source venv/bin/activate && python -m pytest -q
  ```
  **Expect:** all pass (OAuth signed-state, export, syllabus retry,
  `/syllabus` meeting-schedule pass-through, `/calendar/sync` patch-not-recreate,
  `/calendar/meetings` RRULE, `/calendar/visibility` check/uncheck).
- [ ] **iOS:** in Xcode press **Cmd+U**, or:
  ```bash
  xcodebuild test -project Plannr/Plannr.xcodeproj -scheme Plannr \
    -destination 'platform=iOS Simulator,name=iPhone 16'
  ```
  **Expect:** `PlannrTests` all pass (`EventReconcilerTests`,
  `ClassScheduleTests`, `CalendarPreviewViewTests`, `UnifiedEventMeetingTests`,
  `ParsedScheduleTests`, `ClassMeetingSyncTests`, `ClassManagerTests`
  per-account scoping + legacy migration, `AuthManagerDeleteAccountTests`
  retry + probe, `AuthManagerSendTests` 401 choke point,
  `NotificationManagerTests` nearest-60 selection, `TermSettingsTests`
  quarter/semester end date + auto label, `EventTypeTests` category
  normalization, `ClassSyncRequestTests` /calendar/sync body + response,
  `ParsePhaseTests` upload-phase timeline, `TermTests` + `TermStoreTests`
  term folders) and `PlannrUITests/GuestFlowUITests`.

---

## 4. Cleanup

- [ ] Delete the test classes in the app (this also removes their secondary
  Google Calendars).
- [ ] In Google Calendar, delete any leftover `CS 101` / `CS 101 (Section)`
  calendars or events.
- [ ] Re-grant Plannr access at
  [myaccount.google.com/permissions](https://myaccount.google.com/permissions)
  if you revoked it, or just sign in again.
- [ ] Profile → **Delete Account** to wipe the server record, or **Sign Out** to
  keep it. If you test Delete Account: confirm the dialog → **Expect:** you're
  signed out and, on a healthy backend, the server row is gone. (Stop the
  backend and try again → **Expect:** a "Couldn't Delete Account" alert and your
  data is **not** wiped locally.) The client retries the delete once and then
  probes `GET /me` before concluding failure, so a deletion whose response was
  lost to a timeout still ends up signed out with local data cleared —
  hard to reproduce by hand; covered by `AuthManagerDeleteAccountTests`.

---

## 5. Coverage checklist

| Feature | Tested in |
| --- | --- |
| Google sign-in (success / cancel / persistence / profile fetch) | §1A |
| Sign-in error surfacing | §1A (cancel), §2c |
| Guest mode + non-persistence + guest export | §1L |
| Classes + custom photo scoped per Google account (+ one-time migration) | §2h |
| Revoked-access sign-out (401 from any backend call) | §2c, §3 |
| Add class + color | §1B |
| Structured schedule picker (lecture + section) | §1B, §1H |
| Schedule auto-fill from syllabus (+ never overwrites a manual one) | §1H |
| Editable schedule after creation | §1H |
| My Classes list, badges, event counts | §1B, §1E |
| Delete class (+ its Google calendar) | §1M |
| Hamburger navigation + default-tab logic | §1I, §1J |
| Beta feedback — Report an Issue & Suggest a Feature (composer / fallback) | §1K |
| Upload: PDF / Photos / Manual text | §1C, §2a |
| Upload: camera scan + OCR | §2a |
| Upload guardrails (10 MB, not-a-syllabus, timeout) | §2b |
| AI extraction, type classification, relative dates | §1C |
| Calendar Preview grid (week/month), accept/decline, edit event | §1D |
| Class meetings shown (display-only) in the Calendar Preview grid (setting) | §1D |
| Export .ics / .csv (+ "no accepted events") | §1D |
| First sync → dedicated colored secondary calendar | §1E |
| Incremental re-upload (add/remove/update/move, no duplicates) | §1F |
| Preserve manual Google-side edits (patch not recreate) | §1F |
| Preserve local edits on re-upload | §1F |
| ClassEditView: edit / delete / undo / re-sync | §1G |
| Color change → live calendar re-color | §1G |
| End date + auto-INACTIVE | §1G |
| INACTIVE (auto & manual) → meetings pulled + calendar unchecked; ACTIVE re-checks | §1G, §1H |
| Sync Sessions history | §1G |
| Class meetings → recurring Google Calendar events (+ off / edit) | §1H |
| Unified Calendar (legend, grid, list scoped to visible week/month, detail sheet, deleted hidden) | §1I |
| Class meetings + final exam shown in Calendar list/grid (setting) | §1I, §1K |
| Week at a Glance (nav, filters, stats, overview, weekend preview) | §1J |
| Task completion + **persistence across relaunch** | §1J |
| "Class Meetings" display settings (Calendar + Week at a Glance toggles) + filter behavior | §1K |
| Profile photo (custom + remove) | §1K |
| Term folders: create/edit/delete, active-term switcher, per-class filing, Calendar/Week scoping, archive | §1K |
| Deadline reminder lead time | §1K, §2d |
| Auto-sync changes setting | §1K |
| Auto-sync class meetings setting (new/syllabus classes only) | §1K |
| Local notifications (schedule + clear + nearest-60 cap + foreground re-sync) | §2d, §3 |
| Delete Account (success + backend-failure guard + timeout retry/probe) | §4 |
| Landing page (nav, reveal, accordion, ticker, policies) | §2e |
| TestFlight / Stripe success + error pages + webhook | §2f |
| Rate limiting / backend endpoints (incl. `/calendar/visibility`) | §2g |
| Automated test suites | §3 |
