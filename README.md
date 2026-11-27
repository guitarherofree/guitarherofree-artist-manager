# Manager

A macOS app that works as a digital career manager for an independent musician. It keeps your plan, releases, press kit, email list, calendar and contacts in one place, recommends what to do next, and does the routine work you allow — while anything that leaves the app, spends money or commits you waits for your approval.

Everything is stored on your Mac. Nothing is sent, published, accepted, paid or signed by the app.

## What it does

| Area | What you can do |
|---|---|
| **Setup** | A guided onboarding: music and brand, audience, goals, team, budget and time, communication style, and approval rules. It produces your first career plan. |
| **Today** | What needs you (approvals, approved-but-unsent messages, overdue tasks, schedule conflicts), recommended next steps, the next 14 days, and a snapshot. |
| **Career Plan** | Goals, positioning, milestones, and ranked recommendations. Each one explains why it's suggested, and you can add it to tasks, mark it done or dismiss it. |
| **Profile & Brand** | Identity, links, sound and positioning, bios, audience, royalty organizations (PRO, mechanical, neighboring rights), budget, availability and blackout dates, draft tone, notifications. |
| **Releases** | Singles, EPs and albums with tracks, ISRC/ISWC, songwriter splits, assets, a metadata check against what distributors need, a dated campaign timeline (scaled for EPs and albums), and a release budget where spending goes through approval. Exports metadata and splits as CSV. |
| **Press Kit** | An EPK with photos and credits, featured tracks, highlights, pull quotes from your coverage, booking and publicity contacts, a completeness score, and HTML/Markdown export. Press releases generated from a release, and a public-statement framework. |
| **Pitches** | Review requests, press, radio, label, booking and sync pitches with approval, sending via your mail app, follow-ups and reply tracking. **Pitch Several** drafts a personal note to many writers, outlets or curators at once; approve them one by one or all together. |
| **Playlists** | The **Spotify editorial pitch** form for each upcoming release (main genre, up to three subgenres, moods, styles, instruments, location, and the 500-character note), with deadline tracking (7 days before release for Release Radar, about four weeks for the best chance) and checks before approval. You submit it in Spotify for Artists with Copy Fields, then mark it submitted. Plus independent curator pitches and a log of playlist adds. |
| **Coverage** | Reviews, articles, interviews, features, premieres, radio plays, podcasts, video, playlist adds and mentions in one place. Paste a link (or many) and Manager fills in the outlet, headline, writer, date and review score, and can keep a copy of the page in case the link breaks. Attach PDFs, scans of print clippings, screenshots or recordings. Pull quotes with credit feed the press kit; coverage from a pitch closes that pitch. Check Links finds pieces that have gone missing. CSV import and export. |
| **Targets** | Publications, labels, radio shows, podcasts, playlists, festivals and agencies you want to reach or keep an eye on. Paste a website and Manager fills in the name and type and looks for a submissions page and address. Track how they take submissions, priority (dream, stretch, good fit now), why they fit you, and a date to look again. Each target shows the people there from your contacts, every pitch to them and coverage from them, and suggests moving the status along when that history says so. Pitch everyone there in one go, including a new **label pitch**. Suggestions from your contacts and coverage; CSV import and export. |
| **Email List** | Subscribers with status, signup source and consent records; CSV import that never re-subscribes anyone who left; full, sendable and do-not-email exports; hygiene checks (missing consent, typos, role addresses, stale pending); segments; campaigns with pre-send checks, approval, export for your email provider, and report import that applies bounces, unsubscribes and complaints. |
| **Calendar** | Month view, day agenda, events with people attached, conflict checks against your availability, .ics import and export. Release days, task deadlines, planned emails and follow-ups all appear. |
| **Tasks** | Everything due, filtered by area and status, with a workload check against your weekly hours. |
| **Team** and **Contacts** | Two pages: **Team** for the people you work with (what each handles, check-in reminders) and **Contacts** for everyone else. Both have conversation history, follow-up dates, messages to each person, conversation prep built from your history. Import from the **Contacts app**, a **vCard** file or a **CSV**; existing contacts are only filled in. CSV export. |
| **Approvals & Activity** | Every waiting request shows exactly what would go out. Decision history. A full activity log with undo for reversible changes. |
| **Connections** | What's connected (nothing, by default), what the app may do on its own, and how each outside service works today without a connection. |
| **Coming Next** | The roadmap for live/touring, finances, sync, marketing and daily support. |
| **Updates** | Updates itself from this repository's GitHub releases, the same way as Freeman's other apps (see below). |

## Install (once)

1. Download `Manager-<version>-mac-arm64.zip` from the [latest release](https://github.com/guitarherofree/guitarherofree-artist-manager/releases/latest).
2. Open the zip and drag **Manager** into Applications.
3. Open it. macOS says it can't check the app for malicious software, because it isn't signed with an Apple Developer ID. Go to **System Settings → Privacy & Security**, click **Open Anyway** next to Manager, and confirm. You only do this once.

Your data moves over from earlier “Artist Manager” builds automatically. After installing, you can delete the old app.

Manager needs macOS 14 Sonoma or later on an Apple silicon Mac.

## Updates

Manager updates itself from this repository's GitHub releases:

- It checks shortly after it opens and then once a day, and downloads new versions in the background.
- A bar at the top of the window says when a new version is ready. **Restart Now** installs it straight away; otherwise it installs when you quit.
- **Manager › Check for Updates…** (or the link at the bottom of the sidebar) checks right away and shows the release notes.
- Settings › Updates turns automatic checks and downloads on or off and shows the log (`~/Library/Logs/Manager/update.log`).
- Before installing, the app checks the download against the SHA-256 checksum GitHub publishes, confirms it is Manager at the expected version, and verifies its code signature. The previous version is kept in `~/Library/Application Support/Manager/Updates/Previous` in case you need to go back.

The repository is public, so no GitHub token is needed. If it ever becomes private, paste a read-only token in Settings › Updates.

## Releasing an update

1. Add a section at the top of `CHANGELOG.md`:
   ```md
   ## 0.3.0
   - What changed
   ```
2. Push to `main`.

The **Release** workflow runs the tests, builds the app on an Apple silicon Mac, signs it ad hoc, and publishes `Manager-0.3.0-mac-arm64.zip` with that section as the release notes. Installed copies pick it up on their next check. You can also run the workflow by hand from the **Actions** tab, or push a `v0.3.0` tag.

## How approvals work

| Kind of action | What happens |
|---|---|
| Send a message or pitch (including a Spotify editorial pitch), send an email campaign, publish, accept an offer, spend money, make a contractual or financial commitment | **Always asks you first.** This can't be changed. Approving marks the item ready; you send it from your own mail app, email provider or Spotify for Artists, then mark it sent. |
| Organize records, add calendar entries, create tasks, draft materials, watch budgets, refresh the plan | Your choice per action: **automatic**, **ask me first**, or **off**. Set during onboarding or in Settings › Permissions. |
| Reminders to people attached to an event | Defaults to **ask me first**. If you set it to automatic, matching reminders are marked approved by your rule — you still send them. |

Every change is logged with who did it (you, automation, an import, or a pre-approved rule). Changes to your records can be undone from Approvals & Activity › Activity log, or with ⌥⌘Z for the most recent one. Things that happened outside the app — an email you sent, a payment you made — can't be undone there.

## Your data

One JSON file at `~/Library/Application Support/Manager/workspace.json` (moved automatically from the older “Artist Manager” folder), with a daily backup kept for 14 days in `Backups/`, and press photos, saved coverage pages and coverage attachments in `Media/`. Settings › Data has Export Backup and Restore. If the file can't be read, it's set aside (not deleted) and the newest backup is loaded.

## How it's built

- `Sources/ArtistManager/` – the app. `Core/` is plain Foundation (models, plan rules, approvals, imports and exports, drafting); `App/`, `Views/`, `Platform/` and `Updates/` are the SwiftUI and AppKit parts.
- `Packages/GitHubReleaseUpdater/` – the in-app updater, shared in the same form by Freeman's other Swift apps.
- `Tests/ArtistManagerTests/` – tests for the core. They also run on Linux, where the package builds only `Core/`.
- `Scripts/build.sh` – what the workflows run to build `Manager.app` (a Swift package build, then the app bundle and an ad hoc signature).
- `.github/workflows/ci.yml` builds and tests every push; `release.yml` publishes releases. Both write a short report to the `ci-logs` branch.

Run the tests with `swift test` and `swift test --package-path Packages/GitHubReleaseUpdater`.

## More

- [docs/ASSUMPTIONS.md](docs/ASSUMPTIONS.md) — decisions made where the brief left room
- [docs/INTEGRATIONS.md](docs/INTEGRATIONS.md) — what needs outside services or credentials, and the manual workflow for each
- [docs/ROADMAP.md](docs/ROADMAP.md) — what comes next for the remaining capabilities
