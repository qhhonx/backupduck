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
- **Views, not pages.** The grid's existing menu gains views: All photos, Not
  backed up, Needs you, Recently backed up (ordered by backup time). Each view
  keeps its own scroll and date anchor, as report 07 asks.
- **The photo's detail answers the backup question.** The viewer's info shows
  the facts from `records.md` (sent to the Pixel, in the Pixel's Photos), next
  to the date and source.
- **The hub keeps the summary.** "Needs you" cards stay on the hub and open the
  Needs you view; "Backup History" opens Recently backed up. The separate
  history page (`BackupHistoryView`) is retired once the views exist.
- **Pixel unchanged.** The Pixel has no library of its own; Received photos is
  its only photo grid and stays as built.

### Reviewing a selection (iPhone)

While selecting, the selection count in the selection bar opens a review of
just the selected photos, for selections that span far apart in the library.
The page answers one question: are these the photos I mean to back up?

- A standard system sheet (system corner radius and grabber, large detent),
  titled with the count ("已选 12 张"), Done on the trailing side and, as the
  system photo library's selection review does, a leading button that browses
  the selected photos one at a time in the viewer.
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
   - Needs you: the attention items from `backup_tasks`.
   - Recently backed up: items saved in the last seven days, from
     `backup_tasks` ordered by latest change, shown in the grid's date groups.
3. **UI.** The library's existing menu gets a Backup section with the four
   views, behind the catalog's design switch. The hub's Needs you and Backup
   History open the matching view.
4. **Catalog.** Library scenarios run on the iOS Simulator against a synthetic
   photo library (generated images added with `simctl addmedia`); the catalog
   answers backup commands from that library's identifiers. The Mac catalog
   keeps the library placeholder, because it would read the Mac's real photos.
5. **Then marks.** Tile marks reuse the existing window lookup and replace the
   legacy badges.

## 6. State (October 19, 2026)

- Built behind the design switch on iPhone and Mac: the core's
  `received_sources`, the model's backup views, the Backup section in the
  library menu, the view's name in the grid subtitle, and the hub's Needs
  attention and Backup History rows opening Needs you and Recently backed up.
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
  Aspect, only in views where it changes the tiles; Filter; the page's own
  actions (Folders: Add Folder, More); the primary text action, only while the
  selection contains eligible items (Back Up N Items), with its brief "Added"
  feedback, then gone; Search as a magnifier circle, collapsed by default,
  expanded by click or ⌘F, collapsed by Escape when empty (Folders and any page
  that gains search).
- **Filter menu.** Two sections with headers and no other dividers: "Show" —
  All Photos, Not Backed Up, Needs You, Recently Backed Up (History: All, Needs
  You); "Type" — All Types, Photos, Live Photos, Videos, Bursts. All Types sits
  inside the Type section. An active non-default choice tints the filter symbol.
- **Empty results** after a filter say so ("No Photos Match", Show All Photos);
  they never reuse the photo-access placeholder.
- **Album picker (Mac).** The "back up these albums" editor shows albums as an
  adaptive grid of cover cards (square cover, name, count, a checkmark when
  included), with the existing All Albums switch and search above. The iPhone
  keeps its full-width list, which already fills the screen.
- **Feel** is judged on a Release build with 60 fps recordings of zoom, an
  insert/delete burst during a running backup, and scrolling (iteration
  checklist), compared with the system Photos app first.
