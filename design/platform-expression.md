# Platform expression

Status: approved by the owner on October 21, 2026 (items A0–A11). Companion to
`constitution.md` (P2), `visual-language.md` and `interaction.md`.

This contract says which native container and control expresses each recurring
task on each platform. A page is assembled from these answers; it does not
decide them again. When a task is missing from this table, add a row here (with
review) before building the page. Sources: Apple Human Interface Guidelines
(Sheets, Toolbars, Alerts, Action sheets, Sidebars, Buttons, Popovers, Menus,
Panels) and Material 3.

## A0 Chrome is the system's, content is BackupDuck's

Navigation bars, toolbars, tab bars, sidebars, the frame and button area of a
sheet, alerts, confirmation dialogs, menus, popovers, switches, pickers and
search fields are system controls with system styling. BackupDuck never draws
its own version of them, never adds a background, border or tint to them, and
never places a content component inside them.

BackupDuck's own expression lives in content: the status card, problem card,
photo grids and media marks, the settings identity header, step marks and the
duck in guided flows and empty states, the first-photo flight, copy and the
accent color passed to the system as tint (Apple) or seed (Material).

A review that finds a drawn close button in a sheet, card-style buttons in a
sheet footer, or a brand block in a sidebar is a violation of this item, not a
matter of taste.

## A1 Buttons

| iPhone | Mac | Pixel |
| --- | --- | --- |
| Primary action: system `.borderedProminent`, large control size (the system draws the capsule). Secondary action inside a card: `.bordered`, small. Optional action under a primary: plain text button | Push buttons: the default button is `.borderedProminent` (Return activates it), others `.bordered`, regular size. Inside a card: small `.bordered` | Material buttons: Filled for the one primary action, Tonal inside cards, Text for optional actions |

The capsule look approved on October 19 is kept, but the system button styles
produce it. BackupDuck passes the role and the accent; it does not draw shape,
fill, pressed state or contrast variants. A Mac guided flow puts its default
button at the bottom trailing edge; it does not copy the iPhone's full-width
bottom capsule.

## A2 Page title and top bar

| iPhone | Mac | Pixel |
| --- | --- | --- |
| Top-level pages: system large title. Pushed pages: inline title and the system back button. At most one or two borderless symbol items on the trailing side; the system groups them on glass. Photos tab: the title floats over the grid, as in the system photo library | One unified toolbar: sidebar toggle, title (under 15 characters), at most three groups. Symbols without borders; one primary action on the trailing edge when there is one. Every toolbar item also exists as a menu bar command | Top app bar: large title on top-level pages, collapsing on scroll; small bar with back arrow on pushed pages. At most two action icons, the rest in the overflow menu |

## A3 Moving between positions

| iPhone | Mac | Pixel |
| --- | --- | --- |
| Tab bar: Photos, Backup, Settings | System sidebar: Photos (Photo Library, Folders), Backup (Overview, History), Settings. The sidebar lists positions only: no brand block, device card or buttons | Navigation bar: Receive, Photos, Settings |

## A4 Short edit (rename, one value)

| iPhone | Mac | Pixel |
| --- | --- | --- |
| Sheet with a toolbar: Cancel (xmark) leading, Done (checkmark, prominent) trailing. Height fits the content; swipe down dismisses, with a confirmation when there are unsaved changes | Sheet attached to the window: content in a grouped form; Cancel and the default button at the bottom trailing edge; no close button | Basic dialog with one text field; text buttons Cancel and Save at the bottom trailing edge |

## A5 Confirmation and destructive actions

| iPhone | Mac | Pixel |
| --- | --- | --- |
| A destructive action the person chose (stop receiving from a device, stop backing up a folder): a confirmation dialog anchored to its button. An alert only for an unexpected consequence | Alert: title is the question, informative text states the consequence; default button first in a stack or trailing in a row. A deliberately chosen action is not styled destructive | Basic dialog: title is the question, body states the consequence, text buttons |

## A6 Choosing from many (albums, subfolders)

A6 is for large or unbounded sets. A small fixed set (up to about seven
options, such as media types) is an inline checklist in a grouped list: no
search field and no selection summary. Rows that stand for photo collections
(albums, folders) lead with a cover thumbnail from that collection; symbols
in a checklist share one column width so titles align.

| iPhone | Mac | Pixel |
| --- | --- | --- |
| Push a system list with search, a selection summary and checkmarks. Changes apply at once; no Save | A list with a search field in the settings detail; from a task, a sheet with Done | A full-screen pushed page with a search bar and checkbox rows |

## A7 Explanation, Learn more, help

A7 covers explanation opened from a task or state ("Why is this?", Learn more).
The help center reached from a Settings row is ordinary preferences navigation
and is pushed like any other settings page.

| iPhone | Mac | Pixel |
| --- | --- | --- |
| Sheet at the medium detent, expandable, close button (xmark) trailing | One or two sentences: popover from an info button, closed by clicking outside. Longer: a sheet with Done | Modal bottom sheet with a drag handle |

## A8 One photo's information

| iPhone | Mac | Pixel |
| --- | --- | --- |
| An information panel that slides up inside the viewer, as in the system photo library. A photo opened from backup history opens the same viewer; there is no separate photo-detail sheet | A trailing inspector in the viewer window (SwiftUI `inspector`), toggled with the toolbar info button and ⌘I, named "Show Info" in the View menu; the window remembers whether it is shown | A bottom panel inside the viewer |

An in-viewer information panel is docked to the bottom edge: only its top
corners are rounded and it extends under the home indicator or navigation
bar, like a system sheet.

One photo has one viewer and one information layout on each platform: date and
time, the backup facts with their times (`interaction.md` I2 Detail), at most
one action, and a quiet file line. The trailing inspector follows the platform's
convention for showing details of the current item next to it.

History and recent-photo entry points retain their collection and scroll while
the viewer is open. If the local asset is unavailable, recorded information
remains accessible in the fallback detail. Event times are shown only when
recorded; receipt does not supply a publication time. File name, size, format
and available camera fields share the quiet secondary section.

## A9 Feedback after an action

State changes replace content in place; there are no toasts (`interaction.md`
I5). One exception on the Pixel: an action that can be undone (for example
stopping a device) shows a Material snackbar with Undo.

## A10 Empty, no access, failed to load

| iPhone | Mac | Pixel |
| --- | --- | --- |
| The system content-unavailable structure: image, title, one sentence, one button. The duck only when there is truly nothing yet; a system symbol for no access, not connected and failures | Same as iPhone | The same structure, centered |

## A11 More actions and context menus

| iPhone | Mac | Pixel |
| --- | --- | --- |
| A toolbar menu (ellipsis); long press on a photo opens the system context menu | The toolbar's more menu, the context menu and the menu bar carry the same commands | Overflow menu in the top app bar; long press starts selection |

## A12 Live Activity

The Lock Screen and Dynamic Island show a progress ring with one SF Symbol
inside at about half the ring's diameter, one weight for every state: arrow
up while sending, clock while saving, pause, filled triangle when the person
is needed, check when done. Active states use the accent, needs-you uses the
attention role, paused uses the secondary label color. Text beside the ring
states the count and the device.

## Decisions

- **October 21, 2026:** the owner approved A0–A11. On A8 the owner asked
  whether the Mac's trailing inspector is right; it is the platform's place for
  details of the current item, so it stays. A9 allows the Pixel snackbar for
  undoable actions only.
- **October 22, 2026 (owner review of the night's work):** small fixed sets
  have no search (A6); collection rows show covers; in-viewer panels dock to
  the bottom edge (A8); Live Activity glyph rules (A12); every page uses the
  system background role, with no cream canvas left (V1).
