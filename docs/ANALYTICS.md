# Analytics & campaign attribution

*Last updated: September 9, 2026.*

Plannr's measurement stack is deliberately small: **Cloudflare Web Analytics**
for website traffic, **App Store Connect / TestFlight** for beta tester numbers,
and **UTM tags** on campaign links. No GA4, no PostHog, no Segment, no cookies,
no fingerprinting, no extra analytics dependency.

## The funnel

```
campaign link                     ← you build these, with utm_* tags
 [ /linkedin or /instagram ]      ← optional clean alias → 302s to the tagged landing URL
  → https://tryplannr.app/?utm_*  ← landing page  (Cloudflare counts the visit)
  → "Join the Free Beta"          ← 3 CTAs: nav, hero, final
  → /go/beta.html?utm_*           ← redirect page (Cloudflare counts the CTA click)
  → https://testflight.apple.com/join/8q3eFC8d
  → TestFlight                    ← App Store Connect counts installs / sessions
```

The beta is **free**. Nothing on this path touches Stripe or the backend — the
redirect pages are static files on GitHub Pages.

### Clean-alias entry redirects

`/linkedin` and `/instagram` are static pages (`docs/linkedin/index.html`,
`docs/instagram/index.html`) that immediately `location.replace()` to the
landing page with **fixed** UTM tags (with a `<meta http-equiv="refresh">`
fallback and a visible link). They land the visitor on `/?utm_*` — **not** on
`/go/beta.html` or TestFlight — so `site.js` picks the tags up exactly as it
would for a hand-built link.

| Clean URL | Redirects to |
| --- | --- |
| `https://tryplannr.app/linkedin` | `https://tryplannr.app/?utm_source=linkedin&utm_medium=post&utm_campaign=beta_launch` |
| `https://tryplannr.app/instagram` | `https://tryplannr.app/?utm_source=instagram&utm_medium=bio_link&utm_campaign=beta_launch` |

The measurement chain is therefore:

```
/linkedin  → /?utm_source=linkedin&utm_medium=post&utm_campaign=beta_launch
           → /go/beta.html?utm_source=linkedin&utm_medium=post&utm_campaign=beta_launch → TestFlight

/instagram → /?utm_source=instagram&utm_medium=bio_link&utm_campaign=beta_launch
           → /go/beta.html?utm_source=instagram&utm_medium=bio_link&utm_campaign=beta_launch → TestFlight
```

Cloudflare *may* log `/linkedin` or `/instagram` as an extra pageview if its
beacon fires before the redirect, but the hand-off is immediate and no delay is
added to force it — the **landing-page `/?utm_*` visit is the attribution
signal**. As with any campaign link, a TestFlight install still cannot be tied
back to a specific UTM (see *What we CANNOT directly connect*).

---

## The systems

| System | What it tells you | Where |
| --- | --- | --- |
| **Cloudflare Web Analytics** | Visits, referrers, top pages, countries, bounce — for `tryplannr.app` **and** for the `/go/beta.html` redirect page (so its pageview count ≈ "Join the Free Beta" clicks). Cookieless, no consent banner. | Beacon `<script>` in `docs/index.html` and `docs/go/beta.html` (same token). Dashboard: Cloudflare → Web Analytics. |
| **App Store Connect → TestFlight** | Invitation opens, installs / accepted testers, sessions, crashes, feedback — **in aggregate only**. | App Store Connect → Plannr → TestFlight. |
| **Stripe** *(preserved, not currently used)* | Would give Payment Link views → sales → revenue and per-payment `client_reference_id` if a paid tier is ever turned back on. Dormant for the free beta. | Stripe Dashboard. See `README.md` → *TestFlight access → Preserved: Stripe payment flow*. |

---

## What we CAN measure

- **Landing-page visits**, total and over time — Cloudflare.
- **Traffic sources** — Cloudflare's Referrers report (e.g. `instagram.com`,
  `t.co`, `discord.com`), plus the `utm_*` visible in the page path for tagged
  links.
- **"Join the Free Beta" clicks (approximate)** — pageviews of `/go/beta.html`
  in the same Cloudflare dashboard. Treat this as a **floor**, not an exact
  count (see *Limitations*).
- **Landing → CTA click-through rate** — `/go/beta.html` views ÷ landing views
  for the same window.
- **TestFlight installs / active testers / crashes** — App Store Connect, in
  aggregate.

## What we CANNOT directly connect

- **A TestFlight install → a specific `utm_campaign`.** Apple exposes **no
  referrer or UTM** on TestFlight joins. Once the visitor leaves for
  `testflight.apple.com`, the website's attribution chain ends. TestFlight
  numbers are a separate, un-joinable dataset.
- **An individual person across the two systems.** No cookies or IDs are set, by
  design. Everything is counts, not journeys.
- **Per-campaign install counts.** You can see *total* installs (App Store
  Connect) and *per-campaign clicks* (best-effort, Cloudflare), but not installs
  broken down by campaign. Estimate campaign performance from clicks and a
  blended click→install rate; don't report it as measured.

Honest summary: **website attribution stops at the CTA click.** Everything after
the redirect is Apple's aggregate TestFlight reporting.

---

## Campaign URL convention

Every campaign link points at the **landing page** (never straight at the
redirect page or TestFlight) with UTM query parameters:

```
https://tryplannr.app/?utm_source=<source>&utm_medium=<medium>&utm_campaign=<campaign>
```

Use **lowercase**, and only **letters, digits, and underscores** in each value
(`instagram`, `beta_launch`; hyphens are also fine). `docs/site.js` normalises
anything else to `_` before copying the tags onto the CTA, so staying
in-convention keeps Cloudflare and the `/go/beta.html` path showing the *same*
strings.

### Standard values — keep these consistent

| Parameter | Meaning | Use these values |
| --- | --- | --- |
| `utm_source` | where the click came from | `instagram`, `tiktok`, `reddit`, `discord`, `x`, `email`, `flyer`, `poster` |
| `utm_medium` | the kind of placement | `bio_link`, `story`, `post`, `dm`, `ad`, `social`, `email`, `print`, `qr` |
| `utm_campaign` | the specific push (date-stamp when it helps) | `beta_launch` (use this for the launch push), `launch_2026_09`, `finals_week_2026` |
| `utm_content` *(optional)* | A/B or creative variant | `video_a`, `carousel_b`, `headline_2` |
| `utm_term` *(optional)* | paid-search keyword | `syllabus_to_calendar` |

Keep a running doc of the exact links you hand out, so two campaigns never reuse
one `utm_campaign` for different things.

---

## Building campaign links

All of these use the same `utm_campaign=beta_launch`. For LinkedIn posts and the
Instagram bio, prefer the clean aliases (`/linkedin`, `/instagram`) from
*Clean-alias entry redirects* above — they expand to the exact URLs below.

### Instagram — bio link  (alias: `https://tryplannr.app/instagram`)
The single link in your profile. Medium = `bio_link`.
```
https://tryplannr.app/?utm_source=instagram&utm_medium=bio_link&utm_campaign=beta_launch
```
If you use a link-in-bio tool, put the alias (or this URL) as the destination of
the "Join the beta" button there.

### LinkedIn — post  (alias: `https://tryplannr.app/linkedin`)
A personal or company post / comment. Medium = `post`.
```
https://tryplannr.app/?utm_source=linkedin&utm_medium=post&utm_campaign=beta_launch
```

### Instagram — story link sticker
Add a link sticker to the story; paste this as the URL. Medium = `story`. Add
`utm_content` if you run multiple story creatives.
```
https://tryplannr.app/?utm_source=instagram&utm_medium=story&utm_campaign=beta_launch&utm_content=story_1
```

### Instagram — paid ad
Set this as the ad's destination / "website URL". Medium = `ad`. Give each ad set
or creative its own `utm_content`.
```
https://tryplannr.app/?utm_source=instagram&utm_medium=ad&utm_campaign=beta_launch&utm_content=ad_set_a
```
Note: if Instagram/Meta appends its own click IDs (e.g. `fbclid`), that's fine —
the page ignores unknown params and still reads `utm_*`.

### Discord / community post
A message in a server, a pinned channel link, a community newsletter. Source =
the platform, medium = `post` (or `dm` for a direct message).
```
https://tryplannr.app/?utm_source=discord&utm_medium=post&utm_campaign=beta_launch
```
For a different community, change `utm_source` (e.g. `reddit`, `slack`,
`groupme`) and keep `utm_medium=post`.

### Physical flyer / poster QR code
Generate the QR code from this URL. Medium = `qr`; use `utm_source` for where the
flyer is (e.g. `flyer`, `poster`, `library`, `career_fair`).
```
https://tryplannr.app/?utm_source=flyer&utm_medium=qr&utm_campaign=beta_launch
```
Use any offline QR generator that encodes the URL verbatim (no third-party
redirect/shortener — those add tracking and can rot). Print, and test-scan it
before you hand it out.

---

## How the CTA carries the campaign

`docs/site.js` (section "campaign attribution") runs on the landing page:

1. Reads `utm_*` from `location.search`. The site is one page, so tags from the
   first request are still there when a CTA is clicked.
2. Normalises each value to `[a-z0-9_]` (lowercase, other runs → `_`, trimmed,
   ≤ 60 chars).
3. If `utm_source` **or** `utm_campaign` is present, rewrites the three
   "Join the Free Beta" CTAs from `go/beta.html` to
   `go/beta.html?utm_source=…&utm_medium=…&utm_campaign=…` (plus `utm_term` /
   `utm_content` when set).

`docs/go/beta.html` then:

1. Loads the Cloudflare beacon — this registers the pageview (with the `utm_*`
   still in the path).
2. After a short pause (~0.2 s) redirects to the bare TestFlight invitation.
   **Nothing is forwarded to Apple** — TestFlight ignores query params and the
   redirect target stays clean. The `utm_*` exist only so the Cloudflare
   pageview is campaign-tagged.

A visitor with **no** `utm_source`/`utm_campaign` (direct traffic, typed URL)
gets the CTAs unchanged — plain `go/beta.html`.

---

## Reading a campaign's results

1. **Visits** — Cloudflare → filter by the campaign window; cross-check the
   Referrers report and, for tagged links, the `utm_*` in the page path.
2. **CTA clicks** — Cloudflare → Pages report → count `/go/beta.html` (and, if
   Cloudflare shows query strings for you, `/go/beta.html?utm_campaign=…`) over
   the same window.
3. **Click-through rate** = `/go/beta.html` views ÷ landing views.
4. **Installs** — App Store Connect → TestFlight, for the same window. This is a
   *total*, not per-campaign.
5. **Rough campaign install estimate** = campaign clicks × (total installs ÷
   total clicks). Label it an estimate.
6. **Cost per click / per estimated install** = your recorded spend for that
   campaign ÷ the number above. Track spend yourself, one row per campaign.

---

## Limitations to keep in mind

- **Cloudflare Web Analytics has no custom-event API.** Custom events are a
  Cloudflare *Zaraz* feature, which is not installed. The `/go/beta.html`
  pageview is the click proxy because it's a real page load — not an event.
- **The redirect page waits only ~0.2 s** before handing off (UX first). A very
  fast tap on a slow connection can navigate away before the beacon fires, so
  `/go/beta.html` counts are a **floor**. Landing-page `utm_*` visits are the
  more reliable campaign signal.
- **Per-campaign click breakdown is best-effort.** Cloudflare records the path;
  whether it splits by query string in the Pages report varies. If it doesn't,
  correlate `/go/beta.html` totals with the campaign window + referrer.
- **No cross-system join.** Website (Cloudflare) and TestFlight (Apple) can't be
  linked at the person or campaign level. Report them side by side, not merged.

---

## Guardrails

- Campaign links point at `tryplannr.app/?utm_*` — not at `/go/beta.html` and not
  at `testflight.apple.com` directly. Let the page do the tagging.
- No cookies, no fingerprinting, no new analytics dependency. If a real need for
  funnel/event analytics ever appears, the only in-scope option is a single
  cookieless script (Plausible or Umami) — still no GA4 / PostHog / Segment.
- Cloudflare Web Analytics stays the primary website analytics system.
- The Stripe attribution path (`client_reference_id` on a Payment Link) is
  **preserved in git history / the backend** and can be re-enabled if a paid
  tier returns — it's just not part of the current free-beta funnel.
