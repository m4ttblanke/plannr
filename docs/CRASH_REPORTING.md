# Crash reporting (Sentry)

Plannr links the [`sentry-cocoa`](https://github.com/getsentry/sentry-cocoa) SPM
package (pinned in `Plannr.xcodeproj/.../Package.resolved`). All of it is wrapped
in `Plannr/Plannr/CrashReporting.swift` and is a **no-op until a DSN is set**, so
the app builds and runs identically with no configuration — the repo carries no
DSN.

## One-time setup

1. **Create a Sentry project.** In Sentry: *Projects → Create Project →* platform
   **Apple (iOS)**. Copy its **DSN** (`Settings → Projects → <project> → Client
   Keys (DSN)`). A DSN is a write-only ingest key — it is safe to ship in the app
   binary, but keeping it out of git is still tidier (see option B).

2. **Give the app the DSN — pick one:**

   - **A — quickest.** Open `Plannr/Plannr/Info.plist` and paste the DSN as the
     value of `SENTRY_DSN`.

   - **B — keep it out of git.** Leave `Info.plist`'s `SENTRY_DSN` as
     `$(SENTRY_DSN)`, then define `SENTRY_DSN` as a build setting: create
     `Plannr/Plannr/Secrets.xcconfig` (git-ignored) containing
     `SENTRY_DSN = https://…@o0.ingest.sentry.io/0`, and set it as the
     Debug/Release **Configuration File** for the Plannr target
     (*Project → Info → Configurations*).

3. **Run once and confirm.** Launch a Debug build → *profile avatar → Debug →
   **Force a test crash***. Relaunch the app (the crash is sent on next start).
   The event should appear in Sentry within a minute, tagged
   `environment: debug`, `release: plannr@<version>+<build>`.

## dSYMs (release symbolication)

Xcode uploads dSYMs to App Store Connect automatically for TestFlight builds.
Sentry needs them too — either:

- download them from App Store Connect and drag them onto the Sentry project's
  *Settings → Debug Files*, or
- add a `sentry-cli upload-dif` run-script build phase / the Sentry Xcode build
  plugin (see Sentry docs) so it happens on every archive.

Debug builds from the simulator symbolicate without dSYMs.

## What it captures

- Unhandled crashes and the last breadcrumbs before them.
- `environment` (`debug` / `production`) and `release` (`CFBundleShortVersionString`
  + `CFBundleVersion`).
- The signed-in account **email** as the Sentry user, so a tester's report can be
  matched to their crash. Cleared on sign-out and in guest mode. No syllabus
  content, event text, or Google tokens are sent.
- Tracing / profiling / session replay are **off** (`tracesSampleRate = 0`).

## Using it from code

```swift
CrashReporting.breadcrumb("Started syllabus upload", category: "upload")
CrashReporting.capture(error)          // report a caught error, no crash
```
