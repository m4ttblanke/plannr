# Campaign links — copy & paste

*Last updated: September 9, 2026.*

Ready-to-use URLs for the **free TestFlight beta** launch. Every link points at
the landing page with UTM tags; the "Join the Free Beta" button carries those
tags to `/go/beta.html` (a Cloudflare pageview) and then on to Plannr's
TestFlight invitation. Full explanation, conventions, and what can / can't be
measured: **`ANALYTICS.md`**.

Rules of thumb:

- Always link to `https://tryplannr.app/?utm_...` — never straight to
  `/go/beta.html` or `testflight.apple.com`.
- Lowercase values; letters, digits, `_` only (hyphens are fine too).
- One `utm_campaign` = one campaign. Don't reuse `beta_launch` for a later push;
  date-stamp instead (e.g. `finals_week_2026`).
- Extra params a platform tacks on (`fbclid`, `igshid`, …) are harmless — the
  page ignores them.

---

## Clean public links (preferred for sharing)

Two short URLs that look tidy in a post or a bio and expand to the full UTM
landing URL. They redirect **to the landing page** (not to TestFlight); the
`Join the Free Beta` CTA then carries the UTMs onward exactly as it does for a
hand-built link. Attribution values are **fixed** — anything you append to
`/linkedin` or `/instagram` is ignored.

| Share this | It redirects to |
| --- | --- |
| **`https://tryplannr.app/linkedin`** — LinkedIn personal launch post | `https://tryplannr.app/?utm_source=linkedin&utm_medium=post&utm_campaign=beta_launch` |
| **`https://tryplannr.app/instagram`** — Instagram bio | `https://tryplannr.app/?utm_source=instagram&utm_medium=bio_link&utm_campaign=beta_launch` |

Implemented as static pages: `docs/linkedin/index.html`, `docs/instagram/index.html`
(`location.replace()` + `<meta http-equiv="refresh">` fallback + a visible link).
For any other placement, build a full UTM URL from the cookbook below.

---

## Launch campaign — `utm_campaign=beta_launch`

### Instagram — bio link
Profile "link in bio" (or the destination of the beta button in a link-in-bio tool).
Prefer the clean alias **`https://tryplannr.app/instagram`**, which redirects to:

```
https://tryplannr.app/?utm_source=instagram&utm_medium=bio_link&utm_campaign=beta_launch
```

### Instagram — story link sticker
Paste as the sticker URL. Add `utm_content` per creative if you run more than one.

```
https://tryplannr.app/?utm_source=instagram&utm_medium=story&utm_campaign=beta_launch&utm_content=story_1
```

### Instagram — paid ad
Set as the ad's destination / website URL. Give each ad set or creative its own `utm_content`.

```
https://tryplannr.app/?utm_source=instagram&utm_medium=ad&utm_campaign=beta_launch&utm_content=ad_set_a
```

### LinkedIn — post
A personal or company post / comment. Prefer the clean alias
**`https://tryplannr.app/linkedin`**, which redirects to:

```
https://tryplannr.app/?utm_source=linkedin&utm_medium=post&utm_campaign=beta_launch
```

### Discord / community
A server message, pinned link, or community newsletter. Swap `utm_source` for
other communities (`reddit`, `slack`, `groupme`, …); use `utm_medium=dm` for a
direct message.

```
https://tryplannr.app/?utm_source=discord&utm_medium=post&utm_campaign=beta_launch
```

### Physical flyer / poster QR code
Generate the QR straight from this URL with any offline generator (no
third-party shortener). Set `utm_source` to where the flyer lives
(`flyer`, `poster`, `library`, `career_fair`, …). Test-scan before printing.

```
https://tryplannr.app/?utm_source=flyer&utm_medium=qr&utm_campaign=beta_launch
```

---

## Template for a new campaign

Replace `<...>` and keep a note of every link you hand out.

```
https://tryplannr.app/?utm_source=<where>&utm_medium=<placement>&utm_campaign=<name>[&utm_content=<variant>]
```

| Field | Pick from |
| --- | --- |
| `utm_source` | `instagram`, `tiktok`, `reddit`, `discord`, `x`, `email`, `flyer`, `poster` |
| `utm_medium` | `bio_link`, `story`, `post`, `dm`, `ad`, `social`, `email`, `print`, `qr` |
| `utm_campaign` | short, lowercase, unique per push — e.g. `finals_week_2026` |
| `utm_content` | optional A/B or creative tag — `video_a`, `carousel_b` |

---

## Reading results (quick version)

- **Visits** → Cloudflare Web Analytics, filter to the campaign window; check
  Referrers and the `utm_*` in the page path.
- **CTA clicks** → Cloudflare, count `/go/beta.html` pageviews for the window
  (a floor, not exact — see `ANALYTICS.md`).
- **Installs** → App Store Connect → TestFlight (aggregate only; Apple gives no
  per-campaign breakdown).
- **Spend / CAC** → track spend yourself, one row per campaign.
