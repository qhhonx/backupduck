# Interaction standard

Status: approved direction (owner, October 19, 2026); details are adjusted in
native review. Companion to `visual-language.md`. Durations and gesture rules
are in `backupduck-v1/motion.md`; flows are in `flows.md`. Each item has an
identifier (I1–I9) that reviews and code comments cite.

## I1 Navigation

Three positions on every platform (`navigation.md`):

| | iPhone | Mac | Pixel |
| --- | --- | --- | --- |
| Positions | Tab bar: Photos, Backup, Settings | Sidebar: Photos (Photo Library, Folders), Backup (Overview, History), Settings | Navigation bar: Receive, Photos, Settings |
| One level down | Push | Replace the main area; History has its own sidebar row | Push |
| Detail, explanation, chooser | Sheet | Sheet or popover | Bottom sheet or full-screen dialog |
| One photo | Zoom from the tile into a full-screen viewer | Its own dark window | Full-screen viewer |
| Devices | Identity header in Settings and a Settings row (D3) | Same | Same |

## I2 Page types

Every page declares one content type (`constitution.md` § Content types) and
uses that type's skeleton:

| Type | Skeleton |
| --- | --- |
| Task center (hub) | Large title with the device pill; one status or problem card; recent photos as evidence; summary rows that open filtered views. No primary action while calm. |
| Browse | The grid starts at the top with the title floating over it; views live in the existing menu; the active view shows a dismissible pill. Each view keeps its own scroll and date anchor. |
| Preferences | Identity header; at most one contextual card; category rows with current values; help; a quiet footer (version, diagnostics, advanced). At most eight rows. |
| Guided flow | Step marks; title and one sentence; the one decision; the primary action fixed at the bottom with an optional text action below. |
| Detail | The photo, when it was taken, the two facts with times, at most one action, a quiet file footer. |
| Chooser | Search, the current selection summary, a virtualized list, Done. Large sets never expand inside a preference group. |
| Explanation | A sheet ordered by likelihood or by task, never by internal module. |

## I3 States

One state at a time. Hub order: not paired, opening, paused, problems, backing
up or receiving, caught up, empty (`flows.md` § Hub rules).

| State | Says | Shows | Never |
| --- | --- | --- | --- |
| Opening | Values read "—" | The final geometry | Guess values, move the layout |
| Empty | "Nothing here yet", one sentence | The duck and one action | Merge with no access or a read failure |
| No access | The cause | "Open Settings" | Show the duck, block other features |
| Working | Count and size, real progress | A 2–3 pt bar inside the stable card | Add rows, invent remaining time |
| Problem | Cause, what happens by itself | At most one action | Color the title, stack warnings |
| Calm | "All your photos are in the Pixel's Photos" | Recently saved photos | Say "all" before every photo is saved |

## I4 Actions

- At most one primary action per context: a filled capsule, fixed at the
  bottom in guided flows.
- Actions inside a card are tinted capsules, never link text.
- Switches apply at once; nothing needs Save.
- Destructive actions live in menus with confirmation and precise words
  ("Stop receiving from this device", not "Delete").
- A confirmation saves intent and returns to the task screen; failure keeps the
  user's input and selection.

## I5 Feedback

- Every press responds within 80–120 ms; system controls keep their own.
- Haptics: one success when a device connects and when the first photo is saved;
  a selection tick when a view changes; nothing for routine progress.
- State changes replace content in place; no toasts. Notifications only when the
  user is needed or a long task ends (`flows.md` § Every day).
- Retrying never plays a completion animation.

## I6 Continuity

- Returning restores scroll, date anchor, view and selection.
- Grid to photo uses the zoom transition and returns to the same tile.
- Hub summaries open the matching view ("Needs you" opens the Needs you view).
- Notifications open the photo or problem they describe.
- A narrow Mac window keeps detail and back reachable and keeps focus.

## I7 Motion

- System transitions for push, sheet, zoom and menus. Custom motion only for an
  orchestrated moment, at most one per flow: the first photo flying to the
  Pixel (about 1.2 s, once).
- Status replacement fades in place over 120 ms without changing card size; an
  inserted problem card arrives on a critically damped spring and the content
  below moves as one block.
- A connected device rises 12 pt and fades in over 220 ms.
- Nothing loops, bounces or breathes. Reduce Motion adopts the final state;
  low power on the Pixel and older devices drop decorative motion.
- Motion is judged on Release builds from 60 fps recordings (`AGENTS.md`).

## I8 Copy

- The user's words (`copy-glossary.zh.md`): photos, your Pixel, Photos, Wi‑Fi.
- Results say "in the Pixel's Photos"; nothing claims cloud backup.
- Counts state their scope: this batch, all, this Pixel.
- Titles are nouns; a state is one full sentence; a problem says the cause, what
  happens by itself and what the user can do.

## I9 Accessibility

- Dynamic Type up to the largest accessibility size: rows grow, text wraps,
  nothing truncates. The Pixel follows the system font scale.
- WCAG AA contrast; media marks have spoken labels ("Sending to Pixel").
- Reduce Motion, Reduce Transparency and Increase Contrast each have their own
  fallback.
- Screen readers are not interrupted by every progress update; closing a sheet
  returns focus to its trigger.
