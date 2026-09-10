# Ops — health check & uptime monitoring

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
  database (a restart, failover, or transient network blip), so a nap must
  **not** make Render cycle the instance. Alert on the body if you want DB-down
  paging.
- `version` — `RENDER_GIT_COMMIT` (short) in production, `"dev"` locally.

`render.yaml` sets `healthCheckPath: /health` so Render's own checks use it.

## Keeping the service warm (safety net)

The web service is on a paid Render tier now, so it **no longer spins down on
idle** and there's no ~30–60 s cold start. The scheduled `/health` ping below is
kept as a low-cost early-warning signal (service or DB not answering), not
because the instance sleeps.

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
