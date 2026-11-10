# Mac Folders

Rules F0–F9 follow `platform-expression.md` and `interaction.md`.
Capabilities and limits are in `../docs/folder-backup.md`.

## The person's question

"Are my photos that are not in the photo library (camera exports, SD cards,
external drives) backed up, and what is still missing?" Adding a folder comes
second. Folders is therefore a second photo grid, not a file manager: it shows
no file list, no path tree and no settings.

## Folders and scoped browsing

- The Photos sidebar has an expandable **Folders** destination. Selecting the
  parent opens one flat native photo grid across all added folder sources,
  without Photo Library items. Its children open individual added folders;
  they do not form a recursive file-system tree.
- Each child opens its own flat native photo grid. The window title is the
  folder name. It is a sidebar destination rather than a pushed page, so it
  adds neither Back nor a synthetic Command-[ route. Selecting the parent
  restores its aggregate browse state. Folder identity and dates do not become
  repeated content headings or sticky rows.
- The parent supports cross-folder search and selection. Source identities and
  overlap handling come from the core, never file-name or image-based host
  deduplication. There is no cover overview, separate All Photos child or
  button, or By Folder / All Photos segmented control: navigation owns scope.
- **State sentence**, one at a time, in this order: drive not connected; needs
  you; backing up N (size); not yet backed up N (only when the person chose
  "only new photos"); "N photos are in the Pixel's Photos". Never "all" while a
  supported photo is unsaved.
- **Unsupported files** are excluded from supported photo/video counts. When
  any exist, a quiet line explains how many will not be backed up. An info
  popover explains their kinds, why they are unsupported and that they stay on
  the Mac, with Show in Finder.
- **Drive not connected:** retain the folder, indexed media and any available
  thumbnails. Explain that completed backups are unaffected and backup resumes
  when the drive returns. Missing access or a read failure is not an empty
  folder. Unavailable files retain their recorded information and viewer fallback.
- A single folder's availability and unsupported-file notes remain ordinary
  content before its photos and scroll away. They neither pin nor turn into
  photo-date captions. The parent grid does not interleave folder summaries.
- The applicable folder's More menu offers Back Up Remaining Photos when any
  are not backed up, Show in Finder, Folder Settings and Stop Backing Up This
  Folder. Settings remains the canonical editor.
- Selecting photos uses the shared native selection rules. Back Up N Photos
  remains visible for any selection and uses the same registration feedback as
  Photo Library. A repeat backup asks once before making another copy in the
  Pixel's Photos; cancellation preserves the selection. Active work is reused
  rather than duplicated. Double-click, Space or Return opens the shared
  in-window viewer, preserving the current collection and inspector.

## Toolbar, date and search

The workspace owns the native title and subtitle (`library.md` section 5).
The aggregate parent title is **Folders**; a child uses its folder name.
Both use only the current visible photo-date range in the subtitle;
there are no inline day headings or floating date capsules. Selection replaces
that subtitle with one selected-item count.

Collection totals appear once below the final photo row, using the current
inventory or complete results. A known aggregate without a trustworthy
photo/video split says items; it never treats every item as a photo. Search, type and
backup filters cannot present a loaded prefix as a complete count. Missing
counts and dates are omitted. A file-derived date keeps its recorded provenance;
the viewer must not call a file-modification time a known capture time.

Both parent and child use the common trailing toolbar order: Zoom Out / Zoom In,
Filter, Add Folder and the applicable folder's More menu, the selection's
backup action, then native Search. Filter has Show (All Photos,
Not Backed Up) and Type (All Types, Photos, Live Photos, Videos, Bursts). The active non-default choice tints its symbol.
There is no extra scope switch beside these controls.

Search starts as a compact magnifier. Clicking it or pressing Command-F expands
the native field. Escape uses native cancellation; clicking content ends editing
while retaining the query. A single-folder search matches file and subfolder
names only inside that source. The Folders parent searches those names across
all added folder sources.
Searching never silently changes scope.

Each scope retains its filter, query and search-field expansion. Each
scope/filter/query combination retains selection and the stable
visible-photo anchor. The aggregate parent has its own state, independent of
its children. The thumbnail-size preference is shared across full photo
browsers. Sidebar navigation and viewer return reuse these same states.
Renaming a folder keeps its source identity; removing the active source returns
to the aggregate parent without removing completed backup records.

Successful backup registration clears only the submitted photos from selection,
briefly reports Added to Backup in the existing action, then removes it if no
selection remains. Failure preserves the selection. The viewer replaces the browsing toolbar and restores the scoped
browser on return. Browse, search, filter, add and backup actions also have
menu-bar equivalents.

## Adding a folder

1. The system open panel chooses a folder (Mac folder, external drive or SD
   card).
2. One sheet asks the single decision (A4): back up everything (existing N
   photos and new ones) or only photos added from now on. It shows the counted
   number and size once known and "Counting…" until then. Cancel and Add at the
   bottom trailing edge.
3. After Add the sheet closes and the new source opens in its own grid; progress
   belongs to Overview. New photos follow the global Auto Backup preference; there is no
   per-folder automatic switch.

Choosing "only new photos" leaves no lasting reminder; the remaining photos can
be backed up later from the folder's More menu or by selection.

## Settings › Folders (Preferences)

The canonical place to manage folders (P6), reached from the Folders row in Mac
Settings or the Folders summary under Auto Backup. Both routes select the same
canonical Settings category. A list of folders (name, location, count or state) with Add Folder…
below it; the Folders page's add button runs the same flow. Footnote: new photos
in these folders follow Auto Backup; stopping a folder deletes nothing on the
Mac or in the Pixel's Photos.

**One folder:** a header with its icon, name, location and state; Show in
Finder; File Rules (with "most people don't need this"); Remove Folder with confirmation. New photos follow the shared Auto Backup setting; this page has no independent automatic-backup switch. There are no concurrency, cache or scan-interval settings
(`settings.md`).

**File Rules** (Advanced): a sheet with two token fields, "Skip these" and "Only
back up these (empty means everything)", with example placeholders such as
`Drafts/` or `IMG_*`. Copy avoids terms like wildcard or relative path. Rules
apply to later checks; photos already in the Pixel's Photos are unaffected.

## Stopping a folder (A5)

An alert: "Stop backing up “Travel”?" with the consequence: new photos in this
folder are no longer backed up; files on the Mac and photos already in the
Pixel's Photos are not deleted. Buttons: Stop Backing Up (default), Cancel. A
deliberate choice, so not styled destructive.

## Empty state (A10)

The duck, "No folders yet", one sentence ("Photos from camera exports, SD cards
and external drives can be backed up to your Pixel too.") and Add Folder…

## Data the page needs

Each item is a fact from the core, never derived in the app (P3):

- Per folder: supported photo count, saved-to-Photos count, in-flight count
  and size, needs-you count, not-backed-up count, availability (connected or
  not).
- Per folder: count of files skipped as unsupported media, by kind. Verify
  that the folder source records these; if it does not, the core needs a field
  before the unsupported line can ship.
- Search over file and subfolder names of indexed media.
- Per photo: the same backup marks as Photo Library (`visual-language.md` V5).

### Folder preference row composition

The Mac folder detail presents Location with a trailing Show in Finder button;
File Rules shows the current include/skip rule counts (or all supported photos
and videos) with a trailing Edit button. The Folder row has a trailing Remove
Folder action and confirmation explaining that original files and saved photos remain. These are ordinary
41-point preference rows that grow for long content; no dismissive rules footer
or leading button-only rows.

Folder count phrases distinguish supported photos and videos in every state,
visible-scope subtitle and Add Folder preview. Video MIME types start with
`video/`; other supported types count as photos. Mixed phrases name both counts;
English uses native plural rules for each kind and the sentence agreement.

The Settings stop-folder control attaches the native confirmation immediately
from its button action, using the stored folder name/path without resolving a
bookmark. Folder removal starts only after confirmation. Both folder and photo
library viewers reuse the same edge-revealed previous/next controls.

## Shared grid updates

The folder browser fetches the complete ordered metadata result for its scope
from the persisted inventory. Search, media type and backup filters define the
result before the grid adopts it. Scan and metadata observations update the
inventory independently of browsing. The grid knows the final row count and
media split when the result arrives. It can display the result while the
collection's backup summary is loading.

The native collection engine is shared with Photo Library and Backup History
(`library.md` section 5). Source adapters supply stable file identities, images,
marks and recorded dates. Membership inserts, removals and moves use diffable
updates; state changes configure visible cells in place without reloading the
grid. A committed filter membership replaces the grid once under a
0.2-second crossfade; Reduce Motion adopts immediately. A pending projection
must not publish previous rows under a new browse scope.

Scope restoration retains selection and a stable photo anchor across refresh,
sidebar navigation and viewer return. A disconnected
source stays browsable from its known inventory. Folder summaries remain
ordinary flow content; there are no nested folder/date sticky headers.
Empty filtered results use No Photos Match with Show All Photos, which clears
Show, Type and the query inside the current scope. Search never widens a child
to the aggregate parent. Genuine empty, indexing, unavailable and failed states
keep distinct explanations and actions.

The folder adapter supplies display-sized stills and video posters. Thumbnail
requests use the indexed asset identity and file revision. A shared small
thumbnail table can supply decoded pixels at cell configuration. The folder
browser fills missing small thumbnails in the background while there is room
in the table. Memory and durable disk renditions can serve a request without
contacting the source drive. The viewport preheats a bounded neighborhood and
gives visible requests priority.
An available camera preview can supply the first image while a display-sized
rendition is prepared. Zoom retains usable pixels while a larger rendition is
loading, and the viewer can seed nearby pages from the same memory cache. File
revisions and thumbnail cache clearing invalidate reuse within the shared
storage budget.

The Folders sidebar parent reveals a native Add Folder symbol while the pointer
is in the sidebar. It runs the same chooser and submission flow as the toolbar
and menu command; leaving the sidebar hides the shortcut.
