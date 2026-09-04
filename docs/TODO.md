# Plannr — TODO

Working list of known problems and planned features. Last updated: September 3, 2026.

Pre-launch polish is done (onboarding, sample-syllabus tour, crash reporting,
sync resilience + auto-resync, restore a sync session, haptics, launch screen,
accessibility first pass, `/health` + keep-warm).

This file was refreshed after a full walk of the repo (iOS app, FastAPI backend,
Alembic schema, Render config, GitHub Actions, marketing site). Backend test
suite passes locally: **92/92 pytest** (via `backend/venv`); the iOS `PlannrTests`
suite passes via `xcodebuild test`. Findings below are ordered by severity.

---

## P1 — must fix before any real launch

### Security

- ~~**Backend endpoints have no request authentication — they trust a plaintext
  `email` query parameter.**~~ **FIXED (2026-09-03).** Every per-user endpoint
  (`/me`, `/calendar/sync`, `/calendar/meetings`, `/calendar/visibility`,
  `DELETE /calendar`, `DELETE /account`) now requires an opaque session token as
  `Authorization: Bearer <token>`, verified against
  `google_credentials.session_token` (constant-time). The token is minted/rotated
  in `/auth/callback` and delivered to the app on the `plannr://auth/callback`
  redirect. `email` is now just an identifier. Migration `92c09a31fa6e` adds the
  column (nullable → existing users re-auth once). See `require_account` in
  `backend/app.py` and `docs/DEPLOY.md` § Request authentication.

- ~~**The OAuth callback deep link is not bound to the device that started the
  flow.**~~ **FIXED (2026-09-03).** The app now generates a one-time 244-bit
  `nonce` in `getGoogleAuthURL()`, sends it to `/auth/google?nonce=`, the backend
  seals it into the signed `state` (`decode_oauth_state`) and echoes it on the
  `plannr://auth/callback` redirect, and `AuthManager.handleCallback` rejects any
  callback whose `nonce` doesn't match the stored one (consumed one-shot). A
  `plannr://auth/callback` the app never started is now rejected even with a
  valid-looking `email` + `token`. Residual (accepted): an attacker who can
  *observe* the real `/auth/google` request AND intercept the custom-scheme
  callback could still replay — inherent to custom-scheme OAuth; a universal-link
  (`https://`) callback would close it.

- ~~**Google OAuth tokens are stored in plaintext.**~~ **FIXED (2026-09-03).**
  `access_token` / `refresh_token` are now Fernet-encrypted by the backend
  (`backend/crypto.py`) before storage, keyed by `TOKEN_ENC_KEY` (one or more
  keys → rotation supported). Ciphertext is `enc:v1:`-prefixed; legacy plaintext
  rows are read transparently and rewritten encrypted on next sign-in, so no data
  migration is needed. The session bearer token is no longer stored reversibly
  either — only its SHA-256 hash. `TOKEN_ENC_KEY` must be set in production (unset
  → plaintext + startup warning). Landing-page and privacy-policy copy updated to
  state at-rest encryption accurately. **Not covered:** `TOKEN_ENC_KEY` itself
  lives in Render env vars alongside the DB URL, so a full-host compromise still
  exposes both — a managed KMS/HSM would separate them.

### Correctness

- ~~**The Gemini model id `gemini-3.7-flash` is almost certainly not a real
  model.**~~ **NOT A BUG (2026-09-03).** The original claim was wrong — it came
  from a Jan-2026 knowledge cutoff; "Gemini 3.7 Flash" shipped since. Verified
  live against the app's own key/SDK: `client.models.get('gemini-3.7-flash')` →
  `models/gemini-3.7-flash` (1,048,576-token input limit), and it's in the key's
  model list next to `gemini-3.5/3.6/3.8-flash`. AI Studio → Rate Limit (Plannr
  project) also shows non-zero 28-day usage for it, so `/syllabus` has been
  parsing fine in prod. No code change needed. *Nice-to-have:* a non-mocked
  smoke test in CI so a future model rename can't silently break parsing.

### Deploy

- **OCR is not enabled in production** — *no longer a launch blocker (2026-09-03).*
  The Render Python runtime (`env: python` in `render.yaml`) has no `tesseract` /
  `poppler` binaries and there's no `Aptfile` / Dockerfile, so image-only PDFs
  (camera scans, photo uploads) can't be parsed server-side. **Mitigation:**
  `SyllabusUploadView` now shows a "Camera support coming soon!" alert for both
  the *Scan Document* and *Upload from Photos* options instead of uploading an
  image the server can't read — so the only broken path is gated, not surfaced as
  a raw error. The scan/photo plumbing (`DocumentScanner`, `ImagePicker`,
  `convertImagesToPDFAndUpload`) is left intact for easy re-enable.
  **To actually ship the feature:** add `backend/Aptfile` (`tesseract-ocr`,
  `poppler-utils`) or a Docker deploy, then flip the two buttons back. Text-layer
  PDFs and pasted text are unaffected and work today.

---

## P2 — address before scaling / marketing push

- ~~**No CI.**~~ **FIXED (2026-09-03).** Added
  [`.github/workflows/ci.yml`](../.github/workflows/ci.yml): a `backend` job
  (`pip install` + `alembic upgrade head` + `pytest` against a disposable
  `postgres:16` service — also smoke-tests the migrations) and an `ios` job
  (`xcodebuild test` on `macos-15` running `PlannrTests` + `PlannrUITests` with
  `-retry-tests-on-failure`, xcresult uploaded on failure). Runs on push to
  `main` and every PR; needs no secrets. Backend job verified locally with a
  CI-style env (no `.env`, config from env vars): 92/92. Follow-ups: (a) make the
  jobs **required status checks** in branch protection so they actually gate
  merges; (b) the `ios` job may need a `-destination` tweak on first run
  depending on the runner's simulator lineup (deployment target is iOS 18.5); (c)
  optional `paths-ignore: ['docs/**','**/*.md']` if the macOS runner minutes add
  up.

- ~~**Render free PostgreSQL is time-limited and can be deleted.**~~ **FIXED
  (2026-09-03).** The `plannr-db` database was upgraded to the paid
  **`basic-256mb`** plan ($6/mo, 0.1 CPU / 256 MB / 1 GB storage) — durable, not
  time-limited, and it now gets **automatic daily backups**. `render.yaml` and
  `docs/COSTS.md` updated to match. Follow-ups: (a) confirm the backup retention
  window on the DB's Recovery page in the Render dashboard, and consider an
  external `pg_dump` cron for off-Render redundancy; (b) if a blueprint sync ever
  rejects `plan: basic-256mb`, check the exact plan slug on the DB's Settings
  page (Render has renamed Postgres plans over time). The **web service** is
  still `plan: free` (cold-starts) — separate, lower-priority cost decision.

- ~~**Internal ops docs are published by the public site.**~~ **FIXED
  (2026-09-03).** Added [`docs/_config.yml`](_config.yml) with a Jekyll
  `exclude:` list covering every internal doc in `docs/` (`DEPLOY.md`,
  `COSTS.md`, `OPS.md`, `TEST_PLAN.md`, `MANUAL.md`, `TODO.md`,
  `CRASH_REPORTING.md`, `MANUAL_IMAGES/`, and the `*_POLICY.md` /
  `*_OF_SERVICE.md` sources). GitHub Pages runs Jekyll by default, so those files
  now 404 on the published site while staying exactly where they are in the repo
  — no files moved, no README/cross-links broken, no Pages *setting* change
  needed (branch Pages only allows `/` or `/docs` anyway, so a `web/` folder
  wasn't an option without a custom Actions deploy). New internal docs must be
  added to the `exclude:` list; a `docs/.nojekyll` must never be added. Verify
  after the next deploy: `curl -so /dev/null -w '%{http_code}' https://<site>/DEPLOY.md`
  → `404`.

- **`docs/PlannrDemo.mp4` (≈22 MB) is committed to git.** It inflates every clone
  and every CI checkout. Move it to Git LFS or host it externally and reference a
  URL.

---

## P3 — cleanup / lower risk

- **Dead token-expiry plumbing.** `google_credentials.expires_at` (column +
  migration) is never written or read, and `_build_credentials` constructs
  `Credentials` with `expiry=None`. It still works — `google-auth-httplib2`
  refreshes on a 401 and retries — but every call after the ~1 h access-token TTL
  pays an extra refresh round-trip and the refreshed token is never persisted.
  Either persist refreshed tokens (`credentials.refresh(...)` + `upsert`) or drop
  the unused column.

- **`PyPDF2` is deprecated** (raises a `DeprecationWarning` on import). Migrate to
  `pypdf`.

- **Mixed dependency pinning in `backend/requirements.txt`.** Some deps are `==`
  pinned, others `>=`; `stripe>=11.0.0` currently resolves to 15.x and
  `google-genai>=1.0.0` to 2.x. Pin exact versions so a redeploy can't silently
  pick up a breaking release.

- **`render.yaml` uses the deprecated `env:` key** (Render now expects
  `runtime:`). Works today; update opportunistically.

- **`/auth/callback` declares an unused `redirect_to_app` query param** — the
  handler always redirects to the `plannr://` scheme. Remove it or implement it.

- **`initialize()` is duplicated.** `db.verify_connection()` and
  `repositories.user_repository.initialize()` are the same `SELECT 1` + `print`.
  Consolidate to one.

- **Verify the public GitHub URL.** The landing page links
  `https://github.com/m4ttblanke/plannr`; confirm that repo exists and is public
  (the README points contributors at the original UCSB class repo instead), or
  the footer link 404s.

- **`/health` could report launch-readiness of optional integrations.** The app
  boots fine with `GEMINI_API_KEY` / `STRIPE_SECRET_KEY` unset and only errors
  per-request; surfacing `gemini: unconfigured` / `stripe: unconfigured` in the
  `/health` body would make a misconfigured deploy obvious.

---

## Product roadmap (from the landing page "What's next")

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
