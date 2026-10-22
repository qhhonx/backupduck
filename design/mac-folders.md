# Mac Folders

Status: structure approved by the owner on October 21, 2026 (F0–F9). Built from
`platform-expression.md`, `interaction.md` and the Mac window of the October 19
canvas. Capabilities and limits are in `../docs/folder-backup.md`.

## The person's question

"Are my photos that are not in the photo library (camera exports, SD cards,
external drives) backed up, and what is still missing?" Adding a folder comes
second. Folders is therefore a second photo grid, not a file manager: it shows
no file list, no path tree and no settings.

## Folders page (Browse)

- Sidebar position Photos › Folders (A3). Content type Browse (`interaction.md`
  I2), the same skeleton as Photo Library.
- **Default view, by folder:** each added folder is a section with its name,
  where it lives ("SanDisk external drive", "Pictures › Camera exports"), one
  true state sentence and a more menu, followed by its recent photos.
- **State sentence**, one at a time, in this order: drive not connected; needs
  you; backing up N (size); not yet backed up N (only when the person chose
  "only new photos"); "N photos are in the Pixel's Photos". Never "all" while a
  supported photo is unsaved.
- **Unsupported files** (for example RAW, which the Pixel's Photos cannot store)
  are not counted in the state sentence. When a folder has any, one quiet line
  under the section says how many will not be backed up, with an info button
  that opens a popover: what they are, why, and that the files stay on the Mac,
  with Show in Finder.
- **Drive not connected:** the section dims and says that photos already backed
  up are unaffected and that backup continues when the drive returns.
- **Section more menu:** Back Up Remaining Photos (when any are not backed up),
  Show in Finder, Folder Settings…, Stop Backing Up This Folder…
- Selecting photos with click and ⌘/⇧-click shows one primary action on the
  toolbar's trailing edge, "Back Up Selected", when the selection contains
  photos that are not backed up. Backing up a selection saves the intent at
  once and needs no second confirmation.
- Double-click opens the photo viewer window with its info inspector (A8).

## Toolbar (A2)

The leading side contains only the sidebar toggle and the title **Folders**,
with a subtitle describing the visible scope: for example, “3 folders · 1,284
photos” or “Not Backed Up · 312 photos”. Only a pushed level adds Back between
the sidebar toggle and the title. Counts come from the current inventory or
complete results; a paged search never presents its loaded count as a total.

Trailing groups keep this order, with native shared capsule backgrounds:

1. A shared Zoom Out / Zoom In capsule only if the grid supports density.
   The current Folders grid has fixed density and omits this group.
2. A **By Folder | All Photos** segmented capsule, replaced by a pop-up at
   narrow window widths or while search is expanded. Each view retains its own
   scroll position and selection (I6).
3. One action capsule: **Filter**, **Add Folder**, then **More** when a single
   folder applies. Filter offers All, Not Backed Up, Needs You and Recently
   Backed Up. An active filter has a filled, tinted symbol; choosing All clears
   it. There is no separate clear button. More offers Show in Finder and Folder
   Settings… for the applicable folder.
4. **Back Up Selected**, the single prominent text action, appears only while
   the selection contains eligible photos that are not backed up.
5. **Search**, a separate magnifier circle at the trailing edge. Clicking it or
   pressing ⌘F expands and focuses a native search field. Escape collapses an
   empty search. Search finds file and subfolder names within added folders.

The viewer replaces the browsing toolbar. Returning restores the search query,
its expanded state, the active view, filter, selection and scroll position.
View, filter, Add Folder, Back Up Selected and Search also have menu-bar
equivalents.

## Adding a folder

1. The system open panel chooses a folder (Mac folder, external drive or SD
   card).
2. One sheet asks the single decision (A4): back up everything (existing N
   photos and new ones) or only photos added from now on. It shows the counted
   number and size once known and "Counting…" until then. Cancel and Add at the
   bottom trailing edge.
3. After Add the sheet closes and the new section appears; progress belongs to
   Overview. New photos follow the global Auto Backup preference; there is no
   per-folder automatic switch.

Choosing "only new photos" leaves no lasting reminder; the remaining photos can
be backed up later from the section menu or by selection.

## Settings › Folders (Preferences)

The canonical place to manage folders (P6), reached from the Folders row in Mac
Settings. A list of folders (name, location, count or state) with Add Folder…
below it; the Folders page's add button runs the same flow. Footnote: new photos
in these folders follow Auto Backup; stopping a folder deletes nothing on the
Mac or in the Pixel's Photos.

**One folder:** a header with its icon, name, location and state; Show in
Finder; File Rules (with "most people don't need this"); Stop Backing Up This
Folder… There are no concurrency, cache or scan-interval settings
(`feature-triage.md`).

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
