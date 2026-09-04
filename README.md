# Plannr

Plannr is an iOS app that parses course syllabi and syncs the important due dates — exams, homeworks, quizzes, and more — directly to a student's Google Calendar.

A student can:
- Upload syllabi as a PDF, camera scan, photo, or pasted text
- Review AI-extracted events and accept, decline, or edit them individually
- Assign each class a color that carries through to its Google Calendar
- Group classes into **term folders** (Quarter / Semester / Custom length)
- Sync events to a dedicated per-class secondary Google Calendar, plus recurring
  class-meeting events pulled from the syllabus
- Re-upload an updated syllabus and reconcile changes with existing events
- Roll a class back to any past sync from its history
- Export events as `.ics` or `.csv`
- Use the app in guest mode without signing in

First launch shows a 3-card walkthrough, and the empty state has a **Try a sample
syllabus** button — a guided, simulated run through the whole flow (no server
call, no calendar writes) so a new user sees how it works without hunting for a
PDF. Beta builds report crashes to Sentry.

Originally built as a class project at UC Santa Barbara. The original repository is at:
https://github.com/ucsb-cs148-w26/pj07-syllabus-to-cal-2pm

## Original Team

- Arya Sadeghi — @AryaSadeghi21
- Yuhang Jiang — @yuhangj554
- Divyani Punj — @divyanipunj
- Matt Blanke — @m4ttblanke
- Jiaming Liu — @iamjiamingliu
- Divya Subramonian — @divyagsubramonian
- Avaneesh Vinoth Kannan — @AvaneeshVinothK

## Tech Stack

- **Swift / SwiftUI** — iOS frontend
- **Python / FastAPI** — REST API backend
- **PostgreSQL** — persistent storage for user accounts and Google OAuth credentials
- **SQLAlchemy + Alembic** — ORM and database migrations
- **Google OAuth 2.0** — authentication and Calendar API access
- **Google Calendar API** — creating and syncing calendar events
- **Google Gemini** — AI-powered syllabus parsing
- **Stripe** — one-time payment gating access to the TestFlight demo
- **slowapi** — per-IP rate limiting on all backend endpoints
- **Sentry** (`sentry-cocoa`, SPM) — iOS crash reporting; inert unless a DSN is set
- **GitHub Actions** — a `/health` keep-warm ping so Render's free dyno doesn't cold-start
- **Cloudflare Web Analytics** — privacy-focused traffic/conversion tracking on the marketing site (no cookies, no user tracking)

## Prerequisites

- **Xcode 16+** (iOS 18 SDK; deployment target is iOS 18.0)
- **Python 3.12** (`backend/.python-version`)
- **PostgreSQL 14+** — `brew install postgresql@16 && brew services start postgresql@16`
- A **Google Cloud project** with these APIs enabled:
  - Google Calendar API
  - Google OAuth 2.0 (with an OAuth client of type **Web application**)
  - Gemini API
- A **Gemini API key** from [aistudio.google.com](https://aistudio.google.com)

### System dependencies (required for OCR fallback)

```bash
# macOS
brew install tesseract poppler

# Ubuntu/Debian
sudo apt-get install tesseract-ocr poppler-utils -y
```

## Deployment

The production backend is deployed on [Render](https://render.com) and is accessible at:

```
https://plannr-api.onrender.com
```

Deployment is automated — every push to `main` triggers a redeploy via `render.yaml`. The `alembic upgrade head` migration runs automatically on each deploy before the server starts.

The production database is a Render-managed PostgreSQL instance. The `render.yaml` at the repo root defines both the web service and the database, and sets `healthCheckPath: /health`.

`GET /health` returns `200` (with `database` / `ready` in the body) while the process is serving. `.github/workflows/keep-warm.yml` pings it every ~10 minutes so the free dyno doesn't cold-start — which also steadies the OAuth round-trip. See [`docs/OPS.md`](docs/OPS.md) for the endpoint, the workflow's caveats, and pointing a real uptime service (UptimeRobot / Better Stack) at the same URL.

> **Note:** The Render free tier still spins down after ~15 minutes with no traffic at all; the first request then takes up to ~30 seconds while the service wakes up.

## Local Development Setup

### 1. Clone the repo

```bash
git clone https://github.com/m4ttblanke/plannr.git
cd plannr
```

### 2. Create the database

```bash
createdb plannr
```

### 3. Set up the Python backend

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 4. Configure environment variables

```bash
cp .env.example .env
```

Edit `backend/.env` and fill in your values:

| Variable | Description |
|---|---|
| `GOOGLE_CLIENT_ID` | OAuth client ID from Google Cloud Console |
| `GOOGLE_CLIENT_SECRET` | OAuth client secret |
| `GOOGLE_REDIRECT_URI` | Must match a URI registered in Google Cloud Console. Use `http://localhost:8000/auth/callback` for local dev. |
| `GEMINI_API_KEY` | Gemini API key from AI Studio |
| `DATABASE_URL` | PostgreSQL connection string — e.g. `postgresql://your_macos_username@localhost:5432/plannr` |
| `STRIPE_SECRET_KEY` | Optional. Restricted key (`rk_...`) with "Checkout Sessions: Read" permission, from [dashboard.stripe.com/apikeys](https://dashboard.stripe.com/apikeys). Only needed to test the TestFlight payment flow. |
| `STRIPE_WEBHOOK_SECRET` | Optional. Signing secret (`whsec_...`) for the `/stripe/webhook` endpoint. |
| `TESTFLIGHT_LINK` | Optional. Public TestFlight join link from App Store Connect, revealed to customers after payment. |

### 5. Run database migrations

```bash
alembic upgrade head
```

### 6. Start the backend

```bash
uvicorn app:app --reload
```

The API will be available at `http://localhost:8000`. Interactive docs at `http://localhost:8000/docs`.

### 7. Open the iOS app

```bash
open ../Plannr/Plannr.xcodeproj
```

The backend URL is configured in `Plannr/Plannr/Config.swift`. Change it there to switch between local dev and production:

```swift
// Local dev
let BACKEND_URL = "http://localhost:8000/"

// Production
let BACKEND_URL = "https://plannr-api.onrender.com/"
```

The app links one Swift Package (**`sentry-cocoa`**, pinned in `Package.resolved`). Xcode resolves it on first open; if the build reports *"Missing package product 'Sentry'"*, run **File → Packages → Resolve Package Versions**. Crash reporting stays off until a DSN is set in `Plannr/Plannr/Info.plist` (`SENTRY_DSN`) — see [`docs/CRASH_REPORTING.md`](docs/CRASH_REPORTING.md).

Press `Cmd+R` to build and run on a simulator or device.

## How It Works

0. **First launch** — a 3-card walkthrough (upload → review → sync). New users can also tap **Try a sample syllabus** from the empty state for a guided, fully simulated run — no server call, no calendar writes — then delete the sample.
1. **Sign In** — Tap "Sign in with Google" to authenticate via OAuth. The backend stores your refresh token in PostgreSQL so future API calls can access your Calendar without re-authenticating.
2. **Add a Class** — Give it a name, schedule, color, and (optionally) a term folder.
3. **Upload Syllabus** — Upload a PDF, scan with the camera, pick from Photos, or paste text. The backend extracts text and sends it to Gemini, which returns a structured list of graded deliverables with inferred dates — plus meeting times, if the syllabus states them.
4. **Review Events** — Accept, decline, or edit each extracted event before syncing.
5. **Sync** — Tapping Sync creates a dedicated secondary Google Calendar for the class (named after it, colored to match) and pushes all accepted events as all-day events. Transient failures retry with backoff; anything still pending re-syncs automatically when the connection returns.
6. **Re-sync** — If you edit or delete events later, or upload a new syllabus, the app reconciles changes and pushes only the diff to Google Calendar. Every sync is snapshotted, and you can **restore** the class's events to any past one.

## TestFlight Access (Stripe)

The landing page (`docs/index.html`) has a "Get TestFlight Access" button that links to a Stripe Payment Link for a one-time payment. Two backend routes handle it:

- `GET /testflight/success` — the Payment Link's redirect target. Verifies the Checkout Session server-side and reveals the public TestFlight join link (`TESTFLIGHT_LINK`) only once payment is confirmed. This is UX only — customers aren't guaranteed to land here (they may close the tab after paying).
- `POST /stripe/webhook` — the source of truth for fulfillment. Verifies the event signature and handles `checkout.session.completed` / `checkout.session.async_payment_succeeded` (gated on `payment_status != 'unpaid'`).

Both the Payment Link and the webhook endpoint (Dashboard → Webhooks → pointed at `https://plannr-api.onrender.com/stripe/webhook`) are configured directly in the Stripe Dashboard — there's no code path that creates them.

### Testing without real money

Use Stripe's test mode (toggle in the Dashboard) — it's fully isolated from live mode and requires a separate test-mode product, Payment Link, and restricted key (`rk_test_...`).

```bash
brew install stripe/stripe-cli/stripe
stripe login
stripe listen --forward-to localhost:8000/stripe/webhook   # prints a temporary whsec_... — put it in .env as STRIPE_WEBHOOK_SECRET
```

Point your test Payment Link's redirect at `http://localhost:8000/testflight/success?session_id={CHECKOUT_SESSION_ID}` (keep the literal `{CHECKOUT_SESSION_ID}` placeholder — Stripe substitutes it), run the backend locally with the test-mode `STRIPE_SECRET_KEY`, then pay with card `4242 4242 4242 4242` (any future expiry/CVC/ZIP). No real charge occurs.

## Project Structure

```
plannr/
├── Plannr/                  iOS Xcode project (SwiftUI)
│   └── Plannr/
│       ├── Config.swift     Backend URL — change this for production
│       ├── Info.plist       CFBundleURLSchemes, SENTRY_DSN, UILaunchScreen
│       ├── AuthManager.swift ClassManager.swift SettingsManager.swift TermStore.swift
│       ├── SignInView.swift OnboardingView.swift PDFUploadView.swift
│       ├── SyllabusUploadView.swift CalendarPreviewView.swift ClassEditView.swift
│       ├── SampleTour.swift SampleSyllabus.swift  (guided sample walkthrough)
│       ├── ClassSyncRequest.swift ClassAutoResync.swift ClassRestore.swift EventReconciler.swift
│       ├── CrashReporting.swift NetworkMonitor.swift Haptics.swift Accessibility.swift AppColors.swift
│       └── ...
│   ├── PlannrTests/         XCTest unit suite
│   └── PlannrUITests/       GuestFlowUITests, OnboardingUITests
├── backend/
│   ├── app.py               FastAPI routes (incl. GET /health)
│   ├── config.py            Typed settings via pydantic-settings
│   ├── db.py                SQLAlchemy engine + session + ping()
│   ├── models.py            ORM models (User, GoogleCredentials)
│   ├── repositories/user_repository.py
│   ├── alembic/             Migration history
│   ├── requirements.txt  .env.example  .python-version
│   └── tests/
├── .github/workflows/
│   └── keep-warm.yml        pings /health every ~10 min
├── render.yaml              Render Blueprint (web service + Postgres)
└── docs/
    ├── index.html style.css site.js   Landing page
    ├── privacy.html terms.html + favicons, apple-touch-icon, PlannrDemo.mp4
    ├── MANUAL.md            User-facing feature manual
    ├── TEST_PLAN.md         Manual QA walkthrough + automated-test list
    ├── DEPLOY.md            Architecture, env vars, install, troubleshooting
    ├── OPS.md               /health + keep-warm + uptime monitoring
    ├── CRASH_REPORTING.md   Sentry setup (DSN, dSYMs)
    ├── COSTS.md  TODO.md
    └── PRIVACY_POLICY.md  TERMS_OF_SERVICE.md
```

## Running Tests

**Backend** (pytest):

```bash
cd backend && source venv/bin/activate
pytest tests/ -q
```

**iOS** (XCTest, on a simulator):

```bash
xcodebuild test -project Plannr/Plannr.xcodeproj -scheme Plannr \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Documentation

| File | What it covers |
|---|---|
| [`docs/MANUAL.md`](docs/MANUAL.md) | Every user-facing feature |
| [`docs/TEST_PLAN.md`](docs/TEST_PLAN.md) | Manual QA pass + the automated-test inventory |
| [`docs/DEPLOY.md`](docs/DEPLOY.md) | Architecture, environment variables, local setup, troubleshooting |
| [`docs/OPS.md`](docs/OPS.md) | `/health`, the keep-warm workflow, uptime monitoring |
| [`docs/CRASH_REPORTING.md`](docs/CRASH_REPORTING.md) | Sentry project + DSN + dSYM upload |
| [`docs/COSTS.md`](docs/COSTS.md) | Running-cost breakdown |
| [`docs/TODO.md`](docs/TODO.md) | What's left |

## License

MIT — see [LICENSE.md](LICENSE.md).
