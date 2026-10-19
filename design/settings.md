# Settings

Status: proposed, under review in the design catalogs. Production apps keep
their current settings until migration step 6 in `constitution.md`.

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
4. **Help** comes last.
5. **Footer.** The version, plus a quiet link to diagnostics. These are not rows.

Groups keep the constitution's order: the role first, then general, then help.

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
| Feedback Group | Telegram | The tester group, while it is offered |
| About BackupDuck | — | Version, website, Check for Updates (Mac) |

Footer: "BackupDuck 0.4.1 (88)" · "Diagnostics" (activity log) · "Advanced"
(clear temporary files, only specific albums).

Moved elsewhere: backing up earlier photos, pausing and keeping the screen on
during a large batch move to the hub.

## Receiver (Pixel)

| Section | Row | Supporting text | Opens |
| --- | --- | --- | --- |
| General | Connected Devices | "1 · Lin's iPhone" | Connected devices |
| | Appearance | Current mode | Sheet |
| | Language | Current language | Sheet |
| Help | Help Center | — | Help, by task |
| | Experiments | — (discovery dot) | Experiments |

Footer: "BackupDuck 0.4.1" · "Check for Updates" · "Diagnostics" (log report) ·
"Advanced" (format conversion, browser access, stop receiving).

Resume after restart and heat protection are automatic. Freeing space after
saving to Photos is a switch on the Storage page, not in Settings.

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
