# Deployment & Environment Guide

**LIVE document.** This outlines the deployment architecture, system dependencies, and
environment setup for the Plannr iOS app and its FastAPI backend.

For a broader project overview and the fastest local setup, see the repo-root
[`README.md`](../README.md). This document focuses on deployment and operations.

## Table of Contents

- [1. System Architecture](#1-system-architecture)
  - [iOS Application (Frontend)](#ios-application-frontend)
  - [Python Backend (API)](#python-backend-api)
  - [Deployment Pipeline](#deployment-pipeline)
- [2. Prerequisites & Integrations](#2-prerequisites--integrations)
- [3. Environment Variables](#3-environment-variables)
- [4. Local Installation & Setup](#4-local-installation--setup)
  - [Option A: Client-Only (Recommended)](#option-a-client-only-recommended)
  - [Option B: Full-Stack Local Development](#option-b-full-stack-local-development)
- [5. Troubleshooting](#5-troubleshooting)

---

## 1. System Architecture

### iOS Application (Frontend)

Native SwiftUI app. No third-party package managers (no CocoaPods, no SPM
dependencies) — it uses only Apple frameworks (SwiftUI, AuthenticationServices,
VisionKit, PDFKit, PhotosUI, UserNotifications). Built and run from Xcode.

| Property | Value |
| --- | --- |
| Bundle identifier | `com.matthewblanke.plannr` |
| Custom URL scheme | `plannr://` (OAuth callback: `plannr://auth/callback`) |
| Minimum iOS version | 18.0 |
| Orientation | Portrait only (iPhone) |
| Apple Developer Team | `RJCYA2CC76` |
| Distribution | TestFlight, via App Store Connect |
| Backend URL | Hard-coded in `Plannr/Plannr/Config.swift` (`BACKEND_URL`) |

Permissions requested: **Camera** (`NSCameraUsageDescription`, for document
scanning). The photo picker uses `PHPickerViewController`, which is
out-of-process and needs no photo-library permission string.

### Python Backend (API)

RESTful API built with **FastAPI**, deployed on **[Render](https://render.com)**.

| Property | Value |
| --- | --- |
| Production URL | `https://plannr-api.onrender.com` |
| Interactive API docs | `https://plannr-api.onrender.com/docs` |
| Runtime | Python 3.12 (`backend/.python-version`) |
| Web server | `uvicorn` (single process) |
| Database | Render-managed PostgreSQL (`plannr-db`) |
| ORM / migrations | SQLAlchemy + Alembic |
| Rate limiting | `slowapi`, per-IP (100/min default; tighter per-route) |
| Plan | Free tier (spins down after ~15 min idle; first request after a
cold start can take ~30 s) |

**Data stored server-side:** only a user record (`email`, timestamps) and their
Google OAuth credentials (access token, refresh token, scopes). Classes, events,
and settings live entirely on-device in the iOS app — the backend is stateless
with respect to a user's syllabus data.

**OAuth state** is a signed, self-contained token (HMAC over the PKCE
`code_verifier` + timestamp, keyed from the Google client secret). There is no
server-side session store, so a redeploy or restart mid-login does not break the
flow, and the design is safe to run behind multiple instances.

### Deployment Pipeline

Deployment is defined by [`render.yaml`](../render.yaml) at the repo root (a
Render Blueprint) and is fully automated:

> **On every push to `main`,** Render pulls the latest source, runs the build
> command, then the start command. Database migrations run automatically on each
> deploy, before the server accepts traffic.

```yaml
rootDir:       backend
buildCommand:  pip install -r requirements.txt
startCommand:  alembic upgrade head && uvicorn app:app --host 0.0.0.0 --port $PORT --proxy-headers --forwarded-allow-ips='*'
```

`--proxy-headers --forwarded-allow-ips='*'` is required so per-IP rate limiting
sees the real client IP (from `X-Forwarded-For`) rather than Render's proxy.

There is **no GitHub Actions workflow** — Render's native GitHub integration is
the entire CD pipeline. There are no CI/CD repository secrets to configure;
all runtime configuration is Render environment variables (see below).

---

## 2. Prerequisites & Integrations

- **Xcode 16+** (iOS 18 SDK)
- **Python 3.12** and `pip`
- **PostgreSQL 14+** — e.g. `brew install postgresql@16 && brew services start postgresql@16`
- **Git**
- A **Google Cloud project** with:
  - Google Calendar API enabled
  - An OAuth 2.0 client of type **Web application**
  - Gemini API enabled
- A **Gemini API key** from [aistudio.google.com](https://aistudio.google.com)
- *(Optional, for the paid TestFlight flow)* a **Stripe** account

### System dependencies — OCR fallback

Scanned / image-only PDFs are run through OCR, which shells out to the
`tesseract` and `poppler` binaries (via `pytesseract` and `pdf2image`):

```bash
# macOS
brew install tesseract poppler

# Ubuntu / Debian
sudo apt-get install -y tesseract-ocr poppler-utils
```

> **Production note:** Render's native Python runtime does **not** include these
> binaries, and the repo has no `Aptfile` / Dockerfile that installs them. As a
> result, OCR of scanned PDFs will fail in production and the upload returns
> "Could not extract text from PDF". PDFs that contain a real text layer are
> unaffected (they use `PyPDF2`, no binaries needed). To enable OCR in
> production, add an `Aptfile` (`tesseract-ocr`, `poppler-utils`) or switch the
> service to a Docker deploy.

See [`backend/requirements.txt`](../backend/requirements.txt) for pinned Python
dependencies.

---

## 3. Environment Variables

All backend configuration is read from environment variables (locally via
`backend/.env`; see [`backend/.env.example`](../backend/.env.example)).

| Variable | Required | Description |
| --- | --- | --- |
| `GOOGLE_CLIENT_ID` | Yes | OAuth client ID from Google Cloud Console. |
| `GOOGLE_CLIENT_SECRET` | Yes | OAuth client secret. Also the key material for signing OAuth `state`. |
| `GOOGLE_REDIRECT_URI` | Yes | Must exactly match a redirect URI registered on the OAuth client. Production: `https://plannr-api.onrender.com/auth/callback`. Local: `http://localhost:8000/auth/callback`. |
| `GEMINI_API_KEY` | Yes* | Gemini API key. If unset, `/syllabus` returns a "not configured" error. |
| `DATABASE_URL` | Yes | PostgreSQL connection string. On Render this is wired automatically from the `plannr-db` database. |
| `STRIPE_SECRET_KEY` | No | Restricted key (`rk_...`) with "Checkout Sessions: Read". Needed only for the TestFlight payment flow. |
| `STRIPE_WEBHOOK_SECRET` | No | Signing secret (`whsec_...`) for `POST /stripe/webhook`. |
| `TESTFLIGHT_LINK` | No | Public TestFlight join link, revealed to customers after a confirmed payment. |

\* Not required for the app to boot, but syllabus parsing (the core feature)
does not work without it.

### Setting them on Render

`render.yaml` declares every variable above with `sync: false` (except
`DATABASE_URL`, which is bound to the managed database). `sync: false` means
Render will **not** read a value from the blueprint — you must set each one in
the Render dashboard (**Service → Environment**) or during Blueprint creation.
A missing `STRIPE_*` / `TESTFLIGHT_LINK` degrades gracefully: `/testflight/success`
and the webhook report "not configured" instead of crashing.

### Upload guardrails (not configurable)

Defined as constants in `backend/app.py`:

- `MAX_SYLLABUS_BYTES` — 10 MB. Larger uploads are rejected with HTTP 413 before
  being read into memory.
- `MAX_OCR_PAGES` — 30. OCR processes at most the first 30 pages of a scanned PDF.

---

## 4. Local Installation & Setup

### Option A: Client-Only (Recommended)

*Use this if you are working on the iOS UI and are happy to consume the live
production API.*

1. **Clone and open:**
   ```bash
   git clone https://github.com/m4ttblanke/plannr.git
   cd plannr
   open Plannr/Plannr.xcodeproj
   ```
2. **Confirm the backend URL.** `Plannr/Plannr/Config.swift` should already point
   at production:
   ```swift
   let BACKEND_URL = "https://plannr-api.onrender.com/"
   ```
3. **Build and run:** select a simulator or device and press `Cmd + R`.

Sign-in, syllabus parsing, and Google Calendar sync all work against the live
backend. (Guest mode needs no backend for anything except export.)

### Option B: Full-Stack Local Development

*Use this if you are changing backend behavior or API responses.*

#### Part 1 — Backend

```bash
git clone https://github.com/m4ttblanke/plannr.git
cd plannr/backend

python3 -m venv venv
source venv/bin/activate            # Windows: venv\Scripts\activate
pip install -r requirements.txt

createdb plannr                     # PostgreSQL must be running

cp .env.example .env                # then edit .env — see section 3
```

Set `GOOGLE_REDIRECT_URI=http://localhost:8000/auth/callback` in `.env` **and**
register that exact URI on your Google Cloud OAuth client.

Run migrations, then start the server:

```bash
alembic upgrade head
uvicorn app:app --host 0.0.0.0 --port 8000 --reload
```

The API is now at `http://localhost:8000`, docs at `http://localhost:8000/docs`.

#### Part 2 — Point the iOS app at localhost

Edit the single constant in `Plannr/Plannr/Config.swift`:

```swift
// Local dev
let BACKEND_URL = "http://localhost:8000/"

// Production
// let BACKEND_URL = "https://plannr-api.onrender.com/"
```

`BACKEND_URL` is the **only** place the backend host is configured — every
network call in the app reads it. Then open `Plannr/Plannr.xcodeproj` and press
`Cmd + R`.

> A simulator can reach `http://localhost:8000` directly. A physical device
> cannot — use your Mac's LAN IP (`http://192.168.x.x:8000/`) and make sure both
> devices are on the same network.

#### Part 3 — (Optional) Stripe test mode

See the **TestFlight Access (Stripe)** section of the repo-root `README.md` for
the `stripe listen` / test-card walkthrough.

---

## 5. Troubleshooting

### Backend

- **`ModuleNotFoundError: No module named 'fastapi'`** — the virtualenv is not
  activated, or dependencies aren't installed. Run `source venv/bin/activate`,
  then `pip install -r requirements.txt`.

- **`[Errno 48/98] Address already in use`** — port 8000 is taken. Kill the
  process (`lsof -i :8000` then `kill -9 <PID>`) or use another port. If you
  change the port, update `BACKEND_URL` in `Config.swift` to match.

- **App fails to start / boot logs show a database error** — the startup
  connectivity check now logs a warning and continues instead of crashing, and
  `pool_pre_ping` reconnects per request. Confirm PostgreSQL is running and
  `DATABASE_URL` is correct; run `alembic upgrade head` if the schema is missing.

- **`sqlalchemy ... relation "users" does not exist`** — migrations haven't run.
  `alembic upgrade head`.

- **Syllabus upload returns "Gemini API key not configured"** — `GEMINI_API_KEY`
  is unset in the environment the server actually loaded.

- **Syllabus upload returns "Could not extract text from PDF" for a scanned
  document** — OCR needs the `tesseract` and `poppler` binaries. Locally,
  `brew install tesseract poppler`. In production, see the OCR note in
  section 2. Text-layer PDFs are unaffected.

- **Upload returns HTTP 413** — the file exceeds `MAX_SYLLABUS_BYTES` (10 MB).

- **OAuth callback shows "Invalid or expired sign-in session"** — the signed
  `state` failed verification. Causes: more than 5 minutes elapsed between
  starting sign-in and the callback; `GOOGLE_CLIENT_SECRET` differs between the
  instance that issued `state` and the one handling the callback; or the
  callback URL was tampered with.

- **`redirect_uri_mismatch` from Google** — `GOOGLE_REDIRECT_URI` does not
  exactly match a URI registered on the OAuth client (scheme, host, port, path,
  trailing slash all matter).

- **Stripe webhook returns "Invalid signature"** — `STRIPE_WEBHOOK_SECRET` does
  not match the endpoint's signing secret. In local dev, use the `whsec_...`
  that `stripe listen` prints.

### iOS / Frontend

- **Build fails with an SDK or Swift-version error** — use Xcode 16+ (iOS 18
  SDK). Deployment target is iOS 18.0.

- **"Sign in with Google" opens then immediately returns an error** — the app
  now surfaces the backend's error message on the sign-in screen. Check the
  backend logs for the underlying OAuth failure (usually `redirect_uri_mismatch`
  or a bad client secret).

- **App drops back to the sign-in screen with "Your Google session expired"** —
  expected behavior when the stored refresh token has been revoked (e.g. the
  user removed the app in their Google Account settings). Sign in again.

- **Calendar sync fails on a physical device against a local backend** — the
  device can't resolve `localhost`. Use your Mac's LAN IP in `Config.swift`.

- **Camera scan option is missing or crashes** — `VNDocumentCameraViewController`
  is unsupported on the simulator; test document scanning on a real device.
