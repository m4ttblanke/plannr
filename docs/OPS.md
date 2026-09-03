# Ops — health check & keeping the dyno warm

## `GET /health`

Always returns **200** while the process is serving. Body:

```json
{
  "status": "ok",
  "ready": true,
  "database": "ok",
  "uptime_seconds": 1234,
  "version": "a1b2c3d4e5f6",
  "time": "2026-09-03T20:00:00+00:00"
}
```

- `ready` / `database` — `false` / `"unavailable"` when the DB doesn't answer a
  `SELECT 1`. The HTTP status stays 200: the app tolerates a briefly-unreachable
  database (Render's free Postgres sleeps/restarts), so a nap must **not** make
  Render cycle the instance. Alert on the body if you want DB-down paging.
- `version` — `RENDER_GIT_COMMIT` (short) in production, `"dev"` locally.

`render.yaml` sets `healthCheckPath: /health` so Render's own checks use it.

## Keeping the free dyno warm

Render's free web service spins down after ~15 min idle; the next request eats a
~30–60 s cold start (which also makes the OAuth round-trip flaky). Pinging
`/health` on a schedule keeps it up.

### Built in: GitHub Actions (`.github/workflows/keep-warm.yml`)

Runs `curl $HEALTH_URL` every ~10 min and on manual dispatch; the run fails if
`/health` isn't 200, and warns if `database` is `"unavailable"`.

- Override the target with a repo **variable** `HEALTH_URL`
  (*Settings → Secrets and variables → Actions → Variables*); default is
  `https://plannr-api.onrender.com/health`.
- Caveats: scheduled workflows run only on the **default branch**, GitHub can
  delay them several minutes under load, and they **auto-disable after 60 days**
  of no repo activity — re-enable from the Actions tab.

### Recommended for real alerting: an uptime service

Free tier of any of these, 5-minute interval, pointed at `.../health`, alerting
on non-200 (and optionally on the string `"database": "unavailable"`):

- **UptimeRobot** — HTTP(s) monitor, keyword monitor for the DB string.
- **Better Stack (Better Uptime)** — similar, nicer incident UI.
- **cron-job.org** — bare scheduler if you only want the warm-up, no alerting.

Using one of these lets you drop or slow the GitHub Actions job.
