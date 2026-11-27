# Assumptions and decisions

Where the brief left room, these are the choices made and why. Each is easy to revisit.

## Product

- **One artist, one Mac.** The artist is the only user. Data lives in a single local file. There's no account, sync or shared access yet (see the roadmap).
- **The app never acts outside itself.** It drafts, organizes, schedules, reminds and records. Sending email, posting, paying, signing and accepting are done by the artist in their own tools. Approval marks something *ready*; the artist then confirms it happened ("Mark Sent", "Mark Paid", "I've distributed it"). This keeps the record honest: nothing shows as done unless the artist says it is.
- **Approvals that can't be switched off:** sending messages or pitches, sending email campaigns, publishing, accepting offers, spending money, and contractual or financial commitments. These are enforced in code (`ActionKind.alwaysRequiresApproval`), not just in the UI, and tested.
- **Routine work is configurable** per action (automatic / ask first / off): organizing records, calendar entries, task creation, drafting, budget warnings, plan refreshes, and pre-approved reminders. Reminders default to "ask first" because they go to other people.
- **Edits invalidate approvals.** Changing the recipient, subject, body or audience of an approved message or campaign sends it back to draft. Changing the amount of an approved or pending cost sends it back for approval.
- **Recommendations are deterministic rules**, not AI output. Each states its reason ("Why: …"), and refreshing never reopens something the artist dismissed or duplicates what's there.
- **Drafts come from templates** filled with the artist's profile, press kit and release details, in the tone they chose. They always need editing and approval. Brackets mark what the artist should fill in.
- **Creative feedback** (demos, tracklists, artwork, setlists) is on the roadmap, not built: useful feedback on audio and images needs a model service, which would be an explicit opt-in connection.

## Pitching

- **Spotify editorial pitches** follow Spotify for Artists' form: one unreleased song per release, a main genre, up to three subgenres, moods, styles, instruments, culture, language, hometown and location, and a note of up to 500 characters. The app warns under four weeks out, warns that pitches under 7 days miss followers' Release Radar, and won't let you approve a pitch for a song that's already out. It also notes when another pitched song is still pending, since Spotify takes one at a time.
- **Review requests** are their own pitch type: private stream link, release date, tracklist, press kit link, and a request to hold the review until release. The plan suggests pitching reviewers four to six weeks before release, and the release timeline includes the step.
- **Pitch Several** drafts one personal note per contact (never a group email), skips anyone already pitched the same way for that release, and leaves contacts without an email out. Drafts can be approved one by one or all together; approving all is one undoable step and still sends nothing.

## Coverage

- **Reading a link** uses only what the page publishes about itself for link previews and search engines: Open Graph and article tags, the `<title>`, and Schema.org JSON-LD (which is where review scores such as 8.2/10 come from). It happens only when you add or check a link, one request per page, identifying as Safari so sites serve their normal page.
- **When a page can't be read** (paywall, sign-in, bot check, offline), Manager says so and leaves the link unchecked. You fill in the details and can attach a PDF or screenshot instead.
- **Checked vs not checked.** A link is marked working only when Manager opened it successfully (with the date) or you confirm you've opened it. A 404 or 410 marks it broken. A refusal or a slow site doesn't change its status, since that says nothing about whether the piece is still up.
- **Saved copies** are the page's HTML with scripts and auto-refresh removed and a note at the top giving the address and date. Images and styling still load from the original site, so if the site disappears entirely the copy may show text only. For an exact visual record, attach a PDF (Safari › File › Export as PDF) or a screenshot.
- **Duplicates** are found by comparing links the way a person would: http/https, “www.”, a trailing slash, tracking parameters (utm_…, fbclid and similar) and #fragments are ignored.
- **The type** (review, interview, premiere, podcast, video…) is guessed from where the link points and how the page describes itself; you can change it. Mentions and playlist adds start outside the press kit; everything else starts in it.
- **Pull quotes** should be copied exactly as published and credited. The press kit uses only the pull quote, the credit and a link — never the full piece. Saved copies are for your own records.
- **Files are kept** in `Media/Coverage` when coverage is deleted, so undo brings everything back.
- **Release and writer** are filled in when obvious: a release whose title appears in the headline or summary, and a contact whose name matches the writer or who works at the outlet and was pitched. Coverage linked to a contact marks their open pitch as resulting in coverage.

## Targets

- **A target is an organization, not a person**: a publication, label, station or show, podcast, playlist, festival or agency. People who work there stay in Contacts and are linked automatically when their organization matches the target's name (ignoring “The”, capitals and punctuation) or their work email is on the target's website domain. Free mail addresses (Gmail, iCloud and so on) never link someone. Anyone else can be linked by hand.
- **Coverage and pitches are worked out, not copied.** A target shows coverage whose outlet matches its name or whose link is on its website (shared platforms such as Spotify, YouTube and Bandcamp don't count, since many outlets share them), and pitches to the people there that were actually sent.
- **Status moves only when you say so.** When the history says a target is further along (you pitched someone there, they replied, or coverage from them is saved), Manager suggests the new status and you click to apply it. It never moves a status backwards or out of “Not right now”.
- **Priority** is dream, stretch or good fit now — the artist's own judgment. **Fit** reasons (shared genres, similar artists, same city) are only shown, never used to rank or hide anything.
- **Look again** dates are for things that change: submission windows, a new issue, a label announcing its roster. A due date shows in the sidebar badge and the Career Plan. Marking a target checked records today and offers a week, a month, three or six months.
- **Submission details found on a website** (a submissions or demo page, an address) are suggestions from the public page and are marked as such. Respect a label's or outlet's stated policy: when they say they aren't taking submissions, or work by referral only, Manager says so instead of nudging a pitch.
- **Label pitches** are a new pitch type: who you are, a line about why the label (left in brackets for you to write), comparable artists, a listening link, two or three highlights from your press kit, and what you're looking for. Like every pitch, it needs approval and goes out from your mail app.

## Legacy

- **An organizer, not legal advice.** The Legacy page records who would look after the music, where things are and what the artist wants. It says plainly that a will or trust is what makes any of it binding, and points to an estate attorney.
- **No passwords.** Accounts record what each one controls and where its sign-in is kept. Text that looks like a password, PIN or recovery code gets a red warning. The page recommends a password manager's emergency access and services' own legacy settings (Apple Legacy Contact, Google Inactive Account Manager) instead.
- **Facts shown are general and US-focused:** copyright generally lasting for life plus 70 years; royalties passing as the will or trust says, or with the rest of the estate; US termination rights (35 years after a grant) passing to a spouse, children or grandchildren by statute regardless of the will; DistroKid's per-release Leave a Legacy extra; and post-death rights in name, image and voice varying by place. No fees or deadlines are quoted.
- **It reuses what Manager already knows**: released music with ISRCs, ISWCs and writer splits, royalty memberships from Profile › Rights, distributors from Releases, links from the profile, and team members. The letter is built fresh each time from the current data.
- **The letter** (HTML to print or save as PDF, or plain text) includes contact details for the people named and the team. It's written to a file only when the artist exports it.
- **Readiness** is a checklist of 15 items; nothing is scored until something is entered. The plan suggests starting a legacy plan (low priority) once there's released music, and a review at the interval the artist picks (12 months by default).

## Renaming

- The app was renamed from “Artist Manager” to “Manager”. The data folder moves to `~/Library/Application Support/Manager` on first launch; nothing in an existing new folder is ever overwritten.
- With the move to the standard updater (0.2.0), the bundle identifier became `com.freemanedwards.Manager`, like Freeman's other apps. macOS therefore asks again for Contacts access and notifications the first time.

## Music business defaults

These reflect common practice for independent artists in 2026; the app explains each and the artist can change dates and amounts.

- Release campaigns are scheduled back from release day: masters 8 weeks out, distributor upload and review pitches 5 weeks out, Spotify editorial pitch 4 weeks out, press outreach 3 weeks out, announcement 2 weeks out, email 10 days out, follow-ups a week after, and a 30-day review. EPs stretch pre-release lead times by 25% and albums by 60%, with a singles rollout added.
- Friday is suggested as release day (the global release day), as a warning rather than a rule.
- Metadata checks follow what distributors commonly require: square artwork marked final, ISRC format (CC-XXX-YY-NNNNN), UPC/EAN length, songwriter splits totaling 100%, every writer named.
- Royalty guidance names US organizations (ASCAP, BMI, SESAC, GMR; The MLC; SoundExchange) when the country is the US, and speaks generally otherwise.
- Email compliance prompts reflect US CAN-SPAM (a postal address and an unsubscribe link). The app keeps consent records and never re-subscribes suppressed addresses, which also supports GDPR-style practice, but it doesn't claim legal compliance — that depends on how the list was built and the provider used.

## Email list

- **Statuses:** subscribed, pending, unsubscribed, bounced, complained (spam), cleaned. The last four are "suppressed": never emailed, never re-subscribed by an import or a campaign report.
- **Imports** read the column names common providers export (Mailchimp, Kit/ConvertKit, MailerLite, Bandcamp, spreadsheets). Rows without a status column take the status you choose, so a provider's separate "unsubscribed" export can be imported correctly. Opt-in timestamps count as consent; a plain "date added" doesn't.
- **Within one file**, if the same address appears as both subscribed and unsubscribed, unsubscribed wins.
- **Resubscribing** a suppressed address by hand requires confirming the person asked and recording how.
- **Deleting** a subscriber is possible (for erasure requests) but the app recommends marking them unsubscribed instead, because deletion also removes them from the do-not-email list.
- **Sending** happens in the artist's email provider. The app exports the approved content (HTML and text), the recipient list, and the suppression list, then imports the provider's per-recipient report to record results.

## Data and reliability

- One JSON document, saved atomically on every change, with a daily backup kept for 14 days.
- Older files keep opening after updates: missing fields are filled from defaults before decoding (`TolerantDecoding`), and this is tested with a file that lacks newer fields.
- The activity log keeps the last 3,000 entries; undo data is kept for the most recent 300 changes to keep the file small.
- Undo warns before discarding later edits to the same records.

## Updates

- Manager uses the same release and update method as Freeman's other Mac apps: a `## x.y.z` section pushed at the top of `CHANGELOG.md` makes GitHub build, sign ad hoc and publish `Manager-<version>-mac-arm64.zip` as a release, and the shared `GitHubReleaseUpdater` package in the app installs it. No signing keys or repository secrets are involved.
- Before installing, the download must match GitHub's published SHA-256 checksum, be Manager (same bundle identifier) at the release's version, and pass `codesign --verify --deep --strict`. Anything that fails is left uninstalled and the current version keeps running.
- Updates download in the background (if allowed) and install when the artist quits or clicks Restart Now. A small script swaps the app after it quits, keeps the previous version in `~/Library/Application Support/Manager/Updates/Previous`, and puts it back if the move fails. Every step is logged to `~/Library/Logs/Manager/update.log`. No Terminal window opens.
- Builds are signed ad hoc, so the first install needs Privacy & Security › Open Anyway once.
- Manager is a Swift package rather than an Xcode project, so the workflows build it with `swift build` (through `Scripts/build.sh`) instead of `xcodebuild`. The release steps, asset name and updater are otherwise identical to the shared standard.

## Technical

- SwiftUI on macOS 14+, Swift Package Manager (no Xcode project to maintain). The package builds the app on macOS and only the Foundation-based core on Linux, so the same tests run in CI on both.
- No third-party dependencies. The updater is Freeman's shared `GitHubReleaseUpdater` package, included in `Packages/`.
- Accessibility: status is always shown with an icon and words, never color alone; icon-only buttons have labels; headers are marked; lists and rows read as one element where it helps VoiceOver.
