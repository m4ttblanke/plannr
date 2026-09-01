## **Description of Product Purpose**

Managing a course syllabus is one of the first challenges students face at the start of every semester/quarter. Each syllabus is packed with critical dates like assignment deadlines, exam schedules, quiz dates, and project milestones. Manually transferring all of that information into a calendar is time-consuming and prone to human error. A single missed entry can mean a missed deadline.

Plannr solves this problem by automatically parsing uploaded syllabi and converting all relevant dates and events into Google Calendar entries. Using text recognition and Google Gemini, Plannr identifies key academic events within a syllabus document and creates structured, color-coded calendar events. This means no copying, no manual entry, and no guesswork. Students simply upload their syllabus, and Plannr handles the rest, populating their Google Calendar with everything they need to stay on track throughout the semester/quarter.

## **Intended User Audience**

Plannr is designed for college and high school students who are managing the demands of multiple classes simultaneously. At any given time, a typical student may be juggling four to six courses, each with its own syllabus, grading timeline, and schedule of deadlines. Keeping track of it all manually is overwhelming and easy to get wrong.

Plannr is built for students who want to stay organized without spending hours setting up their calendar at the start of each term. Whether a student is trying to plan ahead for a heavy exam week, balance overlapping project deadlines, or simply avoid missing an assignment, Plannr gives them a clear, automated view of their academic schedule from day one. The app is especially valuable for students who are new to managing a heavy course load, though any student looking to focus more on their coursework will benefit.

## **Features**

### Sign In / Guest Mode

Users can sign in with their Google account to enable full calendar sync and persistent data storage. A Guest Mode is also available for users who want to try the app without signing in; classes and events created in guest mode are not saved between sessions, and Google Calendar sync is unavailable. Guests can still parse syllabi, review events, and export them as `.ics` or `.csv`.

If Google access is later revoked (for example, by removing the app from your Google Account settings), Plannr detects this on next launch, signs you out, and prompts you to sign in again.

<img src="MANUAL_IMAGES/login.png" alt="alt text" width="300">


### Add Classes

Users can add multiple classes and view their full class list on the home page. Each class can be assigned a custom color for easy visual identification across the calendar.

<img src="MANUAL_IMAGES/classes.png" alt="alt text" width="300">


### Upload Syllabi

Users can upload their syllabi in four ways: PDF file upload, camera document scanning, photo library import, or manual text paste. Scanned pages and photos are run through OCR (text recognition) automatically. All methods convert the input into a format ready for AI processing.

Notes:
- Uploads are limited to 10 MB. OCR reads at most the first 30 pages of a scanned document.
- Camera scanning requires a physical device (it is not available on the iOS Simulator) and camera permission.
- For scanned or photographed syllabi, clear, high-contrast, straight-on images produce the best results.

<img src="MANUAL_IMAGES/upload.png" alt="alt text" width="300">


### AI-Powered Event Extraction

Once a syllabus is uploaded, Plannr uses Google Gemini to intelligently parse the document and extract key academic dates. Events are automatically classified by type (homework, exam, quiz, lab, or other) and resolved to specific calendar dates, including relative references like "Week 3 Friday" or "Finals Week."

<img src="MANUAL_IMAGES/event_extraction.png" alt="alt text" width="300">


### Preview Calendar

Before syncing, users can review all extracted events in a calendar preview, and accept or decline each one. Events can be edited (title, date, type, description) or removed before they are added to Google Calendar. Synced events are created as all-day entries.

<img src="MANUAL_IMAGES/preview_calendar.png" alt="alt text" width="300">


### Edit Calendar Events
Users can edit any event after it has been parsed or synced. Changes made locally are preserved when re-uploading an updated syllabus, thanks to automatic event reconciliation.

<img src="MANUAL_IMAGES/edit_events1.png" alt="alt text" width="300">
<img src="MANUAL_IMAGES/edit_events2.png" alt="alt text" width="300">


### Calendar View

Plannr provides a weekly/monthly grid calendar showing all events from every class, color-coded by class for quick identification. Events can be filtered by type (homework, exam, quiz, lab, or all).

<img src="MANUAL_IMAGES/calendar.png" alt="alt text" width="300">


### Week at a Glance

The Week at a Glance view gives users a focused look at their upcoming week, surfacing all deadlines and events across classes in a single compact view. This makes it easy to anticipate heavy workload periods and plan accordingly.

<img src="MANUAL_IMAGES/week_at_a_glance.png" alt="alt text" width="300">


### Sync to Google Calendar

Users can push all parsed events to their Google Calendar with one tap. Plannr creates a dedicated secondary calendar for each class with a matching color. Re-syncing handles updates and deletions automatically.

### Export Events

Events can be exported as an iCal (.ics) file compatible with most calendar apps, or as a CSV spreadsheet for use in other tools. Export is available to signed-in users and guests alike.

<img src="MANUAL_IMAGES/export.png" alt="alt text" width="300">


### Profile & Settings

The profile screen (tap the avatar in the top-right of the home screen) collects account and preference options in one place:

- **Profile photo** — use your Google account photo, or pick a custom one from your photo library.
- **Current Term** — record a term label and start/end dates. This is informational only; it is not yet used to constrain parsing or auto-set class end dates.
- **Deadline Reminders** — choose how far ahead of a due date to be reminded (same day up to 7 days before, or leave it to Google Calendar's default). When events are synced, this reminder lead time is applied to the Google Calendar entries.
- **Notifications** — opt in to local reminder notifications on this device, scheduled from the reminder lead time above. These are separate from Google Calendar's own notifications and are limited to this device.
- **Sync** — enable *Auto-sync* to push edits to Google Calendar immediately instead of waiting for a manual re-sync. Not available in guest mode.
- **Sign Out** and **Delete Account**. Deleting an account removes the on-device data and asks the backend to delete the stored Google credentials.


## **Known Problems**

- The event type field (e.g. Homework, Exam, Lab, Quiz) is a free-text input rather than a dropdown menu, so values are not standardized.
- Very large syllabi with many deadlines can exceed what the parser handles in a single pass; the app will suggest splitting the document into smaller uploads.
- OCR of scanned or photographed syllabi depends on image quality — faint, skewed, or low-contrast scans may yield incomplete results. OCR is also not currently enabled on the production backend, so scanned-only PDFs may need to be uploaded as text-layer PDFs or pasted as text.
- The "Current Term" dates in Profile & Settings are recorded but not yet wired into parsing or class end dates.
- Local reminder notifications are capped by iOS at 64 pending notifications per app; students with a very large number of upcoming deadlines may not receive reminders for all of them.
