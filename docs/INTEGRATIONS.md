# Integrations

This version goes online in two cases only: to GitHub, to check for app updates, and — when you add or check a coverage link, or look up a target's website — to that one page. Everything else works through files you import and export, or through apps already on your Mac. The **Connections** screen in the app shows the same information, plus what the app is allowed to do on its own.

## Built in (no account needed)

| Service | How it's used |
|---|---|
| **Your mail app** (Mail, Outlook, Gmail in a browser set as default) | An approved pitch, follow-up or reminder opens as a new message via `mailto:`. You read it, press Send, then click Mark Sent. |
| **Contacts app** | Import › From the Contacts App reads the people you pick, after macOS asks for permission. Nothing is written back to Contacts. Contact notes aren't read (macOS restricts them). |
| **Web pages (coverage and target links)** | When you add a link in Coverage, or click Check Link / Check Links, Manager opens that page once, the way a browser would, and reads the outlet, headline, writer, date and review score the site publishes for link previews (Open Graph, article tags, Schema.org). It can keep a copy of the page. In Targets, Look Up reads a website's home page for its name and description and for links and addresses about submissions or demos. Nothing is fetched in the background and nothing is posted. Pages behind a paywall, sign-in or bot check can't be read: fill those in yourself, or attach a PDF or screenshot. |
| **macOS notifications** | Approvals waiting and deadlines coming up, if you allow notifications. Packaged app only. |
| **GitHub releases** | Update checks and downloads from this repository's releases. It's public, so nothing is needed; if it became private, a read-only token goes in Settings › Updates and is kept in your Keychain. |

## Manual today — import and export

| Service | Workflow now | To connect live it would need |
|---|---|---|
| **Email list provider** (Mailchimp, Kit, MailerLite, Bandcamp, Beehiiv…) | Import your list as CSV. Draft and approve a campaign, then Export for Provider: HTML + text, a recipients CSV, and a do-not-email CSV. Send it from the provider. Import its per-recipient report to record delivery and apply bounces, unsubscribes and complaints. | An account and API key (OAuth for some). Sending would still require approval per campaign. |
| **Calendar** (Apple Calendar, Google, Outlook) | Import .ics files; export your Manager calendar as .ics. | macOS Calendar access (EventKit) for two-way sync on this Mac, or a Google/Microsoft account. |
| **Distributor** (DistroKid, CD Baby, TuneCore, AWAL, Amuse…) | Fix issues in Releases › Metadata check, export the metadata CSV, enter it in the distributor's upload form, then set the release stage to Delivered. | Most distributors offer no public upload API to independent artists. |
| **PROs, The MLC, SoundExchange** and other collection societies | Track memberships in Profile › Rights; export songwriter splits as CSV for registration portals. Registration tasks are part of every release timeline. | These organizations use member portals rather than public APIs. |
| **Spotify for Artists** | Fill in the editorial pitch form in Press Kit › Playlists, approve it, then click Copy Fields and Open Spotify for Artists and submit it there (Music › Upcoming). Mark it submitted afterwards. | Spotify offers no public API for pitching. |
| **Coverage spreadsheets and clipping services** | Import a CSV of coverage (date, outlet, title, type, url, author, rating, quote, excerpt, notes, release — common alternative column names work too). Links already saved are skipped. Export everything as CSV. | Clipping and media-monitoring services (Meltwater, Muck Rack, Google Alerts) would need an account or feed to find new coverage automatically. |
| **Target lists** (spreadsheets, label databases, festival lists) | Import a CSV of publications, labels and others (name, type, status, priority, website, submission page and email, whether they take submissions, genres, location, similar artists, guidelines, notes, tags, next check — common alternative column names work too). Names or websites already on your list are skipped. Export to CSV any time. | — |
| **Contacts, media and curator lists** | Import from the Contacts app, a vCard (.vcf, from Contacts, Google or Outlook) or a CSV (spreadsheets, PR databases, curator lists). Existing contacts are only filled in, never overwritten. Export to CSV any time. | — |

## Not connected — needs an outside service or credentials

| Service | What it's for | Status |
|---|---|---|
| **Streaming analytics** (Spotify for Artists, Apple Music for Artists, YouTube Studio) | Measuring goals and campaigns. | These dashboards don't offer general public APIs for this data. Record results in each release's 30-day review task. |
| **Social platforms** | Publishing announcements and teasers. | Each needs a developer account and OAuth. Publishing would always require approval. Plan posts as tasks and calendar entries for now. |
| **Ticketing and venues** | Offers, settlements and ticket counts for touring. | Roadmap. |
| **Banks and royalty statements** | Income ledger and collection-gap reports. | Roadmap; statement CSV imports first, bank feeds would need an aggregator account. |
| **An AI model service** | Written feedback on demos, artwork and setlists. | Roadmap, as an explicit opt-in connection. |
| **Apple Developer ID** | Signing and notarizing so the app opens without the one-time Open Anyway step. | Not used: releases are signed ad hoc, like Freeman's other apps. |

## Rules any future connection must follow

- It's visible on the Connections screen: what's connected, as which account, and what it may do.
- Credentials go in the Keychain, never in the data file.
- Anything that sends, publishes, accepts, pays or commits still goes through Approvals, whatever the connection could technically do.
- If the service is unavailable, the manual workflow above keeps working, and nothing is shown as done until the service confirms it.
