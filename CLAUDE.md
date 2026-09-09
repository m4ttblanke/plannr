# CLAUDE.md

This file defines how Claude Code should work in the Plannr repository.

Plannr is an iOS student productivity app that converts course syllabi into
organized calendar events and syncs them with Google Calendar.

The repository contains three major surfaces:

- `Plannr/` — native iOS app built with Swift / SwiftUI
- `backend/` — Python / FastAPI backend
- `docs/` — public marketing and TestFlight landing site

## Current priority

The current task is to redesign and improve the public Plannr marketing site
under `docs/`.

Unless explicitly requested, do not modify the SwiftUI application or FastAPI
backend as part of landing-page work.

## Engineering principles

- Preserve the existing architecture unless there is a concrete reason to
  change it.
- Do not migrate the marketing site to React, Next.js, or another framework
  merely for a redesign.
- Prefer improving the existing HTML, CSS, and JavaScript.
- Keep dependencies minimal.
- Maintain existing TestFlight/payment/navigation functionality.
- Do not break URLs used by production or OAuth verification.
- Keep the site responsive and accessible.
- Treat real Plannr screenshots and product behavior as the source of truth.
- Do not invent product capabilities.

## Product positioning

Plannr is not a general calendar app.

Its core value is reducing the manual work of turning syllabi and changing
course information into an organized calendar.

Primary flow:

Upload syllabus
→ review extracted events
→ organize classes
→ sync to Google Calendar
→ reconcile later syllabus changes

Accuracy, trust, and user review are important parts of the product story.

## Landing-page design

The marketing site should feel like a polished consumer/student product,
not a generic SaaS template.

Prioritize:
- real product UI
- clear syllabus → organized calendar transformation
- strong visual storytelling
- responsive mobile presentation
- clear TestFlight CTA
- trust and review-before-sync messaging

Avoid:
- generic feature-card grids as the primary storytelling device
- excessive gradients
- glassmorphism everywhere
- generic AI startup styling
- unnecessary framework migration
- fabricated testimonials or metrics
- excessive animation

Use installed skills selectively.

Suggested roles:
- `frontend-design` — primary creative direction
- `scroll-craft` — scroll-driven product storytelling
- `interface-design` — CTA and interaction hierarchy
- `brand`, `design`, `design-system`, `ui-styling` — visual identity
- `ui-ux-pro-max` — reference research
- `web-design-guidelines` — final accessibility/UX audit
- `ponytail` — prevent unnecessary architecture
- `e2e-testing` / `verification-loop` — browser verification

Use Playwright to inspect the actual implementation at desktop and mobile
sizes before considering visual work complete.

21st.dev may be used for inspiration, but copied components must be adapted to
Plannr's own visual identity.

## Before changing the landing page

1. Inspect the current `docs/` implementation.
2. Identify all existing links, CTAs, payment/TestFlight behavior, analytics,
   and production-sensitive elements.
3. Inspect the existing product screenshots/assets.
4. Propose the redesign direction before replacing the page wholesale.
5. Preserve existing functional behavior unless a change is explicitly
   approved.

## Completion requirements

Before finishing landing-page changes:

- inspect desktop and mobile layouts with Playwright
- verify all CTAs and links
- verify no page-level horizontal overflow
- verify reduced-motion behavior
- run an accessibility/UX audit
- check browser console errors
- confirm no backend or iOS files were changed unintentionally
