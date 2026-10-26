# Main flows

Status: proposed, for review. These are the three journeys of
`product-brief.md`: first run, every day, and when something goes wrong. They
follow `feature-triage.md` and the interaction standards (`interaction.md`).

Copy is quoted in English; the Chinese copy reviewed with the owner is in
`flows.zh.md`. Words follow `copy-glossary.zh.md`.

## Principles

- **Say the whole journey first.** One screen names the three steps with three
  distinct marks: a yellow circle, the blue wing and an orange sparkle, sized to
  the same visual weight and without numerals. Every later step shows the row of
  three with the current mark in its colour and the others neutral and faint, so the
  person always sees where they are in the journey.
- **One decision per screen, primary action in a fixed place.**
- **Explain before the system asks.** Camera, photos and notifications each get
  one sentence of why, then the system prompt. Refusing never blocks the
  journey; the hub shows what is missing.
- **Show value early.** The first photo landing on the Pixel is the first
  reward. Notifications are asked after it, not before.
- **Partial results count.** What is already safe is shown while the rest
  continues, with honest counts.
- **Link like a desktop app is linked.** The device being added shows a code;
  the device you already hold scans it.
- **Space actions show their effect and consequence together** ("Free 3.2 GB ·
  your photos stay in the Pixel's Photos").
- **The duck appears for brand moments only** (welcome, connecting, empty, done,
  all caught up), never on errors or warnings.

## 1. First run

First run stays until it is completed. An interrupted flow (the app killed,
Back, a restart) reopens at the step it reached, before the hub draws. A
reinstall starts at Welcome: a pairing left in the keychain by a deleted
installation is discarded. The app touches the network only once a receiver
has completed a connection, or an explicit connection attempt starts after a
code is read. Merely entering the scan step must not touch the network; see the
iPhone connect contract below.

### iPhone (Mac first run remains planned)

| Step | Screen | Primary action | Notes |
| --- | --- | --- | --- |
| 1 | **Welcome.** Headline: "Bigger than iCloud. Simpler than a NAS. And free." Subline: "One old Pixel backs up all your photos to Google Photos, full quality, without limits." Steps: ① Install BackupDuck on a Pixel ② Connect the two devices ③ Photos back up to Google Photos · free and unlimited. Small print: "Original Pixel: unlimited Original quality. Pixel 2 to 5: unlimited Storage saver. The offer is Google's." Welcome duck | Get Started | The bold value line follows the brief |
| 2 | **Install on the Pixel.** A QR code that opens the Pixel download page in the Pixel's camera; the address as text below | It's Installed | Skipped if a Pixel was paired before |
| 3 | **Connect.** One sentence on why the camera is needed, then the scanner. On success: "Connected to Pixel 8 Pro" with the connecting duck | Scan the code on your Pixel | Mac shows its own code for the Pixel to scan instead |
| 4 | **Photos.** "BackupDuck reads your photos and sends them straight to your Pixel, never through our servers." then the system prompt | Continue | iPhone keeps three benefits in one aligned symbol column: direct to the Pixel, no upload to BackupDuck servers, and full quality without compression. Denial stays on this step with the photo-access explanation, Open Settings and Later; Later ends first run on the hub. Returning with full or limited access advances automatically. Limited access counts only the allowed photos and retains the limited-access note |
| 5 | **Earlier photos too?** Use the earlier-photo question with the actual accessible count as the sole page heading. Keep the step marks, new-photo subtitle, recent-media strip (up to four accessible photos and videos, with poster frames and library duration badges), background-transfer note and conditions link in the content; do not add another question heading. New-photo backup is on, explained in one line without a switch. Show an approximate size only if a supported source supplies it; do not guess. The note says: "However many there are, they can finish sending in the background. If your Pixel runs low on space, you can free up photos already backed up to Google Photos." Learn More explains storage conditions | Back Up Everything | Secondary: Only New Photos; the only decision is whether to include earlier photos |
| 6 | **First photo lands.** The first thumbnail travels between two graphite front-view phone illustrations (Illustrations.xcassets DeviceIPhone / DevicePixel, derived artwork without logos): the iPhone has a Dynamic Island and the Pixel a centred punch-hole camera; both screen openings have the same height, the photo sits under each bezel, and the Pixel's screen is dark until the photo lands. Labels use the device kinds iPhone and Pixel above the unchanged destination labels, without generated device names. A thin shared progress bar under the devices uses only the job’s confirmed/total bytes, with Sending and the byte counts; before bytes are known, show Preparing the photo. Symmetric labels and centered title/status share one axis. The approved done duck appears on confirmed arrival, then "Your first photo is in the Pixel's Photos". The moving tile and both screen tiles share one thumbnail, rectangular crop and corner radius; its start and landing frames exactly match the screens. Keep the existing 0.75-second curve and 0.15-second hold. One orchestrated motion; crossfade without travel under Reduce Motion | OK | Then one sentence on notifications ("We only notify you when something needs you") and the system prompt |
| 7 | **Hub.** Progress card for earlier photos, keep-screen-on switch while a large batch runs, Live Activity on the lock screen | — | First run ends here. Only New Photos skips the first-photo step and ends first run on the hub; until an earlier-photo run starts, the hub says new photos are saved (never "all photos") and offers Earlier Photos with one Back Up action, using the Auto Backup scope. |

### Mac first run gap

For 0.5.0, the empty Overview says that photos are kept on the Pixel and that
connecting will ask for access to the Mac photo library. Connect Pixel stays the
primary action. The complete Mac first-run flow is the first item after 0.5.0;
this empty state does not establish wizard completion.

### iPhone connect: permission and startup order

The redesigned scanner answers one question: connect this iPhone to the Pixel
whose code is being scanned. Merely entering or restoring the scanner is not
connection intent. First run and the later Connect/Reconnect sheet use the same
scanner and recovery states.

1. **Scan:** request only Camera access. Local queue opening (`open_sender`),
   identity and setup-state reads remain available without networking. Do not
   start path monitors, Bonjour browsing, background URLSession, diagnostics
   network observation, receiver probes, profile exchange or processing watches.
   An unfinished Welcome/Install/Scan restoration keeps these workers stopped,
   even if saved trust exists. Do not prewarm or open the photo library behind
   the first-run scanner.
2. **Camera denied:** keep the scanner's explanation and **Open Settings** on
   the current page (in first run, in the fixed action area). Returning from
   Settings rechecks camera authorization. A grant restarts only the camera;
   continued denial does not start a connection or repeat permission requests.
3. **Code read:** decode the code, then begin one explicit connection attempt.
   Codes that cannot be decoded do not start networking. A future manual-address or
   nearby-connect action must enter this same explicit connection boundary;
   displaying its choice must not browse automatically.
4. **Wireless path, then local connection:** start general path observation
   first and wait for an available Wi-Fi/Ethernet path while the app is active.
   Only then open a TCP connection to the scanned address, with cellular
   prohibited. This is where local-network access is needed. No Bonjour browser
   or transfer session competes with this attempt. Permission-dialog time does
   not consume the foreground connection timeout. The preflight sends no
   application data; Rust subsequently verifies the pinned TLS identity and
   receiver before saving trust.
5. **Connected:** only after authenticated pairing succeeds, start receiver
   availability, route discovery, processing observations, diagnostics network
   sampling and the transfer executor. Existing queue pause intent is retained.

The intended system sequence is Camera at Scan; wireless-data access, where
the region requires it, at Connect; then Local Network. The app serializes its
operations, but iOS owns dialog timing and remembers decisions. There is no
public combined WLAN/local-network authorization query or API that promises a
particular regional alert sequence. Do not store a synthetic permission grant or
claim an unavailable path proves denial. Report a specific blocked privilege
only when Network.framework supplies that reason; otherwise say to check the
same Wi-Fi, WLAN access and Local Network in Settings.

On local-network denial, preserve the scanned code and show **Open Settings**
with one secondary **Retry** in the current connect flow. Show **Scan Again**
only after a retry establishes that the code is invalid or expired. Returning from Settings
does not retry networking automatically. Retry reuses the code; Scan Again
discards it and returns to the camera. Do not start workers after a failed or
cancelled attempt, and do not replace existing trust on failure. Terminating and
relaunching onto Scan starts only the camera/recovery state. System decisions
are owned by iOS; the app must not force new prompts through background retries.

Catalog camera-denied and network-recovery scenarios are synthetic UI evidence.
Regional wireless/local-network dialog order and persisted system denial require
separate physical-device acceptance; a simulator does not establish them. The
Network.framework denial checks follow Apple's
[local-network privacy guidance](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

### Pixel

System Back returns to the preceding first-run screen. Within Connect, Back
first returns from the Mac direction to the iPhone code; Back from the camera
returns to the Mac explanation. From Google Photos, Back returns to Connect
rather than replaying a transient connection confirmation. At Welcome, Back
moves the task to the background without completing first run. Returning or
relaunching resumes the saved step; only a final Free Space choice completes
the guide. Recreation preserves the Connect direction and pending scanner
result ownership.

Keep-running rows read the current system access on every return. Granted
items show Allowed; missing access explicitly shows Not allowed. Denying a
prompt does not grant access or complete the guide. Once each missing item
has been requested, Next lets the person continue with those restrictions.

| Step | Screen | Primary action | Notes |
| --- | --- | --- | --- |
| 1 | **Welcome.** The same headline as the iPhone, "Bigger than iCloud. Simpler than a NAS. And free." Subline: "This old Pixel receives the photos on your iPhone and backs them up to Google Photos, full quality, without limits." The same three marks and small print | Get Started | |
| 2 | **Keep it running.** Stay on Wi‑Fi; allow notifications and battery exemption so receiving keeps going. Plugging in is suggested as optional | Allow | Each system prompt explained first, then asked one at a time (battery uses the system's per-app dialog, not the settings list); rows show Allowed or Not allowed from system access; Next once each missing item has been asked |
| 3 | **Pairing code**, full screen: "Scan with BackupDuck on your iPhone". Secondary: Connect a Mac instead (scan the Mac's code) | — | The screen blocks screenshots, as today |
| 4 | **Connected.** "Connected to Lin's iPhone" | Next | |
| 5 | **Google Photos.** "Photos are saved to this Pixel's Photos. They upload once backup is on in Google Photos." | Open Google Photos | Secondary: It's already on. We cannot read Google Photos' backup state, so we never claim it is on |
| 6 | **Free up space.** Show the system Smart Storage state (On, Off, or State unavailable), read from the system. Explain that it removes device copies backed up by Google Photos. | Open system Smart Storage | Opens the system settings, with storage settings as fallback. Below the Smart Storage card, align the cloud-retention sentence and the quiet Try auto cleanup (experimental) link to its text edge. That link opens the existing cleanup page, which owns the accessibility explanation. The bottom actions are Open system Smart Storage and Not now only. Complete first run after a successful settings handoff or an explicit secondary choice. Offer auto cleanup again only when space runs low |
| 7 | **Hub**: waiting for photos, with the empty duck | — | |

## 2. Every day

The hub answers "are my photos safe?" in one line, then shows only what is
happening or needs the user.

### iPhone hub states

| State | Top line | Below |
| --- | --- | --- |
| All caught up | "All your photos are in the Pixel's Photos" · last backup time | Latest photos strip; the all-caught-up duck |
| Backing up | "Backing up 128 photos · about 2.1 GB" with progress | Current photo thumbnail; keep-screen-on switch above a size threshold; Pause |
| Earlier photos | Saved-to-Photos count / frozen membership total once the core has finished counting; otherwise "Counting earlier photos…" | Shared Apple card; Pause / 暂停 pauses scanning and Resume / 继续 resumes it, separately from pausing sending. Paused / 已暂停 names its paused state. Mac places this action trailing in the title row like the running card; iPhone retains the action below the text. Never substitute scanned or prepared counts for saved counts |
| Waiting for the Pixel | "Continues when the Pixel is back on Wi‑Fi" | New photos are kept in order; no action needed |

- **A photo's state** says only what we know: "In the Pixel's Photos · today 10:42", or
  "Received, saving to Photos", or the cause of a failure. Google Photos' state is not
  available to us, so it is not shown per photo; it appears in first-run setup
  and in Help ("Open Google Photos to check"). We never claim cloud backup.
- **Lock screen:** a Live Activity while a batch runs: count left, progress
  ring, pause. It ends when the batch ends.
- **One switch, several conditions.** Auto Backup stays a single switch for
  ordinary users. Its page states when it actually runs ("Runs whenever your iPhone and Pixel
  are on the same Wi‑Fi"), and when a condition is not met the hub names that condition
  instead of a generic "paused" (see section 3).
- **Rating** is asked once, at the moment earlier photos finish backing up, after
  the user has seen the result. Never
  during first run or after a problem.
- **Notifications** only when the user is needed or a long task finishes:
  earlier photos all backed up; the Pixel unreachable for 24 hours; Pixel
  storage full; a photo needs conversion. No routine "backed up" notices.

### Pixel hub states

| State | Top line | Below |
| --- | --- | --- |
| Receiving | "Receiving photos from Lin's iPhone · 34 to go" | Latest items |
| Idle | "128 photos today, all saved to Photos" | Space card when relevant |
| Space freed | "Freed 3.2 GB; your photos stay in Photos" | Shown after freeing runs |

Device readings (temperature, space, battery) stay hidden while normal and
appear as one line when they matter.

### Hub rules (implemented in the catalogs, approved October 18, 2026)

- One state at a time, in this order: not paired, opening, paused, problems,
  backing up or receiving, caught up, empty. Pausing is the user's choice and
  outranks problems, because nothing is checked while paused.
- "All your photos are in the Pixel's Photos" appears only when every received
  photo is saved there. Otherwise the hub says the photos reached the Pixel and
  how many are still being saved (P3).
- The keep-screen-on switch appears only while 50 or more photos remain.
- The Pixel shows free space only in the space card, or as a hint when less
  than 15% remains and auto cleanup is off. Readings are the device's own.
- The Pixel hides recent items until something has been received, and hides
  them while receiving is off or no device is paired.
- First run: the title follows the flight, so the screen never says the photo
  landed before it is seen landing. Reduce Motion adopts the settled state in
  one frame.

## 3. When something goes wrong

Each problem says the cause, what happens by itself, and at most one action. It
appears in the hub of the device where the user can act, and on the affected
items. It becomes a notification only when it lasts.

| Problem | Where | What the user reads | Happens by itself | Action |
| --- | --- | --- | --- | --- |
| Pixel unreachable | iPhone hub | "Can't reach Pixel 8 Pro. New photos wait in order and continue when it's back." | Retries; resumes in order | What to do → checks with the likely cause first (same Wi‑Fi, Pixel on, app running) |
| Pixel storage full | Both hubs | Pixel: "Almost full, so receiving is paused. Photos Google Photos has backed up can be removed from this Pixel, about 18 GB; they stay in Google Photos in the cloud." iPhone: "The Pixel is out of space; paused." | Resumes when space returns | Pixel: Turn on auto cleanup · Free up space in Google Photos |
| Photo access off or limited | iPhone hub | "BackupDuck can't see your photos." / "BackupDuck can only see the photos you picked." | — | Open Settings |
| Live Photo needs conversion | Apple hub and affected items; Pixel problem group | "This Live Photo can't be saved to the Pixel's Photos as is." One short note: "Kept safely on the Pixel." | Kept safely on the Pixel; not converted | Apple: What Can I Do? / 怎么办 opens the Live Photo help article. Pixel: View opens the explanation sheet linking to Advanced settings |
| Pixel no longer trusts this iPhone | iPhone hub | "The Pixel no longer recognizes this iPhone. Scan its code again to reconnect." | Pauses | Reconnect |
| Not enough space on the iPhone to prepare photos | iPhone hub | "Not enough space on the iPhone to prepare photos; paused." | Resumes when space returns | View iPhone Storage |
| Pixel too hot | Pixel hub; iPhone status line | "The Pixel is too hot; it continues once it cools down." | Resumes after cooling | — |
| Running in the background on iPhone | iPhone hub while a batch waits | "BackupDuck is slower in the background; open it to go faster." | Continues when the system allows | Keep-screen-on switch |

When the paired connection reports local-network denial, the hub shows "BackupDuck can't use the local network" at the unreachable-problem priority with Open Settings; iPhone asks to enable Local Network, while Mac asks to turn BackupDuck off and on again in Local Network settings.

Every failure message comes from the same state the item shows, so the hub,
the item and any notification never disagree (P3).

## Platform notes

- The Pixel apps use Material 3's standard navigation bar and monochrome icons,
  per the constitution's platform layer.
- Mac settings keep a limited line width in the detail pane; the photo viewer
  opens in its own dark window.

## Open

- The Pixel download page (step 2) needs a stable address and a page for the
  APK; it is outside the apps.
- D3 is closed (October 18): Devices is the identity header and a Settings row.
- Live Activity and Mac menu bar details are designed with the hub.

## How the Pixel keeps space free

The copy in the Pixel's Photos stays on the Pixel until Google Photos has
uploaded it and the device copy is removed. BackupDuck cannot see which photos
Google Photos has backed up, so only Google's own tools can remove them safely:

1. **System Smart Storage** (baseline): removes backed-up photos automatically.
   Confirm on the device whether its age rule counts from capture or backup
   before describing it in copy.
2. **Auto cleanup (experimental, optional)**: BackupDuck taps Google Photos'
   "Free up space" through the accessibility service when space runs low.
   Google still decides what is safe to remove. It needs a clear consent screen
   and stays an experiment until it proves reliable across Google Photos
   versions.

BackupDuck's own copy is freed separately by "free up space after saving to
Photos" (`feature-triage.md`).

Pixel terminology is "Free up space" for the section, "Auto cleanup
(experimental)" for the feature, and "Free up space" for the action. Storage
shows Smart Storage's observed On/Off state (unknown is explicit). The auto
cleanup detail leads with its stored On/Off state and then the current result.
BackupDuck-copy removal has its own group and says that photos stay in the
Pixel's Photos. Only Smart Storage and Google Photos cleanup share the cloud
retention footnote.

### Auto cleanup journey (Pixel, Storage)

Everything an ordinary person needs for auto cleanup lives on the Storage page;
Diagnostics keeps only technical probes and reports.

- **Turning it on** is one journey from the Storage switch: the consent sheet,
  then the system Accessibility setting. The access step explains that BackupDuck
  comes back once access is turned on. For ten minutes after opening Settings,
  the accessibility service connection brings the saved cleanup journey back to
  the front automatically. The current step survives process death; returning
  manually also re-checks access. Without access, the switch stays off and the
  person can retry. After access is confirmed, BackupDuck confirms which Google
  Photos account it will act in by opening Google Photos for a few
  seconds ("Checking your Google Photos account…"). Only then is the switch on.
  The account is shown as confirmed, never by its address (BackupDuck keeps
  only a fingerprint). Leaving any step leaves the switch off and says why.
- **The switch row's supporting line** is the one place for its state, in the
  same short register as its neighbours. When the person must act, one tonal
  button sits under the row:

  | State | Supporting line | Action |
  | --- | --- | --- |
  | On, idle | Frees space when it runs low | — |
  | Running | Freeing space… | Stop |
  | Result uncertain (pending, needs review, not recognised, could not return, timed out) | Check the result in Google Photos | Open Google Photos, then "I've checked" once back |
  | Account changed or unknown | Google Photos is using another account | Confirm account |
  | Accessibility turned off | Accessibility access is off | Turn on |
  | Pixel locked | Waits until the Pixel is unlocked | — |
  | Google Photos unavailable | Can't open Google Photos | Open Google Photos |

- **Tapping the row** (not the switch) opens an Auto cleanup page: the same
  state, the last result ("Freed 2.3 GB · Oct 19" or "Nothing to free"), Run
  now, Confirm account again, one paragraph on how it works and what Google
  decides, and a quiet link to Diagnostics.
- Stopping never undoes what Google Photos already started; "I've checked"
  records the person's review, not a result. No amounts are invented.


### Apple recovery and overview composition

For a Live Photo that the Pixel cannot save as received, retain receipt as a
separate fact. Apple problem cards and history rows say only "Kept safely on the
Pixel." Their one What Can I Do? / 怎么办 action opens the existing Live Photo
help article. The Pixel problem card uses the same short note; its existing
explanation sheet holds the procedure and links to Advanced settings. The
article/explanation says the Pixel's Photos cannot save these Live Photos as
they are, and gives the path on the Pixel: BackupDuck › Settings › Advanced
Settings › Format Conversion. Explain there that the video part loses a little
quality. Apple does not issue a conversion request or infer cloud upload.

The Apple recent-photo section has one Backup History entry below it; its heading
has no second See All link. A card describing photos that need attention replaces the matching Needs
You summary; an unrelated offline problem does not hide it. Mac hides the folder summary when no folders have been added.
Connection dots use verified connection only, independent of backup outcomes;
iPhone Settings omits that dot. Mac filtered Backup History retains cause and
retry cards, a Needs You subtitle and a removable toolbar marker that repeats the filtered
count and shows all records when cleared. Keep this marker short enough to
remain visible in a narrow window; the receiver name stays in the full scope
subtitle and accessibility label.

### iPhone first-run return and calm evidence

Every first-run step after Welcome has the native navigation Back action.
Returning changes saved presentation intent only: pairing and registered backup
work remain durable. Busy permission/registration work temporarily disables
Back. A photo-access explanation gives one reason and three aligned, fixed-icon
points: direct to the Pixel, never through BackupDuck servers, and full quality
without compression (原画质，不压缩) before Continue opens the system prompt.

The iPhone and Mac calm hubs show up to eight distinct recently saved items. Six to eight
items fill two balanced rows; five retain the complete shared mosaic, and fewer
use a strip. Each thumbnail keeps the same shared viewer route and recorded
identity; fewer available items never produce invented photos or timestamps.

### Reading third-party notices

Settings → About → Source code & licenses → Third-Party Software (Apple) /
Third-party software (Pixel), named 第三方软件 in Chinese, opens one
offline plain-text reader. Scroll, select and copy within the document; Back
returns to the source/license page. There are no per-component destinations.
Apple uses the document for the current distribution, with Sparkle only in the
direct Mac build; Android combines its release libraries and Rust crates.

### Receiver reachability on iPhone

A network path update retains the hub’s last reachability state while an
authenticated probe runs. Only actual probe failure is outage evidence: show
unreachable after it persists for ten seconds or after two consecutive failed
probes. Clear the problem immediately on a successful probe. Preparation remains
gated by the actual probe result throughout this display grace period.

### Earlier-photo card lifetime on iPhone

Scanning and saving retain their current progress states. Complete wording
requires `HistoricalImportStatus.isSaved`, including publication of every frozen
member. Persist the first time that completed state is shown, scoped by receiver
and run; hide the card after 24 hours. Scanned membership and adding work to the
queue do not establish completion; keep the saved-progress note while saving.
