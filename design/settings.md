# Settings

Status: in effect (redesign default since step 6). The bottom of Settings and
the About page were revised on October 22, 2026.

This is the product-layer contract for Settings: what it holds, in which order
and in which words. Each platform draws it in its own dialect (P2).

## Anatomy

1. **Identity header.** This device's name, and as its subtitle the device it
   works with ("Backs up to Pixel 8 Pro", "Receiving · 1 phone connected").
   Edit renames the device.
2. **Card (contextual).** At most one, only when something needs the user.
   It says the cause and offers one action. Today the only card is "BackupDuck
   couldn't open its data" with Retry. Photo access and Pro will use the same
   slot. While the engine is opening, values show "—" rather than guesses.
3. **Category rows.** Short nouns with their current value. Details live one
   level down. Only a choice that needs no explanation (appearance) is edited
   in place. Problems are marked on the row they belong to.
4. **Help and feedback** comes after the categories: Help Center, Send
   Feedback, and Rate BackupDuck where a store listing exists.
5. **About BackupDuck** is a group of its own, one row whose value is the
   version. The version appears nowhere else on the root.
6. **Footer links.** One centered line of small text, "Diagnostics ·
   Advanced Settings" (Chinese 诊断信息 · 高级设置; Pixel sentence case
   "Advanced settings"), for the few people who need them. They are not rows.
   Each page they open uses the same name as its link.

Groups keep the constitution's order: the role first, then general, then help,
then About.

### About BackupDuck

1. The author's words (reserved, see below).
2. **Version**, with the update status as its value where the app manages its
   own updates ("Up to date", "Update available", "Checking…"). Tapping it
   opens the update detail: status, Check for Updates and the automatic
   updates switch, without repeating the version. Store and TestFlight builds
   show the version only; the store manages updates.
3. **Privacy**: photos travel only between your own devices; BackupDuck has no
   cloud of its own.
4. **Open source & licenses**, **Website**. Rows that leave the app end with an
   outgoing arrow; rows that push end with the platform's disclosure.

### Send Feedback

One row that looks like its neighbours. It offers joining the user group and
emailing us with diagnostics attached; the person sees the attachment before
sending. With a single option available it opens that option directly.

### Reserved items

Some parts are designed and built but wait for content the product does not
have yet: the author's words, the feedback email address and the App Store
listing (for Rate BackupDuck). Each is driven by one optional value in one
place in code, marked TODO. While the value is missing the part is not shown
in production at all, with no placeholder; the design catalogs can show it with
sample content (`*-reserved` scenarios) for review. Add the value, review the
catalog scenario, and the part appears.

## Sender (iPhone, iPad, Mac)

Follows `feature-triage.md`: transfers, storage and log settings are automatic,
so they have no rows.

| Row | Value | Opens |
| --- | --- | --- |
| Auto Backup | On / Off / Pair First | Switch; Includes (media types, all by default; albums as a secondary entry) |
| Folders (Mac) | "2 folders" | The Folders position, where folders are edited |
| Appearance | System / Light / Dark | In place |
| Language | Current language | The system's per-app language setting |
| Help Center | — | Help, by task |
| Send Feedback | — | Menu: user group; email with diagnostics (reserved) |
| Rate BackupDuck | — | The store's review page (reserved) |
| About BackupDuck | "0.4.1" | About |

Footer links: "Diagnostics" (export and recent activity) · "Advanced Settings" (clear temporary files,
only specific albums).

In Advanced Settings, a failed clear replaces the group's footer with one line
in the failure tone, "Couldn't clear: <reason>". The row's own Clear Now is the
retry; there is no second Retry button.

Moved elsewhere: backing up earlier photos, pausing and keeping the screen on
during a large batch move to the hub.

## Receiver (Pixel)

| Section | Row | Supporting text | Opens |
| --- | --- | --- | --- |
| Receiving | Connected Devices | "1 · Lin's iPhone" | Connected devices |
| | Storage | "6.7 GB free · Auto cleanup off" (discovery dot) | Storage |
| General | Appearance | Current mode | Sheet |
| | Language | Current language | Sheet |
| Help & feedback | Help Center | — | Help, by task |
| | Send Feedback | "Join the user group, or email us with diagnostics" | Menu |
| (own group) | About BackupDuck | "Version 0.4.1" | About |

Footer links: "Diagnostics · Advanced settings" (export and recent activity; format
conversion, browser access, stop receiving).

### Help Center

One structure on every platform: a searchable list in two groups, "Things
to do" and "When something's wrong", each article a few short paragraphs in the
person's words, read-only (it explains and names the page where the action
lives; it starts nothing). Engineering detail and identifiers stay in
Diagnostics.

| Group | Sender (iPhone, iPad, Mac) | Receiver (Pixel) |
| --- | --- | --- |
| Things to do | Check that photos are safe · Back up faster · Switch to another Pixel · Back up only some photos · Free up space on the Pixel | Check that photos are saved · Keep receiving in the background · Free up space on this Pixel · Connect another iPhone or Mac |
| When something's wrong | Can't reach the Pixel · Some photos aren't backed up · A Live Photo can't be saved · Backup stopped | An iPhone or Mac can't connect · A photo wasn't saved to Photos · Storage is full and receiving paused · Receiving stopped · Auto cleanup didn't run |

Articles keep receipt, saving to Photos and Google's cloud upload apart and say
that BackupDuck cannot see the last. "An iPhone or Mac can't connect" may show
this Pixel's current address in a quiet line for someone helping.

### Diagnostics

Its one job: when something goes wrong, the person can send us a file that
lets us help. People do not read logs here; they export and send. Same
structure on every platform:

1. **One line**: what the file is for and the privacy promise ("If something
   goes wrong, send us this file. It contains no photos.").
2. **Export diagnostics**: the main row, with a small line naming the contents;
   it opens the system share or save sheet (on the Pixel the file includes the
   record of photos saved to Photos and what automatic cleanup observed, never
   the account name). Afterwards the line names the file, or
   says it failed and the row retries. Send Feedback offers the same file.
3. **Recent activity**: a short read-only list of the latest events in plain
   words with their time, newest first, grouped by day, so a person can see
   that something happened. No search, filters, per-field copy or entry pages.
   On Apple, the area title uses primary text (iPhone title3 semibold, Mac
   headline), aligned with the group's leading text inset; days use ordinary
   section headers below it.

The log keeps 14 days automatically. Technical probes and developer tools are
not part of the product, and no other page links to Diagnostics.

Resume after restart and heat protection are automatic. Freeing space after
saving to Photos and the experimental automatic cleanup are on the Storage
page, under "Free up space automatically", not in Settings. There is no
Experiments page.

## Platform dialects

- **iPhone:** a grouped list with no section headers, colored icon tiles from
  the system palette and disclosure rows. A large title, with Edit in the
  navigation bar. The tiles only help users find rows; they never carry state.
- **Mac:** the Settings position shows a list column (identity header,
  category rows) and a detail pane with a grouped form, as System Settings
  does. ⌘, opens it.
- **Android:** Material 3 sections with headers, monochrome leading icons,
  headline and supporting text, switches at the end and no chevrons.

## Copy

- Row labels are short nouns ("Transfers", "Storage"), not sentences.
- Values are a few words in the user's terms ("4 at a time", "300 MB used").
- Footers under a switch say in one sentence what changes. Engineering detail
  goes to Help.

## Open

- Paid: no row or card until D1 is decided. It will use the card slot and a
  row of its own.
- Whether the Devices position becomes a row here instead of a tab is part of
  D3 (closed October 18: it is a row).
