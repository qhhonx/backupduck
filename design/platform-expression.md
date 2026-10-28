# Platform expression

Companion to `constitution.md` (P2), `visual-language.md` and `interaction.md`.

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
accent color passed to the system as tint (iPhone), accent color (Mac) or seed
(Material).

A review that finds a drawn close button in a sheet, card-style buttons in a
sheet footer, or a brand block in a sidebar is a violation of this item, not a
matter of taste.

## A1 Buttons

| iPhone | Mac | Pixel |
| --- | --- | --- |
| Primary action: system `.borderedProminent`, large control size (the system draws the capsule). Secondary action inside a card: `.bordered`, small. Optional action under a primary: plain text button | Push buttons: the default button is `.borderedProminent` (Return activates it), others neutral `.bordered`, regular size. Inside a form or card: regular/small neutral `.bordered`, without ellipsis. Pass the accent to the system with `.accentColor`, so secondary push buttons keep their neutral fill and label; do not tint the Mac root | Material buttons: Filled for the one primary action, Tonal inside cards, Text for optional actions |

System button styles produce the capsule look. BackupDuck passes the role and the accent; it does not draw shape,
fill, pressed state or contrast variants. A Mac guided flow puts its default
button at the bottom trailing edge; it does not copy the iPhone's full-width
bottom capsule.

## A2 Page title and top bar

| iPhone | Mac | Pixel |
| --- | --- | --- |
| Top-level pages: system large title. Pushed pages: inline title and the system back button. At most one or two borderless symbol items on the trailing side; the system groups them on glass. Photos tab: the title floats over the grid on a media scrim through the subtitle, with a light status bar only over photos; empty, permission and loading placeholders keep the system scheme. Selection shows the selected count | One unified toolbar: sidebar toggle, title (under 15 characters), at most three groups. Symbols without borders; one primary action on the trailing edge when there is one. Every toolbar item also exists as a menu bar command | All three top-level tabs (Receive, Photos, Settings) use the same compact top app bar with a small title and trailing actions, so switching tabs never changes the bar and content leads immediately, as the system gallery does; pushed pages use a compact bar with Back |

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
options, such as media types) is inline in a grouped list: leading-label/trailing-switch rows for persistent Boolean preferences on
iPhone and Mac, and a checklist on Pixel. Apple media-type rows share order and
keys; disable the last included type so at least one stays enabled. It has no search
field or selection summary. Rows that stand for photo collections
(albums, folders) lead with a cover thumbnail from that collection; symbols
in a checklist share one column width so titles align.

| iPhone | Mac | Pixel |
| --- | --- | --- |
| Push a searchable, virtualized album card grid: two columns on phone widths, adaptive on iPad. All Albums is alone in a 52 pt preference group; its summary is the footer. Shared square-cover cards show name, count and included checkmark; tap toggles and View Album opens the read-only native library grid. Choose/Deselect Album is a trailing text button. Unavailable albums retain their rows below. Changes apply at once; no Save | The same shared adaptive album cards with search in the settings detail; from a task, a sheet with Done | A full-screen pushed page with a search bar and checkbox rows |

## A7 Explanation, Learn more, help

A7 covers explanation opened from a task or state ("Why is this?", Learn more).
The help center reached from a Settings row is ordinary preferences navigation
and is pushed like any other settings page.

| iPhone | Mac | Pixel |
| --- | --- | --- |
| Sheet at the medium detent, expandable, one system confirmation-role Done trailing | One or two sentences: popover from an info button, closed by clicking outside. Longer: a sheet with Done | Modal bottom sheet with a drag handle |

### Third-party software reader

From Source code & licenses, iPhone pushes a native text reader, Mac replaces
the settings detail with a native text reader, and Pixel pushes a plain-text
page. Each is a single scrollable, selectable offline document; component names
are text rather than navigation rows. Native text controls own selection,
copying, wrapping and scrolling.

## A8 One photo's information

| iPhone | Mac | Pixel |
| --- | --- | --- |
| An information panel that slides up inside the viewer, as in the system photo library. A photo opened from backup history opens the same viewer; there is no separate photo-detail sheet | A trailing inspector in the viewer window (SwiftUI `inspector`), toggled with the toolbar info button and ⌘I, named "Show Info" in the View menu; the window remembers whether it is shown | A bottom panel inside the viewer |

An in-viewer information panel is docked to the bottom edge: only its top
corners are rounded and it extends under the home indicator or navigation
bar, like a system sheet.

The iPhone and iPad viewer's chrome is the system photo library's: system
background (white in light appearance, black in dark), a back button, a centered
date-and-time title (which also opens Info) and a More menu at the top, and a
bottom toolbar with Share and Info, above which the filmstrip sits while
browsing. State is not an action: the backup state is a quiet mark on Info
(none when normal), and its details and Back Up / Retry are in the panel. One tap on the photo hides the
bars and filmstrip and turns the background black; another tap restores them.
Opening and closing fly the photo from and back into its tile while the grid
stays still. On iPhone, rendition preparation and delayed media-local loading
feedback retain the displayed pixels and viewport. Paging retains filmstrip
cells for unchanged items; loading feedback overlays the media without adding
space. Long press on a tile opens the system context menu with the whole
photo at its own aspect ratio as the preview; selection starts from Select.

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

On every platform the state takes the whole content area, centered
horizontally, with the whole block's center at the optical center (45% of
the height). Its one button is the filled primary action, without an
ellipsis. An empty state has no Retry. While a page shows one of these
states, its toolbar keeps only the title: subtitle counts and browsing
controls (view, zoom, filter, search) appear once there is content.
An iPhone filter with zero matches keeps its filter menu and active-view chip
available so the person can leave that view. Show All Photos clears both the
backup view and media-type filter.

## A11 More actions and context menus

| iPhone | Mac | Pixel |
| --- | --- | --- |
| A toolbar menu (ellipsis); long press on a photo opens the system context menu | The toolbar's more menu, the context menu and the menu bar carry the same commands | Overflow menu in the top app bar; long press starts selection |

## A12 Live Activity

The Lock Screen and Dynamic Island show a progress ring with one SF Symbol
inside at about half the ring's diameter, one weight for every state: arrow
up while sending, clock while saving, pause, filled triangle when the person
is needed, check when done. Active states use the accent, needs-you uses the
`attentionGlyph` role, paused uses the secondary label color. Text beside the ring
states the count and the device.

### Apple selected-photo review

The iPhone selected-photo review follows `library.md`: a native large sheet
with the selected count, system cancellation leading, the browse button beside
it, and checkmark confirmation trailing. The native bottom toolbar has Deselect All / 取消全选
leading and prominent Back Up N Photos / 备份 N 张 trailing. Closing preserves
selection; the backup action registers the same durable intent as the library.

## Pixel task recovery and transient handoff

Android action failures use a Material 3 basic AlertDialog. The title names what
failed in ordinary words; the body says what to do. Got it / 知道了 is always
available. Retry / 重试 appears only when retrying the original action can
succeed, never for a cause that requires installing another app. Dismissal
preserves the parent and its input.

The wake/unlock handoff uses the receiver surface with only a small Material
circular progress indicator, title and one-sentence note. The complete block is
horizontally centered at the optical center (45% of the content height). There
is no large icon, card or action. The system owns keyguard dismissal; secure
locks require manual unlock and never accept credentials in the app. Catalog
previews render the same content without operating the keyguard.

The receive hub uses the compact native top bar from its first layout, the page
surface, centered unconnected/first-photo states and one filled connect action.
Connected devices remain in Settings rather than a duplicate hub list. The
Pixel status card retains one secondary line naming the most recently connected
enabled device and its recorded connection time, using the localized date/time
skeleton without a weekday or a colon after Last connected / 上次连接; omit it when no time is known. Calm
recent-photo evidence on all three platforms can show two rows (up to eight photos). Device temperature
and free-space readings are plain secondary text, without chip backgrounds.

### Apple content details

An Apple unavailable-state title uses the primary-text role even when the system
container inherits a secondary style. Photo access states name the unavailable
access, with the system-owned permission or Settings action.

The Mac split workspace hides the automatic native toolbar backdrop so the
shared window surface continues across the titlebar; no content column paints
a separate toolbar surface. Folder preferences use leading labels, trailing
native buttons and a current file-rule summary.

### iOS sheet headers

Every `DuckSheetLayout` and independently tooled iOS sheet follows the same
header roles. Editing sheets use the system cancellation role leading and
confirmation role trailing; current systems render these as a cross and a
checkmark. Read-only and informational sheets have one confirmation-role Done
trailing and no leading close. Their task actions stay in the content rather
than adding another header action. A lone cross is never the complete header.
System-owned sharing and mail composition retain their own controls. On older
systems the same placements use localized Cancel and Done text.

The Rename Device sheet uses a native rounded text field with its standard
clear button. It focuses that field and presents the keyboard on opening.
