# Analytics & campaign attribution

*Last updated: September 9, 2026.*

Plannr's measurement stack is deliberately small: **Cloudflare Web Analytics**
for traffic, **Stripe** for money, and **UTM tags** to join the two. No GA4, no
PostHog, no Segment, no cookies, no fingerprinting, no extra JS dependency.

---

## The two systems

| System | What it tells you | Where |
| --- | --- | --- |
| **Cloudflare Web Analytics** | Visits, referrers, top pages, countries, bounce. Cookieless, no consent banner. Campaign visits show up as pageviews on `/?utm_source=…`. | Beacon `<script>` in `docs/index.html` (token in the tag) and injected on the backend `/testflight/success` page. Dashboard: Cloudflare → Web Analytics. |
| **Stripe** | Payment Link **views → sales → revenue** (one-time price only — Payment Link analytics don't work for recurring prices), plus per-payment `client_reference_id` and UTM values on the post-payment redirect. | Stripe Dashboard → Payment Links → your link → *Payments and analytics*. Per-payment: the `checkout.session.completed` webhook and the payment detail page. |

CAC = **campaign spend you record yourself** ÷ **purchases attributed to that
campaign** (via `client_reference_id`, see below). Nothing automates spend entry;
keep a one-row-per-campaign note.

---

## Campaign URL convention

Every campaign link points at the **landing page** (not directly at Stripe) with
UTM query parameters:

```
https://tryplannr.app/?utm_source=<source>&utm_medium=<medium>&utm_campaign=<campaign>
```

Use **lowercase**, and only **letters, digits, and underscores** in each value
(`instagram`, `beta_launch`). Hyphens are also safe. Anything else (spaces,
`&`, punctuation) is normalised to `_` before it reaches Stripe, and Stripe
itself silently drops values outside `[A-Za-z0-9_-]`, so staying in-convention
keeps Cloudflare and Stripe showing the *same* strings.

### Standard values

| Parameter | Meaning | Examples |
| --- | --- | --- |
| `utm_source` | where the click came from | `instagram`, `tiktok`, `reddit`, `email`, `flyer`, `discord`, `x` |
| `utm_medium` | the kind of placement | `social`, `bio_link`, `story`, `dm`, `email`, `print`, `cpc` |
| `utm_campaign` | the specific push (date-stamp it) | `beta_launch`, `launch_2026_09`, `finals_week_2026` |
| `utm_content` *(optional)* | A/B or creative variant | `video_a`, `carousel_b`, `headline_2` |
| `utm_term` *(optional)* | paid-search keyword | `syllabus_to_calendar` |

### Examples

```
Instagram bio link, launch:
https://tryplannr.app/?utm_source=instagram&utm_medium=bio_link&utm_campaign=beta_launch

Instagram story, launch, creative B:
https://tryplannr.app/?utm_source=instagram&utm_medium=story&utm_campaign=beta_launch&utm_content=carousel_b

Launch email:
https://tryplannr.app/?utm_source=email&utm_medium=email&utm_campaign=beta_launch

Reddit post:
https://tryplannr.app/?utm_source=reddit&utm_medium=social&utm_campaign=beta_launch
```

Keep a running list of the exact links you hand out so two campaigns never reuse
one `utm_campaign` for different things.

---

## How attribution reaches Stripe

`docs/site.js` (section "campaign attribution") runs on the landing page:

1. Reads `utm_*` off `location.search` (the site is one page, so the tags set on
   the first request are still there when a CTA is clicked).
2. Normalises each value to `[a-z0-9_]`.
3. On all three Stripe CTAs, appends:
   - the `utm_*` params themselves — Stripe Payment Links accept these natively
     and echo them onto the post-payment redirect to `/testflight/success`;
   - `client_reference_id` — a single compact tag Stripe stores on the Checkout
     Session and includes in the `checkout.session.completed` webhook and on the
     Dashboard payment row.

`client_reference_id` format (only `-` and `_`, ≤ 200 chars, no PII):

```
cmp-<campaign>__src-<source>__mdm-<medium>
```

e.g. `?utm_source=instagram&utm_medium=social&utm_campaign=beta_launch`
becomes `client_reference_id = cmp-beta_launch__src-instagram__mdm-social`.

Parse it back with: split on `__`, then split each part on the first `-`
(`cmp` → campaign, `src` → source, `mdm` → medium).

Only `client_reference_id` is used — the proposed value is non-sensitive campaign
tags, well within Stripe's 200-char limit, so no adjustment was needed.

A visitor with **no** `utm_source`/`utm_campaign` (direct traffic, someone typing
the URL) gets the CTAs unchanged — no `client_reference_id` is added.

---

## Reading a campaign's results

1. **Visits** — Cloudflare Web Analytics, filter the path/referrer for the
   campaign window. (Cloudflare doesn't break out by UTM value; use the date
   window + referrer, or read total landing visits for the push.)
2. **Purchases** — Stripe → Payments, filter the campaign window, and read
   `client_reference_id` on each (or the Payment Link *Payments and analytics*
   tab for the link-level view → buy count; data can lag up to ~18 h and isn't
   available in sandboxes).
3. **Landing-page conversion rate** = purchases ÷ landing visits for the window.
4. **Campaign conversion rate** = purchases with that `utm_campaign` ÷ visits
   driven by that campaign.
5. **CAC** = your recorded spend for that campaign ÷ its attributed purchases.

---

## Guardrails

- Payment Links only. Don't hand out the raw `buy.stripe.com` URL with a
  hand-written `client_reference_id` that contains anything sensitive — these
  links get reshared.
- Don't add another analytics tool without a concrete reason. If you ever need
  funnel/CTA-click events in one place, the only in-scope option is a single
  cookieless script (Plausible or Umami) — still no GA4 / PostHog / Segment.
- Cloudflare Web Analytics and Stripe stay the primary systems.
