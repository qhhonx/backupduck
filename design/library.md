# Library and backup history: one grid

## 1. The user's question

In the Photos tab people browse their own photos. While doing so they ask "is
this one backed up?" and occasionally "which ones are not?". In backup history
they ask the same question from the other side. Two grids answer one question
twice, with two scroll positions, two sets of gestures and two places to look.

## 2. Library views

- **One grid per source.** The Photos tab (iPhone) and Photo Library and Folders
  (Mac) are the only photo grids. Their tiles carry the same marks as the
  history page: none when the photo is in the Pixel's Photos, sending,
  saving, needs you. Photos outside the backup are not marked: on a new install that would mark most of the library. They are found
  through the Not backed up view.
- **Views, not pages.** The grid's existing menu offers two views: All photos
  and Not backed up, the library's own question. Recently backed up and Needs
  you belong to History (`records.md`), which counts them from the same core
  records, so the two places never disagree.
  Each view keeps its own scroll and date anchor.
- **The photo's detail answers the backup question.** The viewer's info shows
  the facts from `records.md` (sent to the Pixel, in the Pixel's Photos), next
  to the date and source.
- **The hub keeps the summary.** On iPhone its History, Needs You and
  earlier-photos actions push `BackupHistoryView` within the Backup tab, using
  all, attention and saved respectively. Photos backup views remain independent
  choices in the Photos menu.
- **Pixel photo grid.** The Pixel has no library of its own; Received photos is
  its only photo grid.

### Reviewing a selection (iPhone)

While selecting, the selection count in the selection bar opens a review of
just the selected photos, for selections that span far apart in the library.
The page answers one question: are these the photos I mean to back up?

- A standard system sheet (system corner radius and grabber, large detent),
  titled with the selected count, with the browse button leading and
  confirmation-role Done trailing. Done is the only dismissal: the selection is
  live, so a second Cancel would close the same state. Browse shows selected
  photos one at a time in the viewer; each page carries its own selection mark
  in the photo's trailing corner and pages with it, and loading progress takes
  the photo's leading corner.
- The selected photos in the library's grid density, each with its selection
  mark. Tapping a photo deselects it in place (it stays, unmarked, until the
  sheet closes, so a mistaken tap is undone with another tap). Long press opens
  the same system context menu and full-aspect preview as the library; tapping
  the preview opens the viewer.
- A system bottom toolbar: Deselect All (leading, plain) and the primary
  "备份 12 张" (trailing, prominent), the same durable action as the library's
  selection bar, with the same in-place feedback.
- Closing keeps the selection. No custom buttons, floating controls or corner
  radii.

## 3. Constraints

- The library grid is the performance-critical native grid with the calendar
  and zoom gestures (`iphone-calendar-grid.md`, `apple-media-interactions.md`).
  Marks are an overlay on the existing cells; virtualization, cancellation,
  stable IDs and gesture ownership stay as they are. Feel is measured on a
  Release build with 60 fps recordings.
- The backup state per photo comes from the core, which already answers
  `browse_sources` with a state per source for the library scope. Marks must
  never be inferred on the host.
- The catalog cannot read real photos; Library scenarios need the synthetic
  photo source noted in the catalog README.

## 4. Backup-view data

- `received_sources` supplies the source identifiers this receiver has received
  for the whole library (receipt only, never cloud). `source_states` is the
  bounded lookup for the visible window (400 per call) that tile marks use.
- `PhotoLibraryModel` has a backup view next to its type filter. Each view is a
  PhotoKit fetch over the same pipeline, sorting, paging and thumbnails:
  All photos uses the type-filtered fetch; Not backed up subtracts
  `received_sources` from it.
- The library's menu has a Backup section with the two views. iPhone hub actions
  retain the Backup tab and push History with the corresponding task filter;
  they do not change the Photos view.
- Catalog backup commands use the synthetic photo library's identifiers.
- The floating header's title and status bar follow whether photos lie behind
  them, retaining readable contrast over both photos and the page surface.

## 5. One grid engine and one toolbar

This section governs shared grid behavior, state updates, toolbar order,
filtering, headers and album browsing.

- **One engine.** On Mac every photo grid (Photo Library, Folders, Backup
  History, and later the album picker's photo previews) is the Photo Library's
  native collection grid with a different item source. Shared: tile and marks,
  zoom levels with the same animated density change (buttons and pinch), sticky
  date headers in the library's style, selection and marquee, the viewer with
  previous/next controls and the information panel, virtualization,
  cancellation and stable identifiers. Sources supply items, sections, marks and
  images only. iPhone Backup History uses its native timeline list (`records.md`).
- **Changes animate, state updates in place.** Inserted, removed and moved
  items animate as in the system Photos app (diffable updates keyed by stable
  identifiers). A mark or progress change updates the visible cell in place; it
  never reloads the grid or the section. Scroll position and the date anchor are
  kept across updates.
- **Backup History stays a page.** It remains the one place that lists backups
  from every source (photo library and folders) by latest change, with Needs
  You at the top. It uses the shared grid implementation. The library's
  Recently Backed Up view stays as the per-source view.
- **One toolbar order** for every grid page, trailing side, each group only
  when it applies: Zoom Out / Zoom In; the page's view control (Library: Years,
  Months, All Photos; Folders: By Folder, All Photos; History: none); Original
  Aspect on Photo Library only, retained in place and system-disabled at gapless
  overview densities or with empty/placeholder content; Filter; the page's own
  actions (Folders: Add Folder, More); the primary text action, only while the
  selection contains eligible items (Back Up N Items), with its brief "Added"
  feedback, then gone; Search as a magnifier circle, collapsed by default,
  expanded by click or ⌘F, collapsed by Escape when empty (Folders and any page
  that gains search).
- **Filter menu.** Two sections with headers and no other dividers: "Show" —
  All Photos, Not Backed Up, Needs You, Recently Backed Up (History: All, Needs
  You); "Type" — All Types, Photos, Live Photos, Videos, Bursts. All Types sits
  inside the Type section. An active non-default choice tints the filter symbol.
- **Filter presentation.** Committed Show, Type and search membership is adopted
  once with a 0.2-second grid crossfade (Reduce Motion: instant), without
  interpolating collection rows. New views start at their newest edge; returning
  restores that view's retained anchor. Pending source work cannot adopt old
  rows as a new context. Toolbar state and membership must commit together.
- **Folder headers.** A folder summary is its section header, aligned with the
  date text at the library header's 28 pt inset, measured at the exact laid-out width. Nested dates show
  only the date. All Photos shows dates without folder summaries.
- **Album browsing.** The album photo browser uses a scoped PhotoKit source and
  the same native grid, density stops, marks and viewer as Photo Library, with
  selection disabled. Its single text action is Choose This Album or Deselect
  This Album, according to the saved rule.
- **Empty results** after a filter say so ("No Photos Match", Show All Photos);
  they never reuse the photo-access placeholder.
- **Album picker (Mac).** The "back up these albums" editor shows albums as an
  adaptive grid of cover cards (square cover, name, count, a checkmark when
  included), with the existing All Albums switch and search above. The iPhone
  keeps its full-width list, which already fills the screen.
- **Feel** is judged on a Release build with 60 fps recordings of zoom, an
  insert/delete burst during a running backup, and scrolling (iteration
  checklist), compared with the system Photos app first.

### iPhone filtering and viewer continuity

Selection owns the bottom toolbar: hide the active backup-view chip throughout
selection and restore it when selection ends, retaining the same native grid.
With Photos access granted, zero matches in a backup view or media-type filter
show No Photos Match, Try another filter and Show All Photos. Keep the active
view chip and filter menu available. Show All Photos resets both filters.

Every iPhone photo collection opens the same viewer with information collapsed.
Horizontal paging runs from older to newer: swipe left for a newer photo and
right for an older one. Apply the same ordering to the library, recent mosaic,
history and selected-photo review; preserve the entry collection and return
anchor. Paging never changes grid or durable backup order.


## 6. iPhone filter commits and viewer direction

Backup-view and media filters prepare complete immutable membership off the
main thread, then publish content, count and active filter state together.
The native grid adopts one complete layout with a 0.2-second crossfade of the
grid and its labels (instant under Reduce Motion). A new view starts at its
newest edge; returning restores that view's retained anchor. Any non-default
backup view or media type uses the filled accent filter symbol; All restores
the plain symbol.

The thumbnail strip runs older on the left to newer on the right, without a
mirrored collection transform. It follows the pager in the same direction:
swiping the photo left advances to the newer item. This applies to every entry
collection, including albums, History and selected-photo review, preserving
that collection's return anchor.

### Group captions during Mac density changes

A live grid zoom owns one native-size caption per section, shared across the
photo density faces. Its bottom follows the blended position of the section's
first row; sticky bounds use the next section's caption. Folder summaries use
the same path. Caption text, width and native height never scale with tiles.
The stage's final caption frame equals the settled collection header frame.

Toolbar zoom anchors use the clamped point on the selected photo when the
viewport centre falls outside its rectangle. A stage entering a gapless overview
uses that density's zero gap, including its initial pitch. These entry corrections
do not change settled collection frames.

## 7. Mac Photos library

All Photos, Years and Months run oldest to newest and rest at the newest edge,
at the bottom. Older pages appear above the oldest loaded row without moving
the viewport; a viewport resting at the newest edge stays there. Arrow keys
follow the visual order: Left is older, Right is newer. A level change or a
return from the viewer centres the retained item.

Years and Months are a cover hierarchy over the filtered PhotoKit fetch,
separate from All Photos thumbnail size. A year is a portrait card with its
year at top left. Covers use the period's own photos in date order. Missing capture dates remain unknown. Calendar cover
membership is indexed off the main actor and does not request full-library
thumbnails. Native reusable collections virtualize both the covers and the
complete media grid. Clicking a year opens its months; a month cover opens its
matching All Photos anchor. A toolbar level change retains the visible asset.
All Photos ends at the newest edge with the actual photo and video totals;
no sync state is shown because none is reported.

The window toolbar owns the segmented level control, All Photos size buttons,
original-aspect control and media-type filter. The window subtitle shows the visible date, yielding to one selection count;
selected backup uses the toolbar action. Command/Shift, rubber-band and keyboard selection remain AppKit owned.
Disabled actions do not forward clicks to media below.

Single-click selects. Double-click or Space/Return opens the current photo
inside the same window, growing from its cell. A mouse or trackpad drag pages
sideways; dragging up shows information and dragging down hides it, then returns
to the grid. The grid remains alive beneath the viewer, which uses the system
window background. Escape or Back returns to the currently viewed asset,
retaining filter and selection. The viewer uses native horizontal page tracking,
fit/magnification, video/Live Photo playback and an information sidebar with
complete wrapping values. There is no permanent filmstrip; Left and Right move
through the library. Backup registers durable intent through the shared queue,
never through browsing.

All Photos has six stops: four grids (3, 4, 6 and 9 columns) and two gapless
overview mosaics whose column counts follow the window width. Overviews draw
pooled image layers with no cells or badges and load the whole library; a click
steps toward the grid around that photo. Selected photos carry an accent
outline, never a check mark.

Density input begins at the tile under the pointer, tracks magnification
linearly, retains the focal position on reversal, resists beyond the smallest
and largest sizes, and settles to the previewed column count using `GridZoom`.
Shrinking into the last row moves the pivot to that edge, and a new gesture
interrupts a settle in place. A bounded native tile stage draws both densities
on one coherent lattice, including scaled media decorations; per-item
interpolation between wrapped rows is not allowed. The native collection adopts
the exact final pitch and retained displayed pixels. Density never implicitly
changes calendar level. Window resizing keeps the nearby visible asset.
Reduce Motion adopts state immediately.
