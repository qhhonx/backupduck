# Motion and stable feedback

Motion explains cause and hierarchy. Avoid decorative loops, bouncing, breathing
brand accents and continuously spinning mascots. Receiver/media performance takes
priority on older devices. Use native transitions for standard system controls.

| Custom interaction | Duration | Treatment |
| --- | --- | --- |
| Press/highlight | 80–120 ms | Background or opacity, ease-out |
| Switch | 160 ms | Thumb displacement, cubic-bezier(0.2, 0.8, 0.2, 1) |
| Status replacement | 120 ms | Fade without changing container geometry |
| Scrim entry | 140 ms | Opacity |
| Detail/pairing entry | 220 ms | Fade and up to 12 units displacement |
| Overlay exit | 160 ms | Fade and up to 8 units displacement |
| Confirmed progress | 320 ms | Interpolate actual progress |
| Filter/sort | Immediate | Update data without moving the entire list |

Progress is a 2-unit overlay on a stable status region, not another layout row.
Show byte progress only during actual transfer with meaningful partial progress;
waiting, completed and unrelated preparation states do not leave an empty track.
Large text adapts the layout without clipping. Failures and important consequences
remain visible even when they require more space.

Update rows by stable identity. Image loading replaces a fixed thumbnail slot.
Preserve scrolling, selection, filters, pagination and expanded folders. Replace
status content instead of inserting transient warnings above the working list.
A retry request must not trigger a completion animation.

Respect Reduce Motion/Remove Animations and `prefers-reduced-motion`: remove
spatial motion and progress interpolation while retaining immediate feedback.
Reduced transparency and contrast settings are separate and do not hide content.
Return focus to the trigger after closing an overlay; do not repeatedly interrupt
screen readers for every progress update.

Inspect transfer, pause, failure, completion and offline transitions in actual
native windows. Check long lists, narrow screens, large text and reduced motion.
Prototype transitions are references, not proof of native execution or old-device
frame-rate performance.

Library density changes update stable native collection attributes and the scroll
anchor together on every gesture frame. Gesture progress follows image scale;
release uses a normalized critically damped response over 320 ms, cancellation
over 300 ms, and menu changes over 420 ms. Mac changes use the same response
over 260 ms. Phone pinch retains its initial focal point during the gesture, then
settles the column edges while preserving vertical context. Date headings crossfade
when grouping changes. Never restore the anchor only after the animation ends.
Phone detail paging uses native scroll deceleration and neighbouring live views,
not an onEnded replacement. Information opens within the same media viewport.
See [Apple media interactions](../apple-media-interactions.md) for reversal,
zoom ownership, scope navigation and accessibility acceptance.

The focused [iPhone calendar Grid contract](../iphone-calendar-grid.md) supersedes
the older phone coupling of calendar grouping and density. Its cover transition
uses one image between actual member anchors while the bounded old scene fades.
Density settles over 380 ms with a normalized critically damped response. Bottom
chrome minimization and calendar-accessory placement use the system transition
on supported iPhones. Navigation-item updates retain native sizing and group
transitions without adding operations. Legacy chrome uses an interruptible
300 ms settle; reversal continues from the visible pose. Two-finger translation and a final single touch cannot move the pinch focal point. Range
selection yields to a second finger and restores its baseline. Native media
detail behavior remains a separate interaction.
