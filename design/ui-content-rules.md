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

Errors remain visible with a recovery action. Routine persistence and preparation
use neutral busy feedback, not warnings. Only an unfinished operation after
execution ends exposes recovery. Do not permanently stack a submitted message
under an existing status. Label file totals as totals, not current-run progress.

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

Components own row height, internal padding and icon alignment. Pages own the
spacing between components. Preference groups must not inherit the extra vertical
padding of general content cards. Keep headings and their content together;
trailing actions must not change heading geometry.

Apple preference rows use `DuckPreferenceMetrics`: 52 pt minimum on iPhone and
48 pt on Mac. Descriptions, wrapping and accessibility text can increase height.
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
