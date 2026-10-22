# Component and content rules

These rules apply to all platforms. Treat individual UI feedback as a reason to
inspect every use of the same component or interaction.

## Content and feedback

Working screens show the current state, the next action, and consequences that
change a decision. Show each current state or selection count once. Ordinary
supporting text does not need an information banner.

Keep permission requirements, account changes, deletion scope and irreversible
consequences at the relevant step. Move repeated explanations and implementation
terminology to help or diagnostics. Help is read-only and does not start another
workflow. Receipt, phone-gallery publication and cloud upload remain separate
facts; removing redundant text must not merge their success states.

Rows in one group speak in parallel: each has at most one supporting line, of
similar length and the same grammar (all action phrases, or all states). A
switch already shows on or off, so its line says what it does. Explanations
that apply to the group go in one footnote sentence under it; anything longer
goes to Help. A row's line changes only to report a problem with its action.

Errors remain visible with a recovery action. Routine persistence and preparation
use neutral busy feedback, not warnings. Only an unfinished operation after
execution ends exposes recovery. Do not permanently stack a submitted message
under an existing status. Label file totals as totals, not current-run progress.

## Connection and system notifications

Device identity areas show pairing or verified connection state, never the last
backup result. Saved pairing alone is not an online signal. Show transfer and
phone-gallery outcomes with tasks and backup progress. Completed aggregate
progress says "Transfer complete" only after all queued work and gallery
publication have finished; individual tasks retain their specific gallery
result. An aggregate completion label must not sound like local sender storage
or imply Google Photos cloud backup. Apple aggregate headings and footers share
one state projection, including preparation, waiting and failure priority.

System notifications use the native template and an original-brand monochrome
alpha icon, with no theme-dependent strokes or launch-tile background. Android
uses a 24 dp canvas with a 21 dp mark, exported for each density. The system
already displays the application name: the content title names the current
state, and the body gives one useful next step or consequence. Apply the same
contract to ongoing reception and restart reminders. Never include account
identifiers or filenames on the lock screen, imply cloud backup, or describe
idle readiness as an active transfer. Check actual system rendering in light
and dark notification surfaces.

## Feature discovery

A quiet 8-unit duck-yellow dot indicates an unseen feature, not an error,
unread message count or required action. Use the shared discovery mark and
`brandAccent`; include a localized accessibility label, with no pulse or animation.
Propagate one acknowledgement state from the destination entry to its parent
navigation tab. Opening Settings alone does not acknowledge a nested feature.
Opening the feature overview clears both marks, persists locally across restart
and upgrades, and never enables the feature or grants consent. Key this state by
the feature introduction, not the app version. Avoid marking already visible
routine actions or showing repeated reminders for disabled features.

The Android receiver marks Settings and Experiments until the Experiments overview
has been viewed. Google Photos automatic cleanup remains off until separately
configured and explicitly enabled. Other platforms do not add discovery dots
without a specific discoverability need.

Choose the reminder by its purpose. Introduce an important hidden feature with
one discovery mark; explain an optional setting when the user reaches the
relevant decision; show a blocking condition with its recovery action where it
affects work. Automatic new-photo backup is a contextual candidate after a first
manual backup, only while disabled. Explain folder automation while adding a
source. Do not mark normal preparation, transfer navigation or update checks as
unseen features, and do not add a global badge for every actionable status.

## Layout ownership

Root Apple navigation owns its background across all tabs. On iOS before 26,
standard and scroll-edge tab appearances use the same opaque semantic surface;
media grids respect the legacy tab safe area. Newer system material navigation
retains native rendering. Never fix transparency by painting a single page.

Components own row height, internal padding and icon alignment. Pages own the
spacing between components. Preference groups must not inherit the extra vertical
padding of general content cards. Keep headings and their content together;
trailing actions must not change heading geometry.

Apple preference rows use `DuckPreferenceMetrics`: 52 pt minimum on iPhone and
41 pt on Mac. Descriptions, wrapping and accessibility text can increase height.
Mac sections use `MacContentSection`: 24 pt between sections, a 32 pt minimum
heading area, and 12 pt between heading and content. Content cards and preference
groups have different padding contracts.

Align the visible edges of controls, not just their outer frames. Mac segmented
controls use `duckDesktopSegments` to keep intrinsic size and align within the
trailing slot. Do not fix individual screens with guessed offsets.

Pending original preparation belongs to the same task feed as transfer. It is
active while waiting, and needs attention on failure; it is not a separate
settings destination. Library checks are discovery records, not transfer jobs.
Show their scan progress with scan controls; keep per-photo audit records out
of ordinary navigation.

Content groups containing explanatory text or standalone actions reserve 20 pt
inside the bottom edge on Mac. Row-only groups retain zero extra vertical inset;
row metrics supply their spacing.

## Apple sheet chrome

`DuckSheetLayout` follows `platform-expression.md` A0/A4. On iOS it owns a
`NavigationStack`, an inline navigation title and system cancellation and
confirmation toolbar items. iOS 26 uses the system close/confirm button roles;
earlier versions use Cancel/Done. Fitted detents retain a large option for growing
content. Background, corners and the drag indicator remain system-owned.

On Mac, the title is bold semantic content text, forms use grouped `Form`, and
native push buttons sit at the bottom trailing edge. Cancel uses the cancel
keyboard shortcut; the default action is prominent and Return-activated. There
is no close X or painted header/footer. Long explanations end with Done.

A dirty name editor blocks interactive dismissal and offers a native discard
confirmation from Cancel. Busy sheets disable dismissal. Errors use neutral
semantic text with one small colored symbol, without a colored notice surface.
`DuckSheetHeader` remains a compatibility adapter for standalone title content;
new sheets use the complete layout so navigation owns its toolbar.

## Brand resources

Use the approved `assets/AppIcon.png` as the source for launch and system marks.
System-chrome marks remove the background and derive a monochrome mask while
preserving the original silhouette, wing and eye. Do not redraw a similar duck
or place a scaled full-color launch tile in the menu bar.

The Mac template uses a 20 pt canvas with an approximately 18 pt mark. Check it
beside system symbols in light and dark appearances. Regenerate derivatives
with `scripts/export-menu-bar-icon.swift` after changing the source.

## Submission and long-running work

Confirmation dialogs save durable intent and close after successful registration.
Downloads, original-resource export, scanning and transfer continue through the
persistent task pipeline. Preparation, failure and retry appear on task screens.
Submission failure preserves selection and input; submission success does not
mean original preparation or transfer has completed.

Keep request identity, receiver ownership, source revision and repeat intent
across restart. Never redirect existing work to a newly paired receiver.
Ordinary page actions have no static ellipsis; busy states use specific text.

User-initiated external operations return to their result page after finishing,
including setup checks and recovery. Returning must not launch the operation
again. Preserve the external app's required safety confirmations; if the user
leaves that app or locks the device, do not interrupt them to show a result.
Automatic background operations do not open a result page without user intent.

## Change procedure

1. Identify whether the cause is content, component composition or business state.
2. Inspect similar uses and fix the shared component or explicit platform setting.
3. Update contracts and affected prototypes in the same change.
4. Run existing relevant checks and inspect actual native windows. Add coverage
   for new states; checking that text exists is not a visibility check.
5. Separate build results, installation, observed behavior and physical-device
   coverage. Document limitations without personal development narratives.

## Sender media browsing

Preview uses the current filtered/sorted library context and stable asset identity.
Previous/next navigation preserves selection and the parent's scroll anchor.
Phone paging tracks a drag continuously with adjacent pages; information stays
in an in-place drawer. A zoomed image owns pan input. See the
[media interaction contract](apple-media-interactions.md).
Photos support fit/zoom, Live Photos use PhotosUI playback, videos use AVKit.
Information shows real capture date, dimensions, format, available EXIF and location;
missing fields are omitted, never guessed. Information access is read-only.

Grid image targets use cell size times display density, with bounded quality caches
and visible requests. Detail targets are high quality and bounded to 4096 pixels.
PhotoKit may resolve local and iCloud previews automatically under system Photos
access and network policy. There is no app-level browsing consent or network
preference. A media-local ring owns loading and retry; browsing never registers
backup work. Visible cloud requests remain bounded and off-screen prefetch stays
local. A missing larger rendition must not discard an available tiny cover.
EXIF reads occur only when information is opened. No private file-size API is used.

## Photo backup scope

Persistent backup scope is separate from temporary gallery filters and explicit
manual selection. Still photos, Live Photos, video and bursts are disjoint
categories. Multiple types/albums form a union within that dimension; type and
album dimensions intersect. No selected types, or restricted albums with no
accessible matches, means an empty scope, never the whole library.

The scope applies at new-media discovery and existing-scan snapshot capture.
Changing it does not start historical work or rewrite persisted preparations;
paused/resumed scans use their frozen IDs. Deleted/restricted albums remain
visible as unavailable configuration until the user changes their selection.
Manual selected-item backup follows the explicit selection instead of silently
excluding items. Folder rules remain source-specific, separate from Photos albums.

## Library time views

On iPhone, use the [calendar Grid contract](iphone-calendar-grid.md): Years,
Months and All are a cover hierarchy, with independent All-grid density. Full
navigation, compact calendar browsing and selected-item actions are mutually
exclusive bottom states. Desktop now follows the [Mac library contract](macos-v1.2/specification.md#photos-library): Years/Months/All Photos is independent of size. The grouped modes below describe the retained legacy layout helper, not desktop navigation.

All/Days/Months are presentation modes over the same filtered, sorted asset IDs.
Days group by local-calendar capture day; Months group by capture month and use
denser thumbnails. Missing capture dates form an explicitly unknown group.
Changing mode preserves the visible asset anchor and selection. At the beginning
of the library, retain the top so the new date heading remains visible.

Calendar grouping and density are distinct. Pinch progress updates native tile
attributes and the vertical scroll anchor on every frame. Three/five/seven/nine
phone columns provide progressively denser browsing; Months starts at seven.
Grouping labels crossfade. Disable pinch during range selection, and cancel
obsolete motion before replacing membership. Reduce Motion adopts the anchored
layout immediately. Desktop magnification also updates during the gesture.
Virtualization uses bounded visible-rectangle lookup for cells and headings.

Backup scope shows two summary destinations, Media types and Specified albums.
All albums is an explicit switch. Removing the final explicit choice keeps the
scope restricted and empty until All albums is turned on again. Retained but unavailable selected albums never widen the scope. Show user
albums initially; fetch previously selected system albums only to preserve edits.
iPhone album covers use three reusable native columns (a readable list at
accessibility sizes), explicit item-count units, and display-scale thumbnail targets. Album
selection is searchable and virtualized; it never expands the parent page.
A tap (iPhone) or click (Mac) on a cover toggles its choice; covers stay the
choosing surface because unselected covers carry no mark to aim at. The cover's
long-press menu (iPhone), secondary-click menu (Mac) and an accessibility action
open the album read-only in the library grid, backed by an album-scoped
`PhotoLibraryModel` with its own paging, thumbnail pipeline and scroll. Browsing
never changes the scope or registers work; the album page's only scope control
is the same explicit choose/deselect toggle. Back returns to the picker with its
scroll position, search, summary line and selection unchanged.
Independent choices use checkmarks. Persistent Booleans use leading-label,
trailing-switch preference rows.

## Media selection cells

iPhone image-based choices share one selection treatment across gallery, album
covers and selected-item review: a 23 pt blue filled check circle with a white
backing, inset 6 pt at bottom trailing. Only selected cells show the mark. Selected
media opacity is 0.72; the cover bounds, caption and image request identity stay
unchanged. Do not add a second border or top-corner check. Form preference rows
retain a trailing plain checkmark and a fixed slot; selection changes neither
fade the row nor replace it. Pressing a scope choice does not dim its entire label.

Album cover requests use the gallery thumbnail pipeline: exact, display-density
size, revision-aware bounded cache, reuse/offscreen cancellation, local first,
and system access/network policy for cloud fallbacks. Never reset an unchanged
cover to its placeholder on a selection update.

Standalone Apple loading states use `DuckLoadingState`, centered across their
content region with a specific action label. A cache-settings read must not say
that a backup is loading. Initialization failures expose recovery rather than an
indefinite spinner. Inline progress beside an action or control retains its slot.
