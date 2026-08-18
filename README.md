# Plannr

Plannr is an iOS app that parses course syllabi and syncs the important due dates — exams, homeworks, quizzes, and more — directly to a student's Google Calendar.

A student can:
- Upload syllabi as a PDF, camera scan, photo, or pasted text
- Review AI-extracted events and accept, decline, or edit them individually
- Assign each class a color that carries through to its Google Calendar
- Sync events to a dedicated per-class secondary Google Calendar
- Re-upload an updated syllabus and reconcile changes with existing events
- Export events as `.ics` or `.csv`
- Use the app in guest mode without signing in

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

## Prerequisites

- **Xcode 15+** (iOS 17+ SDK)
- **Python 3.10+**
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

The production database is a Render-managed PostgreSQL instance. The `render.yaml` at the repo root defines both the web service and the database.

> **Note:** The Render free tier spins down after 15 minutes of inactivity. The first request after a period of inactivity may take up to 30 seconds while the service wakes up.

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

Press `Cmd+R` to build and run on a simulator or device.

## How It Works

1. **Sign In** — Tap "Sign in with Google" to authenticate via OAuth. The backend stores your refresh token in PostgreSQL so future API calls can access your Calendar without re-authenticating.
2. **Add a Class** — Give it a name, schedule, and color.
3. **Upload Syllabus** — Upload a PDF, scan with the camera, pick from Photos, or paste text. The backend extracts text and sends it to Gemini, which returns a structured list of graded deliverables with inferred dates.
4. **Review Events** — Accept, decline, or edit each extracted event before syncing.
5. **Sync** — Tapping Sync creates a dedicated secondary Google Calendar for the class (named after it, colored to match) and pushes all accepted events as all-day events.
6. **Re-sync** — If you edit or delete events later, or upload a new syllabus, the app reconciles changes and pushes only the diff to Google Calendar.

## Project Structure

```
plannr/
├── Plannr/                  iOS Xcode project
│   └── Plannr/
│       ├── Config.swift     Backend URL — change this for production
│       ├── AuthManager.swift
│       ├── ClassManager.swift
│       └── ...
├── backend/
│   ├── app.py               FastAPI routes
│   ├── config.py            Typed settings via pydantic-settings
│   ├── db.py                SQLAlchemy engine + session
│   ├── models.py            ORM models (User, GoogleCredentials)
│   ├── repositories/
│   │   └── user_repository.py
│   ├── alembic/             Migration history
│   ├── alembic.ini
│   ├── requirements.txt
│   ├── .env.example
│   └── tests/
└── docs/
    ├── MANUAL.md
    ├── PRIVACY_POLICY.md
    └── TERMS_OF_SERVICE.md
```

## Running Tests

```bash
cd backend
source venv/bin/activate
pytest tests/ -v
```

## License

MIT — see [LICENSE.md](LICENSE.md).
