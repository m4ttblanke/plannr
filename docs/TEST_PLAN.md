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
    from Word/Google Docs, not a scan). 6–15 dated items.
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
  **Expect:** "Processing..." spinner with the "can take up to a minute" note.
  (First request after an idle Render dyno really can take ~30 s.)
- [ ] **Expect:** you land on the **Calendar Preview** with a list of extracted
  events, each auto-**Accepted**, tagged by type (homework/exam/quiz/lab/other),
  and dates resolved (including any relative ones like "Week 3 Friday").

### D. Calendar Preview — edit, grid, export

- [ ] Toggle the **Week / Month** picker at the top; tap a day with a dot.
  **Expect:** the grid switches and the day's events show below.
- [ ] On one event tap **Edit** → change the **Title** and **Description**,
  spin the **Date** wheel forward a day, **Save Changes**.
  **Expect:** the card reflects the new title/date/description.
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

- [ ] In the class edit screen, the schedule row shows
  `MWF 10:00 AM · Section Th 3:00 PM`. Tap **Edit** next to it → the schedule
  picker opens inline; change the class time to **11:00 AM** → tap **Done**.
  **Expect:** the row text updates.
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
- [ ] **Current Term:** type a label ("Fall 2026"); set **Start date** and
  **End date**. (These feed the class-meeting recurrence window — re-toggle a
  class's meetings after setting them to see the recurrence end change.)
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
- [ ] **Notifications → Deadline reminders:** turn ON → grant the permission
  prompt. (If you deny it, **Expect:** a "Notifications Disabled" alert.)
- [ ] **Report an issue path** (also reachable from the hamburger menu):
  hamburger → **Report an Issue**.
  **Expect:** a mail composer prefilled **To: mattheweblanke@gmail.com**,
  subject **"Plannr Beta — Issue Report"**, body with a prompt + your app
  version / iOS version / device. (On a Simulator with no Mail account you may
  get the "email mattheweblanke@gmail.com" alert instead — that's the fallback.)
  Cancel out of the composer.

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
- [ ] Back in the app, trigger any synced action (open a class and **Re-sync**,
  or just **force-quit and relaunch** — the launch `/me` check catches it).
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
  **Expect:** one pending request per upcoming event, titled with the class
  name, body "… is due today" / "… is due in N days".
- [ ] Toggle notifications **off** → **Expect:** pending requests cleared.

### 2e. Landing page (`docs/`)

Open `docs/index.html` (locally: `python3 -m http.server` in `docs/`, then
visit `localhost:8000`).

- [ ] Page loads; on scroll the top nav **morphs into a floating pill**.
- [ ] Sections **fade/rise in** as they enter view.
- [ ] The **features** and **FAQ** accordions expand/collapse.
- [ ] The **"What's next"** ticker auto-scrolls, can be **dragged**, and
  includes a **"Canvas integration"** card.
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

---

## 3. Automated tests

- [ ] **Backend:**
  ```bash
  cd backend && source venv/bin/activate && python -m pytest -q
  ```
  **Expect:** all pass (OAuth signed-state, export, syllabus retry,
  `/calendar/sync` patch-not-recreate, `/calendar/meetings` RRULE,
  `/calendar/visibility` check/uncheck).
- [ ] **iOS:** in Xcode press **Cmd+U**, or:
  ```bash
  xcodebuild test -project Plannr/Plannr.xcodeproj -scheme Plannr \
    -destination 'platform=iOS Simulator,name=iPhone 16'
  ```
  **Expect:** `PlannrTests` all pass (`EventReconcilerTests`,
  `ClassScheduleTests`, `CalendarPreviewViewTests`, `UnifiedEventMeetingTests`)
  and `PlannrUITests/GuestFlowUITests`.

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
  data is **not** wiped locally.)

---

## 5. Coverage checklist

| Feature | Tested in |
| --- | --- |
| Google sign-in (success / cancel / persistence / profile fetch) | §1A |
| Sign-in error surfacing | §1A (cancel), §2c |
| Guest mode + non-persistence + guest export | §1L |
| Revoked-access sign-out | §2c |
| Add class + color | §1B |
| Structured schedule picker (lecture + section) | §1B, §1H |
| Editable schedule after creation | §1H |
| My Classes list, badges, event counts | §1B, §1E |
| Delete class (+ its Google calendar) | §1M |
| Hamburger navigation + default-tab logic | §1I, §1J |
| Report an Issue (mail composer / fallback) | §1K |
| Upload: PDF / Photos / Manual text | §1C, §2a |
| Upload: camera scan + OCR | §2a |
| Upload guardrails (10 MB, not-a-syllabus, timeout) | §2b |
| AI extraction, type classification, relative dates | §1C |
| Calendar Preview grid (week/month), accept/decline, edit event | §1D |
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
| Current Term settings (feeds meeting recurrence) | §1K, §1H |
| Deadline reminder lead time | §1K, §2d |
| Auto-sync setting | §1K |
| Local notifications (schedule + clear) | §2d |
| Delete Account (success + backend-failure guard) | §4 |
| Landing page (nav, reveal, accordion, ticker, policies) | §2e |
| TestFlight / Stripe success + error pages + webhook | §2f |
| Rate limiting / backend endpoints (incl. `/calendar/visibility`) | §2g |
| Automated test suites | §3 |
