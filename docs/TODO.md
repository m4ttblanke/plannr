# Plannr — TODO

Working list of known problems and planned features. Last updated: September 3, 2026.

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

- Backend `/health` endpoint + an uptime monitor (also keeps the free dyno warm,
  which improves cold-start and OAuth reliability).
- Accessibility: further polish as it comes up. Done so far: `Color.secondaryText`
  (~4.8:1 on black) for captions; `accessibilityLabel`s on icon-only buttons;
  fixed fonts → scalable text styles with shrink-to-fit CTAs; calendar day
  cells are now scalable (bounded) and each is one VoiceOver button that speaks
  its date + event count; decorative art (brand, waves, dots, coach-mark chrome)
  hidden from VoiceOver; the coach-mark bubble and parse spinner read as single
  elements. Not done: a device VoiceOver run through every screen; localization.

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
