# Apple backup Live Activity

A compact task surface for iPhone/iPad: remaining photos, receiver, current
state, and an explicit pause/resume action. It uses system Lock Screen and
Dynamic Island presentations, semantic typography and the shared role tokens.
It is not a scheduler and does not grant additional background execution.

## Composition

The Lock Screen uses one compact horizontal composition: a leading publication
progress ring, a central remaining-photo headline and receiver/state subline,
and a trailing system pause/resume button. WidgetKit owns the background,
clipping, wallpaper treatment and placement. There is no app-drawn control
background or forced color scheme (platform-expression.md A0).

The ring occupies the shared 48-point spacing unit, with 16-point content
padding and 12-point gaps. Headline and subheadline use semantic styles and wrap.
State changes retain the same slots. Unknown/stale progress shows a state glyph
without a percentage. Saving, attention and stale states offer Open. State
color belongs to a small glyph; titles and body text remain neutral (V1/V5).

Dynamic Island uses the same facts in system regions: expanded uses the
horizontal composition; compact uses a ring and remaining count; minimal uses
the ring/state glyph. The native catalog shows both Lock Screen content and
compact content with synthetic state, without drawing system chrome or enabling
backup actions. It does not establish system presentation acceptance.

## Facts and scope

The Rust whole-receiver task summary supplies active, attention, saved and total
counts, including original preparation. A presentation session starts with the
then-published count as its baseline. Its denominator includes outstanding work
and work added during that session; completed photos from before the session do
not inflate its progress. No asset IDs, filenames, thumbnails or credentials are
sent to the widget. Receiver and session IDs bind actions but are not displayed.

While the historical scan is still discovering membership, show its state and
the currently known remaining count without a percentage. Never treat scanning
or byte receipt as gallery completion. Saving to Photos remains an active phase;
failed photos remain an attention result. A regression or unknown observation
must not manufacture completed progress.

## Lifecycle

- Start at most one activity for the selected receiver while foregrounded and
  active work exists. Respect the system's Live Activities permission.
- Reuse an existing activity after process restart; end activities belonging to
  an old receiver after an observed pairing change/removal.
- Update during execution opportunities already granted to the app, including
  background URLSession/BGProcessing callbacks. Do not claim uninterrupted
  updates while the process is suspended.
- Mark content stale after a bounded freshness interval. A stale widget says to
  open BackupDuck for the current state and does not imply ongoing progress.
- End when active work drains. All saved is a completion; unfinished attention
  has its own result. Clear the Lock Screen promptly after success.
- Do not recreate a user-dismissed activity for the same undrained work. Rearm
  after the host observes that active work drained.

## Interaction and accessibility

A LiveActivityIntent runs in the app and calls the existing Rust-owned pause
operation. It carries an explicit desired pause state, receiver and session;
a stale button cannot toggle a newer batch or another receiver. Persist intent
before showing its result. Pause controls sending and preparation; receiver
gallery publication can continue. A gallery-only saving phase offers Open rather
than a pause control that cannot stop the receiver. Failure remains actionable by opening BackupDuck.

Tapping the activity opens Backup. Text wraps and uses semantic styles; compact
presentations use the ring and remaining count with a spoken scope. Under stale
content, large text and reduced motion the same facts remain available without
custom animation, blur or a newly inserted progress row.

## Validation

Test projection boundaries, restart/dismissal policy, receiver/session ownership,
unknown/scanning progress, saved versus received and action failure. Build both
the host and embedded widget. Review synthetic Lock Screen/expanded/compact
presentations in light/dark and large text. System activity creation, lock-screen
pause/resume, stale rendering and background updates require separate native
system and physical-device observations. The catalog alone does not prove them.

Implementation references: [ActivityKit lifecycle](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
and [interactive widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities).
The pause intent is allowed on the Lock Screen, but validates the current
receiver/session and only edits existing durable backup intent. It does not
expose photo contents or grant access to new media.
