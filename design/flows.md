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

### iPhone (and Mac)

| Step | Screen | Primary action | Notes |
| --- | --- | --- | --- |
| 1 | **Welcome.** Headline: "Bigger than iCloud. Simpler than a NAS. And free." Subline: "One old Pixel backs up all your photos to Google Photos, full quality, without limits." Steps: ① Install BackupDuck on a Pixel ② Connect the two devices ③ Photos back up to Google Photos · free and unlimited. Small print: "Original Pixel: unlimited Original quality. Pixel 2 to 5: unlimited Storage saver. The offer is Google's." Welcome duck | Get Started | The bold value line follows the brief |
| 2 | **Install on the Pixel.** A QR code that opens the Pixel download page in the Pixel's camera; the address as text below | It's Installed | Skipped if a Pixel was paired before |
| 3 | **Connect.** One sentence on why the camera is needed, then the scanner. On success: "Connected to Pixel 8 Pro" with the connecting duck | Scan the code on your Pixel | Mac shows its own code for the Pixel to scan instead |
| 4 | **Photos.** "BackupDuck reads your photos and sends them straight to your Pixel, never through our servers." then the system prompt | Continue | Limited access: say what will and won't back up |
| 5 | **What to back up.** Auto Backup on (switch shown on), with when it runs: "Runs whenever your iPhone and Pixel are on the same Wi‑Fi". "Back up your 12,384 earlier photos too? About 86 GB; however many there are, they all fit." No Pixel free-space figure: the Pixel frees space as it goes | Back Up Everything | Secondary: Only New Photos |
| 6 | **First photo lands.** The first thumbnail travels to the Pixel mark, then "Your first photo is in the Pixel's Photos". One orchestrated motion; static under Reduce Motion | OK | Then one sentence on notifications ("We only notify you when something needs you") and the system prompt |
| 7 | **Hub.** Progress card for earlier photos, keep-screen-on switch while a large batch runs, Live Activity on the lock screen | — | First run ends here |

### Pixel

| Step | Screen | Primary action | Notes |
| --- | --- | --- | --- |
| 1 | **Welcome.** The same headline as the iPhone, "Bigger than iCloud. Simpler than a NAS. And free." Subline: "This old Pixel receives the photos on your iPhone and backs them up to Google Photos, full quality, without limits." The same three marks and small print | Get Started | |
| 2 | **Keep it running.** Stay on Wi‑Fi; allow notifications and battery exemption so receiving keeps going. Plugging in is suggested as optional | Allow | Each system prompt explained first |
| 3 | **Pairing code**, full screen: "Scan with BackupDuck on your iPhone". Secondary: Connect a Mac instead (scan the Mac's code) | — | The screen blocks screenshots, as today |
| 4 | **Connected.** "Connected to Lin's iPhone" | Next | |
| 5 | **Google Photos.** "Photos are saved to this Pixel's Photos. They upload once backup is on in Google Photos." | Open Google Photos | Secondary: It's already on. We cannot read Google Photos' backup state, so we never claim it is on |
| 6 | **Free space automatically.** System Smart Storage shown as on (it removes photos Google Photos has backed up; on by default on the test Pixel XL). Recommends turning on auto cleanup (experiment): "When space runs low, BackupDuck taps Free up space in Google Photos for you. It needs accessibility access, used for this only." | Turn on auto cleanup | Secondary: Not now. Offered again when space runs low |
| 7 | **Hub**: waiting for photos, with the empty duck | — | |

## 2. Every day

The hub answers "are my photos safe?" in one line, then shows only what is
happening or needs the user.

### iPhone hub states

| State | Top line | Below |
| --- | --- | --- |
| All caught up | "All your photos are in the Pixel's Photos" · last backup time | Latest photos strip; the all-caught-up duck |
| Backing up | "Backing up 128 photos · about 2.1 GB" with progress | Current photo thumbnail; keep-screen-on switch above a size threshold; Pause |
| Earlier photos | Task card "Earlier photos 3,210 / 12,384" | Runs in the background once started; pause only |
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
| Live Photo needs conversion | The item, and a hub line with a count | "This Live Photo can't be saved to the Pixel's Photos as is." | Kept safely on the Pixel; not converted | Convert and save (video quality drops) · Send feedback |
| Pixel no longer trusts this iPhone | iPhone hub | "The Pixel no longer recognizes this iPhone. Scan its code again to reconnect." | Pauses | Reconnect |
| Not enough space on the iPhone to prepare photos | iPhone hub | "Not enough space on the iPhone to prepare photos; paused." | Resumes when space returns | View iPhone Storage |
| Pixel too hot | Pixel hub; iPhone status line | "The Pixel is too hot; it continues once it cools down." | Resumes after cooling | — |
| Running in the background on iPhone | iPhone hub while a batch waits | "BackupDuck is slower in the background; open it to go faster." | Continues when the system allows | Keep-screen-on switch |

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
2. **Auto cleanup (experiment, recommended)**: BackupDuck taps Google Photos'
   "Free up space" through the accessibility service when space runs low.
   Google still decides what is safe to remove. It needs a clear consent screen
   and stays an experiment until it proves reliable across Google Photos
   versions.

BackupDuck's own copy is freed separately by "free up space after saving to
Photos" (`feature-triage.md`).

### Auto cleanup journey (Pixel, Storage)

Everything an ordinary person needs for auto cleanup lives on the Storage page;
Diagnostics keeps only technical probes and reports.

- **Turning it on** is one journey from the Storage switch: the consent sheet,
  then the system Accessibility setting, then, on return, BackupDuck confirms
  which Google Photos account it will act in by opening Google Photos for a few
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

