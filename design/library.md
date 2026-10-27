# Library and backup history: one grid

Status: direction approved October 18, 2026 (one grid; not-backed-up is a view, not a mark). Views are built first, marks second. Raised in the records review:
the backup history grid and the Photos tab (and on Mac, Photo Library and
Folders) are two grids of the same photos. This proposal makes them one.

## 1. The user's question

In the Photos tab people browse their own photos. While doing so they ask "is
this one backed up?" and occasionally "which ones are not?". In backup history
they ask the same question from the other side. Two grids answer one question
twice, with two scroll positions, two sets of gestures and two places to look.

## 2. References

| Product | What it does |
| --- | --- |
| Google Photos | One photo grid. Photos not backed up carry a crossed-out cloud; a photo's info says "Backed up". Backup progress is in the account menu. No second grid of backed-up photos. |
| iOS Photos with iCloud | One library. Sync state is a single line at the bottom of the library; nothing per photo. |

## 3. Proposal

- **One grid per source.** The Photos tab (iPhone) and Photo Library and Folders
  (Mac) are the only photo grids. Their tiles carry the same marks as the
  history page today: none when the photo is in the Pixel's Photos, sending,
  saving, needs you. Photos outside the backup are not marked (owner decision, October
  18): on a new install that would mark most of the library. They are found
  through the Not backed up view.
- **Views, not pages.** The grid's existing menu offers two views: All photos
  and Not backed up, the library's own question. Recently backed up and Needs
  you belong to History (`records.md`), which counts them from the same core
  records, so the two places never disagree (owner decision, October 27 2026).
  Each view keeps its own scroll and date anchor, as report 07 asks.
- **The photo's detail answers the backup question.** The viewer's info shows
  the facts from `records.md` (sent to the Pixel, in the Pixel's Photos), next
  to the date and source.
- **The hub keeps the summary.** On iPhone its History, Needs You and
  earlier-photos actions push `BackupHistoryView` within the Backup tab, using
  all, attention and saved respectively. Photos backup views remain independent
  choices in the Photos menu.
- **Pixel unchanged.** The Pixel has no library of its own; Received photos is
  its only photo grid and stays as built.

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

## 4. Constraints

- The library grid is the performance-critical native grid with the calendar
  and zoom gestures (`iphone-calendar-grid.md`, `apple-media-interactions.md`).
  Marks are an overlay on the existing cells; virtualization, cancellation,
  stable IDs and gesture ownership stay as they are. Feel is re-measured on a
  Release build with 60 fps recordings after the change.
- The backup state per photo comes from the core, which already answers
  `browse_sources` with a state per source for the library scope. Marks must
  never be inferred on the host.
- The catalog cannot read real photos; Library scenarios need the synthetic
  photo source noted in the catalog README.

## 5. Build plan (views first)

1. **Core.** Add `received_sources`: the source identifiers this receiver has
   received, for the whole library (receipt only, never cloud). `source_states` stays the bounded lookup
   for the visible window (400 per call) that tile marks use.
2. **Model.** `PhotoLibraryModel` gains a backup view next to its type filter.
   Each view is a PhotoKit fetch over the same pipeline, sorting, paging and
   thumbnails:
   - All photos: today's fetch.
   - Not backed up: the type-filtered fetch minus `received_sources`.
3. **UI.** The library's existing menu gets a Backup section with the two
   views. iPhone hub actions retain the Backup tab and push History with the
   corresponding task filter; they do not change the Photos view.
4. **Catalog.** Library scenarios run on the iOS Simulator against a synthetic
   photo library (generated images added with `simctl addmedia`); the catalog
   answers backup commands from that library's identifiers. The Mac catalog
   keeps the library placeholder, because it would read the Mac's real photos.
5. **Then marks.** Tile marks reuse the existing window lookup and replace the
   legacy badges.

## 6. State (October 19, 2026)

- Built behind the design switch on iPhone and Mac: the core's
  `received_sources`, the model's backup views, the Backup section in the
  library menu and the view's name in the grid subtitle. iPhone hub navigation
  now pushes History within Backup, independently of the Photos menu.
- Checked on the iOS Simulator with a synthetic library of 240 photos: 246 in
  All (with the Simulator's samples), 34 not backed up, 4 needing the user, 30
  recently backed up, each in the grid's date order.
- Defect fixed in the shared grid: with only a few photos the header kept its
  light-on-photo text over the light canvas; it now follows whether photos lie
  behind it, for the title and the status bar.
- Tile marks (step 5) built on iPhone behind the design switch: no mark once
  the Pixel has the photo, an arrow while it is on its way, an
  exclamation when it needs the user, all white with a soft shadow over photos
  (V5); the legacy check and ellipsis badges are gone in the proposed design.
- Gap: the visible-window lookup (`source_states`) reports receipt, not whether
  a received photo is already in the Pixel's Photos, so tiles have no "saving"
  mark yet. Adding the processing observation to that lookup is a small core
  change.
- Mac tile marks built behind the design switch but not seen on screen: the
  Mac catalog never reads a photo library, so they need a check on a Mac with
  a synthetic library.
- Not done: feel measured on a Release device recording.

## 7. Open

- The order of work: the Photos tab is the most-used page and the riskiest
  change; it may be built behind the design switch in two steps (views first,
  marks second).

## 8. One grid engine and one toolbar (October 26, 2026)

Owner's real-device review of the Mac: Photo Library, Folders and Backup
History look and behave like three different grids. History redraws and
flickers while backups progress, has no zoom animation and its header and date
headers read differently; Folders has no zoom; search starts expanded; the
filter menu splits "All" from the media types; the aspect button shows where it
does nothing; the library's primary button stays "Added to Backup". Decision:

- **One engine.** On Mac every photo grid (Photo Library, Folders, Backup
  History, and later the album picker's photo previews) is the Photo Library's
  native collection grid with a different item source. Shared: tile and marks,
  zoom levels with the same animated density change (buttons and pinch), sticky
  date headers in the library's style, selection and marquee, the viewer with
  previous/next controls and the information panel, virtualization,
  cancellation and stable identifiers. Sources supply items, sections, marks and
  images only. On iPhone, Backup History moves to the library's UIKit grid the
  same way (second step).
- **Changes animate, state updates in place.** Inserted, removed and moved
  items animate as in the system Photos app (diffable updates keyed by stable
  identifiers). A mark or progress change updates the visible cell in place; it
  never reloads the grid or the section. Scroll position and the date anchor are
  kept across updates.
- **Backup History stays a page.** It remains the one place that lists backups
  from every source (photo library and folders) by latest change, with Needs
  You at the top. It is no longer a separate grid implementation. The library's
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


## 9. iPhone filter commits and viewer direction

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
