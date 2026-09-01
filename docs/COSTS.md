# Cost & Break-Even Model

*Last updated: September 1, 2026. All third-party prices are estimates — verify
against current published pricing before relying on these numbers.*

This document estimates what it costs to run Plannr, what each paying customer
nets, and how many customers are needed to break even. The revenue model today is
a **one-time payment for TestFlight access** (a Stripe Payment Link on the
landing page). The price is configured in the Stripe Dashboard, not in this
repo — the tables below are worked at several price points so you can read off
the one you set.

---

## 1. Fixed costs (do not scale with usage)

| Item | Cost | Notes |
| --- | --- | --- |
| Apple Developer Program | **$99 / year** | Required to ship to TestFlight or the App Store. Flat fee. |
| Render — web service | **$0 (free) → ~$7 / mo** ($84/yr) | Currently `plan: free` in `render.yaml`. Free tier spins down after ~15 min idle (cold-start delay on the next request). Starter is ~$7/mo. |
| Render — PostgreSQL | **$0 (free) → $6 / mo** ($72/yr) | Currently `plan: free`. Render's free Postgres is time-limited and can be deleted — **not safe for a real launch**. The paid plan is **$6/mo**. |
| Landing page hosting | **$0** | Served from `docs/` via GitHub Pages (supports HTTPS + a custom domain). |
| Domain — `tryplannr.app` (planned) | **$16 year 1, then $30 / yr** | Via Squarespace. Not yet purchased. `.app` requires HTTPS, which GitHub Pages provides. Squarespace pricing is on the high side — plan to transfer to a cheaper registrar (~$12–15/yr for `.app`) later. |
| Cloudflare Web Analytics | **$0** | Free tier. |

**Fixed-cost scenarios:**

| Scenario | Annual fixed cost | When it applies |
| --- | --- | --- |
| **Minimum** (all free Render tiers, no domain) | **~$99 / yr** (~$8.25/mo) | Beta only. Accepts cold starts and the risk of losing the free database. |
| **DB-only paid** (free web + $6/mo DB + domain) | **~$201 / yr** (~$16.75/mo) | Durable data, but the API still cold-starts. Year 1 ~$187 with the $16 intro domain price. |
| **Fully paid** (Starter web + $6/mo DB + domain) | **~$285 / yr** (~$23.75/mo) | No cold starts. Year 1 ~$271. This is the target for paying customers. |

---

## 2. Variable costs (scale with usage)

| Item | Cost | Notes |
| --- | --- | --- |
| **Gemini API** (syllabus parsing) | **~$0.005–0.015 per syllabus parse** | The only per-use API cost. A parse = prompt (~1.2K tokens) + syllabus text (~3K–15K tokens input) + JSON output (~1K–4K tokens) on a Flash-tier model. |
| Google Calendar API / OAuth | **$0** | Free, subject to quota. |
| OCR (Tesseract) for scanned PDFs | **$0** | Runs on the server CPU, no API charge. (Also not currently enabled in production — see `DEPLOY.md`.) |
| Server storage per user | **≈ $0** | One `users` row + one `google_credentials` row per account. 10,000 users is still trivial storage. |

**Per-user lifetime Gemini cost:** a student parses ~4–6 syllabi per term plus
re-uploads → roughly **8–12 parses per user per term**, or **~$0.05–$0.18 per
user per term**. Over a couple of terms of use, call it **~$0.15 per user,
lifetime** — used as the variable cost in the break-even math below.

At scale this stays small: 10,000 users × 10 parses = 100,000 parses ≈
**$500–$1,500 total**, one-time-ish.

---

## 3. Revenue per paying customer

Stripe (US, standard pricing) takes **2.9% + $0.30** per successful charge.
Disputes cost **$15 each** (charged whether you win or lose).

Net revenue per customer, at price **P**:

```
net(P) = P − (0.30 + 0.029·P) − 0.15   (lifetime Gemini)
       ≈ 0.971·P − 0.45
```

| Price P | Stripe fee | Gemini (lifetime) | **Net per customer** | Stripe takes |
| --- | --- | --- | --- | --- |
| $1.00 | $0.33 | $0.15 | **$0.52** | 33% |
| $3.00 | $0.39 | $0.15 | **$2.46** | 13% |
| $5.00 | $0.45 | $0.15 | **$4.40** | 9% |
| $10.00 | $0.59 | $0.15 | **$9.26** | 6% |

**Minimum sensible price:** at $1 the processor eats a third of it. Price
**≥ $3–5** to keep fees to ~10% or less. Below ~$0.50 you lose money on every
sale regardless of volume (Stripe's fixed $0.30 + Gemini).

---

## 4. Break-even: how many paying customers

Customers needed per year = `annual fixed cost ÷ net per customer`.

| Price P | Net / customer | **Minimum** (~$99/yr) | **DB-only paid** (~$201/yr) | **Fully paid** (~$285/yr) |
| --- | --- | --- | --- | --- |
| $3 | $2.46 | ~41 / yr (~4 / mo) | ~82 / yr (~7 / mo) | ~116 / yr (~10 / mo) |
| $5 | $4.40 | ~23 / yr (~2 / mo) | ~46 / yr (~4 / mo) | **~65 / yr (~5–6 / mo)** |
| $10 | $9.26 | ~11 / yr (~1 / mo) | ~22 / yr (~2 / mo) | ~31 / yr (~3 / mo) |

Everything above these counts is profit, minus the ~$0.15 Gemini cost per
additional user (i.e. margin is ~95%+ per marginal sale at $5+).

**Rule of thumb:** on the fully-paid setup at a **$5** price point, you need
about **5–6 sales per month** to cover costs; at **$10**, about **3 per month**.
Year 1 is ~$14 cheaper thanks to the intro domain price.

---

## 5. What moves the number most

1. **Price (set in Stripe).** Doubling the price nearly halves the break-even
   count. This is the single biggest lever.
2. **Free vs. paid Render.** Staying on free tiers drops fixed cost to ~$99/yr,
   but the free database can be deleted and cold starts hurt conversion. The
   cheapest safe step up is the **$6/mo paid Postgres** while leaving the web
   service free (~$201/yr) — durable data, but the API still cold-starts.
3. **Domain registrar.** `tryplannr.app` through Squarespace is $16 the first
   year then **$30/yr** — roughly double a budget registrar. Transferring to
   Cloudflare/Porkbun/Namecheap after the first year saves ~$15/yr.
4. **Disputes / refunds.** One Stripe dispute is $15 — it erases ~3 sales at $5
   or ~6 at $3. A 2–3% dispute rate on a cheap impulse purchase is realistic;
   budget for it.
5. **Gemini volume** only matters past thousands of users, and even then it's
   hundreds of dollars, not thousands. Not a launch concern.

---

## 6. Plug in your real numbers

Replace the placeholders and recompute:

```
P                 = <your Stripe price>
fixed_annual      = 99 (Apple) + 72 (Render DB $6/mo) + [84 if paid web] + 30 (domain, yr 2+)
net_per_customer  = P − 0.30 − 0.029·P − 0.15
break_even_users  = fixed_annual ÷ net_per_customer

# Current best estimate, fully paid, steady state:
fixed_annual      = 99 + 72 + 84 + 30 = 285
```

Things this model does **not** include: your time, marketing/ad spend, LLC or
business registration, accounting, or App Store commission (15% under the Small
Business Program) if you later move from a one-time Stripe fee to paid App Store
distribution or in-app purchases.
