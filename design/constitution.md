# BackupDuck design constitution

This document describes what good BackupDuck design is and how design work is
done. Component contracts describe how individual parts behave.

## Sources of truth

- **Production components** decide what the product actually looks like.
- **Contracts** (this document and the component rules) constrain behavior and
  meaning. Code that contradicts a contract is a bug, not a new rule.
- **The design catalog** provides repeatable review scenarios built from the
  production components.

## Principles

**P1. Photos are the subject.** The interface frames the user's own photos.
When a moment needs warmth or proof, use their photos before illustrations, and
illustrations before text.

**P2. One meaning, native expression.** Every platform shares what things mean:
states, consequences, where information belongs and the brand. Each platform
expresses that meaning with its own controls, navigation and conventions. Never
hide or rebuild a system component to match a picture.

**P3. One true state, said once.** Receipt, phone-gallery publication and cloud
upload are separate facts with separate words and marks. Each surface (row,
overview, notification, Live Activity) projects them from the same source.
Unknown stays unknown.

**P4. One primary action per context.** A task context has at most one primary
action. A desktop split view or a media browser may combine several contexts on
one screen.

**P5. Teach in place.** No tours or coach marks. Teaching belongs in the first-run
flow, just before a permission or consequential choice, in empty states and in
Learn more sheets. Footers are one sentence.

**P6. One canonical place per preference.** Each preference is edited in exactly
one place. Contextual shortcuts may navigate there or mirror the same control
bound to the same model. Long-running tasks are not preferences.

**P7. Calm by default.** Motion explains cause, badges mean something to do and
color means a role. Nothing pulses, loops or celebrates routine work.

**P8. Feel is measured.** Motion, scrolling and launch are judged on Release
builds with 60 fps recordings on old devices. Record the system app's behavior
for the same interaction first.

**P9. Design from the long-term target.** Decisions start from the intended
platform set and product, not from what the current code happens to do.
Structure that no longer fits is removed rather than preserved. Existing
capabilities are an inventory, never a design to port. § Redesign before
refinement makes this a gate.

## Layers

| Layer | Shared across platforms | Examples |
| --- | --- | --- |
| Brand | Identical | Brand primaries, duck character, wing mark, voice, illustration |
| Product | Same meaning | Device roles, state vocabulary, consequences, information ownership, content types |
| Platform | Native | Navigation, controls, presentation, materials, type rendering, system fallbacks |

- **Copy** keeps the same terms and meaning everywhere. Wording may adapt to a
  platform's interaction model, localization and available space.
- **Motion** spans all three layers. A completion moment is a product decision,
  the duck's performance is a brand decision, and playback and reduced-motion
  fallback are platform decisions.

## Platforms and roles

| Platform | Sender | Receiver | Dialect |
| --- | --- | --- | --- |
| iPhone / iPad | Shipped | Possible | Apple HIG |
| Mac | Shipped | Possible | Apple HIG (macOS) |
| Android | Possible | Shipped (Pixel) | Material 3 on Views and Material Components |
| Windows | Possible | — | Fluent |
| Browser, receiver management | — | Shipped | Web dialect |
| Browser, client | Possible | Possible | Web dialect |

**The Web dialect** has no platform guideline to inherit. It uses the brand and
product layers strictly, with restrained solid-surface controls that imitate
neither iOS nor Material. The receiver serves it locally, so it stays small,
works offline and loads no third-party resources. Quality comes from typography,
spacing, state expression and the signature elements. WCAG 2.2 AA is the
acceptance baseline. The management page always states which receiver it
manages and never presents capabilities that only a native client has.

## Color

**Brand primaries** come from `assets/AppIcon.png`. They are fixed values used
in illustration and brand marks:

| Primary | Role |
| --- | --- |
| Wing blue | Seed for the interface accent |
| Duck yellow | Brand moments, discovery mark; also marks Pro, but is never exclusive to it |
| Beak orange | Illustration only; never interface state |

**Interface roles** are semantic. Each platform maps them to its own colors:

- **Accent** means "interactive or in progress". It is derived from wing blue
  per platform, with light, dark and increased-contrast variants. Apple uses it
  as the tint. Android generates a fixed Material 3 scheme from it; wallpaper
  dynamic color is not used. Web defines its own light and dark pair.
- **Neutral roles** (`background`, `groupedSurface`, `elevatedSurface`,
  `primaryText`, `secondaryText`, `separator`) map to system colors on Apple,
  to Material color roles on Android, and to defined pairs on Web. There is no
  global brand-tinted canvas.
- **State roles** (`saved`, `received`, `attention`, `failure`) always pair with
  an icon or text. In-progress reuses the accent. Received and saved use
  visibly different marks, not two shades of one mark.
- On Android, foreground and container colors are used in Material's pairs.

**Illustration palette** is the three primaries plus a small set of tints, for
onboarding, empty states and future memory content. It never colors controls.

`tokens.json` defines primaries, seeds and roles. The export script generates
every platform's values. Platform code does not define colors locally.

## Typography, spacing and shape

- Text uses semantic styles mapped to each platform's scale (Dynamic Type on
  Apple, the Material type scale on Android, a defined scale on Web). A
  hard-coded size replaced by a generated number is not a semantic style.
- Apple status cards may use rounded, monospaced numerals. This is a platform
  choice, not a cross-platform brand rule. Check long counts, units, Dynamic
  Type and width stability while values update.
- Shared spacing, radius and motion tokens apply to custom-drawn surfaces.
  System controls keep their platform metrics, padding and animation.
- Exceptions to these rules are allowed when they are written next to the code
  that needs them.

## Brand character

**The duck** is the main brand character. **The wing** taken from the icon is
the small mark.

| Use | Element |
| --- | --- |
| First run, empty state, first completed backup, Pro, milestones | Duck character |
| Step numbers, small badges | Wing mark |
| Errors, warnings, working screens | Neither |

Rules:

- At most one duck per screen.
- Animations play once. They do not replay when the user returns to the page
  and stop when the page is left. Reduced Motion shows a static frame.
- Decorative illustrations are hidden from assistive technology.
- An empty state ("nothing here yet") is distinct from restricted access or a
  loading failure. The latter two lead with the cause and the recovery action.
- Animation format (for example Lottie) is decided after the first two or three
  animations are defined, by comparing size, compatibility and playback cost.

Production:

1. Build a layered vector master from the icon. It fixes the body
   outline, head-to-body ratio, tail, beak, eye position and the wing's
   characteristic curve.
2. Define the allowed variations: expression, head angle, accessories, and the
   wing's waving posture. The waving wing is a pose that
   keeps the wave's recognizable features rather than the exact path.
3. Explore poses with image models.
4. Build each pose from the master and review it side by side with the
   icon by a person.

Poses with the smallest deviation from the master are looking at a phone
(pairing), holding a photo (done), napping (waiting) and wearing a crown (Pro).

## Information architecture

Each role has four default positions. This is a default skeleton, not a fixed
tab count.

| Position | Sender | Receiver |
| --- | --- | --- |
| Content | Library | Storage |
| Hub | Backup | Receive |
| Devices | Paired receivers, pairing | Paired senders, pairing |
| Settings | Backup, General, Support | Receive, General, Support |

- **Hub** is the task center: current state, one primary action, and summaries
  that open records already filtered (failed, waiting). It always offers an
  entry to all records. Returning from records preserves filter and scroll.
  System notifications open the relevant task or failure list.
- Phones use four tabs. Mac and Web sidebars may list Records separately, but it
  still belongs to the hub.
- **Devices** earns its own position only if it holds up in catalog scenarios
  with no peer, one peer and several peers.
- **Mac settings** live in the main window as a sidebar position. ⌘, and the menu
  open the same place. There is no separate Settings window.
- **Dual-role devices** (future) are architecture test scenarios, not current
  work. Before one ships, decide how content distinguishes local sources from
  received items, and whether each setting applies to this device, a peer or a
  direction.

### Content types and presentation

Content type says what a screen does. Presentation says how it opens, and
belongs to the platform.

| Content type | Purpose |
| --- | --- |
| Browse | Media first, selection and contextual actions |
| Task center | Current state, primary action, summaries |
| Records | Stable list of tasks or events, filters |
| Preferences | Grouped saved values and switches |
| Chooser | Searchable, virtualized selection with a summary |
| Detail | One item's facts and actions |
| Guided flow | One decision per step, fixed primary action |
| Explanation | Read-only help or Learn more |

Presentations include push, sheet, popover, split pane, window and full screen.
Any content type may use the presentation its platform expects.

System permission, camera, picker, sharing and installation UI remain actual
platform interfaces.

## Copy

- Name results in the user's terms ("Saved to the Pixel's Photos"), not mechanisms.
- Avoid absolute claims that the implementation cannot guarantee. For example:
  "Originals go directly to the device you paired; BackupDuck does not relay
  them through its own cloud." Verify any such statement against actual network
  behavior before shipping.
- Counts state their scope: this run, all time, this peer or all devices.

## How design work is done

### Change levels

| Level | When | Required work |
| --- | --- | --- |
| Small | Uses existing patterns; no change to behavior or information ownership | Implement; accept in the affected scenarios |
| Medium | Changes an existing component's expression or local behavior | Check every use; update the contract; accept on affected platforms |
| Large | Introduces navigation, state meaning, a permission flow or a new interaction pattern | Define problem, states and flow; explore where needed; accept components and flows |

Extracting a shared component without visual change, or adding a token for an
existing value, is Small or Medium. Large work does not require two alternatives
when a clear reference exists; record the reason and go to native validation.

### Redesign before refinement

A page change starts from the user's question and a fresh structure before
visual refinement. Defect, safety and data-loss fixes may use the existing
structure; any other change to a page whose structure does not answer the
user's question is Large and follows these steps:

1. **The user's question.** State in one sentence what the page's user comes
   to learn or do, and what they never need to see there. For most pages this
   is an ordinary user; for technical pages (diagnostics, logs, exports,
   compatibility routes) it is someone troubleshooting or helping a person
   troubleshoot. A technical audience changes what the page shows, not whether
   it is designed: every page goes through these steps.
2. **References.** Record how the system app and reference products handle the
   same question (§ References).
3. **Fresh structure and copy.** Derive sections, states and words from the
   user's question, references and `copy-glossary.zh.md`. Existing pages tell
   which capabilities exist; their layout, grouping, controls and strings are
   not carried over because they exist.
4. **Native composition.** Build from production components in the catalog,
   with scenarios for key states, and check the structure, flow, copy and
   visual language on devices.

A page's embedded pages and components (a sheet, a list row, a flow) follow the
same rule before it ships. Catalog coverage, copy sweeps and fixes do not
substitute for a structure that answers the user's question.

### References

Record the system app and reference products doing the same task. When nothing
matches, split the task into basic interactions (select, confirm, wait, recover,
browse) and find each separately. If that still fails, build two switchable
native variants and compare them on a device. Record the resulting rule and its
reason in the contract.

#### What references are for

References are not skins to choose between. They teach two different layers,
and BackupDuck digests them into its own point of view:

- **Product craft**: settings, features, first run, guidance and taste, so the
  app reads as made by experienced product and design people. Technical inputs
  become life questions; first run says what the user invests and gets, asks one
  thing per screen and explains a permission right beside it; the first real
  success is defined on its own; requests such as notifications come after
  value; waiting shows real content and stages; small fixes happen in context;
  settings put the important object first with its current value and move long
  explanations into sheets.
- **Feel**: overall style, interaction, visual effects and fluency, so the app
  is smooth and comfortable. Content stays put while navigation floats over it;
  grid, viewer and back return to the same place; each platform keeps its own
  layout with the same meanings; lists scan as state tables with marks only for
  actionable state; motion explains one object entering, being selected or
  changing level; settings go condition, object, threshold, with a summary on
  top; impact is shown before an action.
- **No surface is copied.** Colors, radii and photo cards make neither a mature
  product nor a smooth one. BackupDuck's positioning (an old Pixel as unlimited,
  free photo backup that the user sets up once and then trusts) decides what to
  show. The standards that follow from this are `visual-language.md` and
  `interaction.md`.

Reference observations, measurements and mappings are working material. They
are kept with the local design notes (`build/internal-docs/`, see
[public-source policy](../docs/public-source-policy.md)) and are not named in public files.

### Design catalog

The catalog is a debug-only and separately buildable review target in each
native app.

- It renders the **same production pages and components**. It replaces data
  providers and action executors with scenario drivers. It never reimplements
  pages or business queues.
- Scenarios state the expected state and the result of each action. A screenshot
  that renders is not proof that it means the right thing.
- Scenarios include continuity flows: submit, leave, change in the background,
  return and recover.
- The catalog runs in Release configuration so motion and old-device performance
  can be judged.

**The catalog is complete when it can support a review of the whole design**:
the full navigation skeleton, every content type, the key states of each, and a
few complete representative interactions. It is not a second finished product.

### Enforcement

- A check fails when page code introduces a literal color or text size outside
  the token and semantic-style system without a documented exception.
- Screenshot matrices are generated from catalog scenarios and run according to
  the change's scope, not across every platform for every small change.
- People review consistency side by side. Model output assists the review but
  does not replace it.

## Coverage

Every catalog review and large change considers:

- **Input and navigation**: VoiceOver and TalkBack order, keyboard and focus,
  Android system back, iPad split views and window resizing.
- **Continuity**: restart, revoked permission, missing source, offline peer and
  switching peers; existing work keeps its owner.
- **Counts and progress**: scope is explicit; received and saved stay distinct.
- **Localization**: long device names, plurals, number and date formats,
  right-to-left layout.
- **Old devices**: solid surfaces and bounded work on the oldest supported Pixel.
- **Upgrades**: reorganized settings keep their values; old notifications, help
  paths and deep links still reach the right place.
- **Paid state**: before designing the upgrade page, decide the free promise and
  what happens to reading, exporting, recovery and queued work when
  entitlements end.

