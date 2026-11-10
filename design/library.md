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
Show Selected is a plain native navigation-toolbar item between flexible spaces.
The navigation controller owns its bottom placement, safe-area reservation and
system material. Its count and enabled state update on the same persistent item;
entering or leaving selection shows or hides the native toolbar.

- A standard system sheet (system corner radius and grabber, large detent),
  titled with the selected count, with the browse button leading and
  confirmation-role Done trailing. Done is the only dismissal: the selection is
  live, so a second Cancel would close the same state. Browse shows selected
  photos one at a time in the viewer; each page carries its own selection mark
  in the photo's trailing corner and pages with it, and loading progress takes
  the photo's leading corner. The viewer retains the source sheet's bounds and
  native clipping geometry. Entry, return and cancelled return move the media
  within that stable surface; they do not expand or scale the whole sheet.
- The selected photos in an independent three-column grid, retaining the
  library's original-aspect choice, each with its selection mark. Thumbnail
  requests use the review cell size and display density. Tapping a photo
  deselects it in place (it stays, unmarked, until the
  sheet closes, so a mistaken tap is undone with another tap). Long press opens
  the same system context menu and full-aspect preview as the library; tapping
  the preview opens the viewer.
- A system bottom toolbar: Deselect All (leading, plain) and the primary
  "备份 12 张" (trailing, prominent), the same durable action as the library's
  selection bar, with the same in-place feedback.
- In the selected-photo viewer, the sole Back Up N Items action is centered in
  the native bottom toolbar and still acts on the complete selected set.
  Deselect All remains on the grid. The current photo's corner check keeps its
  separate hit target clear of the backup control.
- Closing keeps the selection. No custom buttons, floating controls or corner
  radii.

## 3. Constraints

- iPhone uses the same native calendar collection, media cells, preview,
  selection, thumbnail pipeline and shared gesture core. Albums and the main
  library do not maintain separate grid implementations. Resizing preserves the
  visible asset and selection; each filter retains its own browsing anchor.
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
  ordinary density levels with the same animated change (buttons and pinch),
  date presentation, selection and marquee, the viewer with
  previous/next controls and the information panel, virtualization,
  cancellation and stable identifiers. Sources supply items, sections, marks and
  images only. iPhone Backup History follows its native timeline contract
  (`records.md`).
- **Shared size.** Photo Library, Folders and Backup History retain one Mac
  thumbnail-size setting. Changing size in one browser carries into the others
  instead of restoring a page-specific default. A source that supports only
  ordinary densities projects the preference to its nearest ordinary size; it
  does not overwrite a retained denser Photo Library preference.
- **Stable window chrome.** The workspace owns the browsing toolbar and uses
  one native navigation owner for the window title and subtitle across browsing sources.
  Equivalent controls retain their native identity across sources; selection
  and progress update the existing action. Pages provide their current subtitle
  without independently rewriting window chrome. Ordinary browsing reserves
  the native subtitle line while its first visible date is being resolved;
  missing dates remain blank. Date calculation follows native viewport layout,
  independently of thumbnail and backup-status refresh. Search receives its
  compact native width before insertion into the toolbar, so its first visible
  layout does not temporarily expand and move neighbouring controls.
  Until photo access is resolved and the first fetch finishes, loading is not
  presented as denied access or an empty library. Supporting album choices
  likewise show an empty state only after their first completed lookup.
  Switching sidebar positions
  retains each position's native grid and open viewer. The active position alone
  owns window controls, keyboard commands and the current Info target; the independently open Info window stays open, and switching does not
  dismiss a viewer or play a return flight. Folder scopes retain separate detail
  sessions and visible date ranges. Cached scope changes keep the collection
  mounted while membership updates.
- **Changes animate, state updates in place.** Inserted, removed and moved
  items animate through diffable updates keyed by stable identifiers. A mark or progress change updates the visible cell in place; it
  never reloads the grid or the section. Scroll position and the date anchor are
  kept across updates.
- **Backup History stays a page.** It remains the one place that lists backups
  from every source (photo library and folders) by latest change, with Needs
  You at the top. It uses the shared grid implementation. The library's
  scope and record dates remain distinct from capture-date library browsing.
- **One toolbar order** for every grid page, trailing side, each group only
  when it applies: Zoom Out / Zoom In; the page's view control (Library: Years,
  Months, All Photos; folder scopes and History have no level control); Original
  Aspect on Photo Library only, retained in place and system-disabled at gapless
  overview densities or with empty/placeholder content; Filter; the page's own
  actions (Folders: Add Folder, More), Info, then Back Up Selected where
  supported within one persistent symbol group; the native toolbar Search item at
  the trailing edge. Back Up Selected uses the existing upward-arrow symbol,
  remains disabled without selection, and includes every selected item with
  confirmation before repeating an existing backup. The selected count stays in
  the subtitle and in the action's help and accessibility label. The upward-arrow
  symbol remains unchanged during registration and Added feedback; these states
  disable the action and update its help and accessibility label.
  The same standard toolbar Button and Label used by Info provide native
  symbol weight, alignment, padding and hit size. Registration is announced to
  assistive technology. Selection never inserts or removes toolbar items,
  introduces a text button between symbols or changes their group geometry.
  Folder More remains in place and is disabled when no single folder applies.
  Search uses the same system presentation as Settings albums and Help. AppKit
  renders a compact magnifier initially; clicking it or ⌘F expands the native
  field and begins editing. Escape uses native cancellation and restores the
  compact item. Clicking content ends editing and restores the compact item
  while preserving the query and filtering.
  Toolbar search stays outside retained grids' visibility modifiers, so hiding
  a grid does not fade the toolbar control.
- **Filter menu.** Two sections with headers and no other dividers: "Show" —
  All Photos, Not Backed Up (History: All, Needs You); "Type" — All Types, Photos, Live Photos, Videos, Bursts. All Types sits
  inside the Type section. An active non-default choice tints the filter symbol.
- **Library membership.** Photo Library and Folders use ordered metadata
  results with stable identifiers and media types. Photo Library can display
  its opening viewport while materializing the rest of the same collection.
  Completion is automatic, retains the visible anchor and waits for an
  active zoom to settle before changing the extent. Collection totals describe
  the source rather than the opening viewport. The record feed maintains its
  own task results and extent as it loads older records.
- **Rendition priority.** Visible tiles and their near neighbors take priority
  over background thumbnail fill. Cached small covers can appear while the
  display-size rendition loads. Folder cache fill has its own table capacity,
  so it cannot consume the Photo Library's decoded thumbnail slots.
- **Filter presentation.** Committed Show, Type and search membership is adopted
  once with a 0.2-second grid crossfade (Reduce Motion: instant), without
  interpolating collection rows. New views start at their newest edge; returning
  restores that view's retained anchor. Pending source work cannot adopt old
  rows as a new context. Toolbar state and membership must commit together.
- **One date surface.** The native window title identifies the current source.
  Ordinary grids put only the visible photo-date range in the subtitle,
  yielding to one selected-item count. Collection totals never occupy this slot. The date comes from the
  top visible photo row: one localized day when its dated photos share a day,
  otherwise a localized interval. Unknown dates and incomplete totals are not
  invented. Photo Library and folder grids use their recorded photo dates;
  History explicitly labels the range as the latest record update. History
  never substitutes capture time for that update time.
  Years and Months identify their periods on their covers. Gapless overview
  densities retain their internal period captions. In these modes the subtitle
  is empty unless photos are selected; it never retains a previous ordinary-grid
  date or substitutes a count for the hidden date.
- **One total surface.** Full photo grids place their current collection total
  below the final photo row. Known photo/video splits use the shared localized
  count phrase; a known aggregate with unknown types says items. Search and
  local filters omit incomplete totals rather than counting a loaded prefix.
  Selection never changes this collection total. History follows the count with
  the known receiving device in secondary text. General cloud-backup guidance
  belongs in help rather than a permanent collection footer.
  This native footer wraps and retains sufficient document height in narrow
  windows and throughout density changes. It is not a pinned status bar.
  Date formats follow the application language, the user's calendar and its time
  zone. Chinese single dates and compact intervals use numeric months.
- **Folder navigation.** Selecting the expandable Folders sidebar parent opens
  the aggregate photo grid across all added folders, without Photo Library
  items. Its children select independent single-folder grids. These are sidebar
  destinations, so selecting one does not add Back or a synthetic parent-return
  keyboard command. There is no intermediate cover page, extra All Photos
  destination or separate scope control. Parent and children retain independent
  search, filter, selection and scroll state and share the photo toolbar.
  Search matches file and subfolder names within the selected scope. Folder
  grids run from oldest to newest by the recorded photo date and open at the
  bottom. Grids are continuous, with no repeated folder names, inline day headings or floating
  date capsules. Single-folder availability and unsupported-file notes remain
  ordinary content; they do not pin. See `mac-folders.md`.
- **Album browsing.** On Mac, album photos share the ordinary 3, 4, 6 and 9
  column sizes used by folder and History grids, including pinch and toolbar
  changes. Calendar levels and gapless overview densities are not album modes.
  The album photo browser uses a scoped PhotoKit source and
  the same native grid, density stops, marks and viewer as Photo Library, with
  ordinary inspection selection enabled; choosing the backup scope remains a
  separate whole-album action. On iPhone the grid and viewer share one native navigation
  controller. The iPhone album photo grid keeps its entry density and disables
  grid pinch zoom; scrolling, photo taps, viewer zoom and return anchoring retain
  their existing native ownership. Photo Library keeps its grid pinch zoom.
  Its inline album title, minimal system Back and native bar
  button remain owned by UIKit. Two retained choice states share a semantic item
  identifier and switch through the native animated bar-item API. The button reflects the saved choice through the system selected state and
  short action labels; the system draws its material, touch feedback and
  state transition. It chooses or deselects the whole album according to
  the saved rule and does not dismiss the page. Loading, empty and unavailable
  content retain that same navigation owner and action. Mac uses a native toolbar
  button toggle with explicit Choose This Album or Deselect This Album text.
  Its selected appearance follows the saved scope, changes apply immediately,
  and the same toolbar item remains mounted.
- **Empty results** after a filter say so ("No Photos Match", Show All Photos);
  Photo Library, albums, folders and History reuse the same shared placeholder
  composition and clear action. Empty membership is determined from the photos
  actually shown after every filter, once all required pages have resolved.
  An unmatched loaded prefix remains loading; a failed lookup retains recovery.
  Filter emptiness never reuses the photo-access placeholder.
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

All iPhone photo collections use the same system media canvas across the host,
collection gaps, section headers and the exposed area above and below short
content. Native collections retain vertical rubber-banding even when their items
fit on screen. Backup History applies this in both a pushed page and a sheet;
its source vacancy uses that same canvas. Album choice cards and the Backup hub
keep their own page or card surface.

Recent-photo mosaics and the first-run library strip reuse the native library
cell's media marks over their existing thumbnails: the same glyphs, corner
geometry, shadow, width thresholds and compact video duration. A locally
accessible original supplies its current media type and duration; without it,
only the recorded media type is shown. Tiny problem-card covers remain unmarked.
The mosaic retains its own rounded outer clip, frame lookup and source-vacancy
ownership.

Every iPhone photo collection opens the same viewer with information collapsed.
The return vacancy uses the source page or card's semantic surface, including
History and recent-photo entries; it never substitutes the viewer's canvas color.
Horizontal paging runs from older to newer: swipe left for a newer photo and
right for an older one. Apply the same ordering to the library, recent mosaic,
history and selected-photo review; preserve the entry collection and return
anchor. Paging never changes grid or durable backup order.


## 6. iPhone filter commits and viewer direction

Backup-view and media filters prepare complete immutable membership off the
main thread, then publish content, count and active filter state together.
An unchanged media view may reuse its prepared membership; a PhotoKit change
invalidates it, and receipt-dependent views use current receiver state.
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

### Reading surfaces during Mac density changes

Ordinary grids keep their date in the native window subtitle throughout density
changes. They do not introduce a content date header, floating capsule or folder
identity layer during tracking, reversal or native adoption. Folder notices and
History cause headings remain ordinary flow content. Their text keeps its native
reading size and measured geometry while the photos change density.

Gapless overview captions remain at native text size outside the photo transform.
Their positions follow geometric density independently of the timed photo blend.
The settled and moving surfaces use the same caption appearance, without a
material or text-size change at adoption. The subtitle does not repeat their
period labels.

Toolbar zoom anchors use the clamped point on the selected photo when the
viewport centre falls outside its rectangle. A toolbar zoom that retains the
top edge anchors the first photo. A toolbar zoom that retains the newest edge
anchors the bottom of the last photo, so all density faces keep their last row
clear of the totals label. A stage entering a gapless overview uses that
density's zero gap, including its initial pitch. These entry corrections do
not change settled collection frames.

Ordinary photo grids fill each row from the leading edge: the first row has
no empty leading slots, and the final row may be partial. The settled layout
uses the same rule on iPhone and Mac. A zoom target face uses that final row
composition before settling; the focal photo and the retained top or newest
edge move continuously into it, without a second reflow at adoption.

## 7. Mac Photos library

All Photos, Years and Months run oldest to newest and rest at the newest edge,
at the bottom. Older pages appear above the oldest loaded row without moving
the viewport; a viewport resting at the newest edge stays there. Arrow keys
follow the visual order: Left is older, Right is newer. A level change or a
return from the viewer centres the retained item.

Every primary press on a gapless overview photo steps toward the ordinary
grid around that photo's source identity, including rapid consecutive presses.
System double-click counting does not suppress overview activation. While a
zoom stage covers the native collection, that stage owns both the clicked photo
identity and the current density. A subsequent press continues from the shown
face: the broader overview enters the nearer overview, and the nearer overview
enters the ordinary grid. It never restarts from covered native geometry. A
long-press recognizer is enabled only when the current surface offers its
selection action.

Years and Months are a cover hierarchy over the filtered PhotoKit fetch,
separate from All Photos thumbnail size. A year is a portrait card with its
year at top left. Covers use the period's own photos in date order. Within each
month, sampled days advance left to right, then top to bottom, including mirrored
compositions; each cover retains its own drill-down asset. Missing capture dates remain unknown. Calendar cover
membership is indexed off the main actor and does not request full-library
thumbnails. Native reusable collections virtualize both the covers and the
complete media grid. Clicking a year opens its months; a month cover opens its
matching All Photos anchor. Selecting a different Years, Months or All Photos
level restores that level's scroll and focused cover. Clicking the already
selected level goes to its newest edge. Double-clicking has no separate
navigation meaning. Photo-driven drill-down retains the chosen asset.
Calendar covers use a bounded reading scale: year cards add columns before
exceeding 240 pt in width, and month compositions stop growing at 760 pt and
stay centred in a wider viewport. Their sampling and chronological order do
not change with window size. During live resizing, the native calendar layout
retains one visible period and its position within that period throughout the
drag, including column-count changes and reversal. A newest-edge viewport stays
at that edge. Layout completion owns the restored position; delayed navigation
requests never replay over a resize or later browsing.
All Photos ends at the newest edge with the actual photo and video totals;
no sync state is shown because none is reported.

The window toolbar owns the segmented level control, All Photos size buttons,
original-aspect control and media-type filter. Ordinary All Photos shows the
visible photo-date range in the window subtitle, yielding
to one selection count. Years, Months and gapless overviews keep their period
labels in the content and omit the duplicate subtitle date. Selected backup
uses the toolbar action. Shift-click and Shift-arrow extension
share one fixed anchor and moving endpoint, including when mouse and keyboard
input alternate. They select every photo in item order between those endpoints,
including across row wraps and date headings. Up and Down preserve the visual
column; Left and Right continue in item order across row boundaries. Reversing
direction contracts the range, including through the anchor.
Command toggles retain native additive selection. Selection and rubber-band
feedback remain AppKit owned.
Disabled actions do not forward clicks to media below.

Single-click selects. Double-click or Space/Return opens the current photo
inside the same window, growing from its cell. A mouse or trackpad drag pages
sideways; dragging up shows information and dragging down hides it, then returns
to the grid. The grid remains alive beneath the viewer, which uses the system
window background. Space, Escape or Back returns to the currently viewed asset,
retaining filter and selection. A held Space press triggers at most one
transition, including when focus returns to the grid. The viewer uses native
horizontal page tracking, fit/magnification, video/Live Photo playback and an
information sidebar with complete wrapping values. There is no permanent filmstrip; Left and Right move
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
on one coherent lattice, with native-size media decorations; per-item
interpolation between wrapped rows is not allowed. The native collection adopts
the exact final pitch and retained displayed pixels. Density never implicitly
changes calendar level. Window resizing keeps the nearby visible asset.
Reduce Motion adopts state immediately.

During Mac density changes, the totals retain their own reading track. Photo
faces share a content boundary above the totals, including short libraries whose
row count changes. Overview period capsules remain outside the photo-only clip.
Ordinary media marks also retain a separate reading plane, with complete glyphs
and an x-small spacing-token margin above the totals. A fading mark never inherits
the photos' clipping or scale transform.
Entering an overview hands reading ownership from media marks to period
captions. Different reading families never overlap as legible text during that
handoff or its reversal.

In a compact Mac toolbar, the period chooser is a native toolbar menu with readable short titles and content-based sizing. The toolbar supplies its arrow, padding and background; a fixed form-control width must not create excessive empty space. Selection changes retain the same toolbar item.
