# BackupDuck design constitution

Status: draft 2 for review. It records decisions from the October 2026 design
review. Until it is adopted, the existing contracts in `ui-content-rules.md`,
`backupduck-v1/specification.md` and `backupduck-v1/motion.md` remain in force.
Once adopted, this document replaces their overlapping guidance.

This document describes what good BackupDuck design is and how design work is
done. Component contracts describe how individual parts behave.

## Sources of truth

- **Production components** decide what the product actually looks like.
- **Contracts** (this document and the component rules) constrain behavior and
  meaning. Code that contradicts a contract is a bug, not a new rule.
- **The design catalog** provides repeatable review scenarios built from the
  production components.

The maintained HTML prototypes are retired. Disposable explorations (sketches,
HTML, generated images) may be used during a discussion. They are deleted once
a decision is made and are never cited as a specification.

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
platform set and product, not from what the current code happens to do. Legacy
structure that no longer fits is removed rather than preserved. This version is
rewritten for ordinary users; the earlier apps are an inventory of capabilities,
never a design to port. § Redesign before refinement makes this a gate.

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
  dynamic color is not used for now. Web defines its own light and dark pair.
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
- Apple status cards may trial rounded, monospaced numerals. This is a platform
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

1. Build and approve a layered vector master from the icon. It fixes the body
   outline, head-to-body ratio, tail, beak, eye position and the wing's
   characteristic curve.
2. Define the allowed variations: expression, head angle, accessories, and the
   wing's waving posture. The waving wing is a separately reviewed pose that
   keeps the wave's recognizable features rather than the exact path.
3. Explore poses with image models.
4. Build each approved pose from the master and review it side by side with the
   icon by a person.

The first production set is the poses with the smallest deviation from the
master: looking at a phone (pairing), holding a photo (done), napping (waiting)
and wearing a crown (Pro). Waving and lowered-head poses follow.

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

Every page is either **redesigned** or **legacy**, as recorded in
`page-register.md`. A page is redesigned only when it has gone through these
steps and was approved in review:

1. **The user's question.** State in one sentence what the page's user comes
   to learn or do, and what they never need to see there. For most pages this
   is an ordinary user; for technical pages (diagnostics, logs, exports,
   compatibility routes) it is someone troubleshooting or helping a person
   troubleshoot. A technical audience changes what the page shows, not whether
   it is designed: every page goes through these steps.
2. **References.** Record how the system app and the reference products
   handle the same question (§ References).
3. **Fresh structure and copy.** Derive sections, states and words from steps 1
   and 2 and `copy-glossary.zh.md`. The legacy page only tells which
   capabilities exist; its layout, grouping, controls and strings are not
   carried over because they exist.
4. **Catalog review.** Build it from production components behind the catalog's
   design switch, with scenarios for its key states, and review it on devices.
   This approves the structure, flow and copy. The page's look is approved
   separately, through the visual language (migration step 6).

Rules that follow:

- **No refinement of legacy pages.** Do not polish copy, add scenarios, add
  features or restyle a legacy page. Fix defects, safety and data-loss problems
  only. Any other change to a legacy page is Large and starts at step 1.
- **No legacy inside a redesigned page.** A redesigned page that opens or embeds
  a legacy page or component (a sheet, a list row, a flow) lists it as a
  remnant in the register. The remnant is redesigned before the page ships.
- **Coverage is not progress.** Catalog coverage, copy sweeps and fixes are
  scheduled against the register. Before touching any page, check its status;
  if it is legacy, redesign it first.
- **Say which.** Reviews, summaries and commit messages name whether a page is
  redesigned or legacy, so porting cannot pass as redesign.

### References

Record the system app and reference products doing the same task. When nothing
matches, split the task into basic interactions (select, confirm, wait, recover,
browse) and find each separately. If that still fails, build two switchable
native variants and compare them on a device. Record the decision and its
reason in the contract.

#### What references are for (owner, October 19, 2026)

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
`docs/public-source-policy.md`) and are not named in public files.

### Design catalog

The catalog is a debug-only and separately buildable review target in each
native app, and a static page for Web.

- It renders the **same production pages and components**. It replaces data
  providers and action executors with scenario drivers. It never reimplements
  pages or business queues.
- Scenarios state the expected state and the result of each action. A screenshot
  that renders is not proof that it means the right thing.
- Scenarios include continuity flows: submit, leave, change in the background,
  return and recover.
- The catalog runs in Release configuration so motion and old-device performance
  can be judged.
- Existing native interaction workbenches (grid, media) remain for complex
  gesture research.

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

## Migration

1. Adopt this document.
2. Generate primaries, roles, semantic text styles, spacing and motion for Apple,
   Android and Web from `tokens.json`, and add the enforcement check.
3. Let the catalog supply scenario data beneath the live models: replace the
   core, credential and system providers, and keep the production models and
   pages. Done for the iPhone and Mac senders (`apps/apple/Catalog`) and the
   Pixel receiver (`apps/android/app/src/catalog`).
4. Build the design catalog to its completion gate and review it on devices.
5. Retire the HTML prototypes. Move live contracts out of the prototype folders
   first, then update references and tests.
6. Set the visual language (`visual-language.md`): icons, marks, cards,
   density, color details, illustration and motion, decided by the owner from
   native specimens, then applied to every redesigned page. Approvals before
   this step are structure approvals (structure, flow, copy) only.
7. Migrate production pages to the catalog compositions. Only pages that are
   structure-approved, carry the approved visual language and have no open
   remnants are migrated.
8. Build new flows (first run, Pro, memories) through the same process.

## Open decisions

- **D1.** Free promise and Pro scope.
- **D2.** Rounded numerals on Apple status cards, after the trial.
- **D3.** Whether Devices keeps its own position on each role, after the catalog
  scenarios.
- **D4.** Animation format, after the first animations are defined.
