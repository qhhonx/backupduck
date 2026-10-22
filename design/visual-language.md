# Visual standard

Status: approved direction (owner, October 19, 2026); details are adjusted in
native review. Migration step 6 of `constitution.md`. The interaction standard
is `interaction.md`; together they replace every earlier "look" proposal.

Values live in `backupduck-v1/tokens.json` and reach each platform through the
export script. Shared components (`apps/apple/Shared/DuckLook.swift`,
`apps/android/.../DuckLook.kt`) draw them. A page uses components and semantic
styles; it never defines a color, size or radius of its own. Each item below
has an identifier (V1–V7) that reviews and code comments cite.

## Character

A quiet utility the user trusts, with a few crafted moments. Calm screens show
the user's own photos as evidence that they are safe; working screens are
compact; problems are plain and actionable. The brand appears in the accent,
the duck and the step marks, never as a tinted canvas.

## V1 Color

| Role | Meaning | Apple | Pixel |
| --- | --- | --- | --- |
| `background`, `groupedSurface`, `elevatedSurface` | Page, card, sheet | System grouped colors | Material 3 surface roles from the fixed scheme |
| `primaryText`, `secondaryText`, `separator` | Text and rules | System label colors | Material on-surface roles |
| `accent` | Interactive or in progress | Tint derived from wing blue | Primary of the scheme seeded by wing blue |
| `saved` | In the Pixel's Photos | Green, always with a check glyph | Same |
| `attention` | Needs the user | Amber, always with a glyph | Same |
| `failure` | Failed and blocked | Red, only for failures | Same |

- Titles and body text are never colored. State color lives in one small glyph
  or dot next to neutral text.
- Received and saved use different glyphs (clock and check), not two shades.
- Duck yellow appears only in brand moments: the first-run step mark, the
  discovery dot and illustrations. Beak orange is illustration only.
- No tint over photos, no text laid over photos except media marks and the
  library title on its scrim.
- Dark mode, increased contrast and reduced transparency come from the system
  roles; nothing is redrawn per mode.

## V2 Type

Semantic styles only, mapped to Dynamic Type on Apple and the Material type
scale on Android.

| Use | iPhone | Mac | Pixel |
| --- | --- | --- | --- |
| Page title | Large title, bold | Title 1 (22), bold | Headline medium (28) |
| Guided-flow and sheet title | Title 2, bold | Title 2 | Headline small |
| Card title, row title | Headline | Body, semibold | Title medium |
| Body, rows | Body | Body (13) | Body large |
| Supporting text | Subheadline, secondary | Callout, secondary | Body medium, on-surface variant |
| Section header, footer | Footnote, secondary | Caption, secondary | Label large in the accent (section header) |
| Media marks | Caption, semibold, white with shadow | Same | Same |

Counts on the hub status card may use rounded numerals (D2 trial); nowhere
else.

## V3 Space and shape

| Token | iPhone | Mac | Pixel |
| --- | --- | --- | --- |
| Grid | 4 pt | 4 pt | 4 dp |
| Page margin | 16 | 24 | 16 |
| Card padding | 16 | 12 | 16 |
| Section gap | 24 | 16 | 24 |
| Card radius (`radius.card`, Mac `radius.cardCompact`) | 20 | 12 | 20 |
| Sheet radius | System | System | 28 |
| Primary and secondary buttons | System button styles (capsule) | System push buttons | Material buttons (full radius) |

Spacing values come from the `spacing` scale (4, 8, 12, 16, 24, 32, 48).
Components own their padding and alignment; pages own section spacing. Photo
grids use 2 pt gaps and no radius; photos inside a card take the card radius.

## V4 Material and elevation

- Apple: system materials only for chrome that floats over content (tab bar,
  toolbars, viewer controls, menus). Cards, rows and progress are solid.
- Pixel: solid surfaces only; elevation is tonal. No blur, for older devices.
- Cards have no border and no shadow. Only floating menus and sheets cast one.
- Reduced transparency replaces materials with solid surfaces.

## V5 Icons and media marks

- SF Symbols and Material Symbols at the text weight, monochrome.
- Colored icon tiles appear only in Apple settings rows, with one stable color
  per row; they help users find a row and never carry state. Pixel settings use
  monochrome leading icons.
- Media marks are white glyphs or text with a soft shadow, in a fixed corner,
  with no pill: sending (arrow up), received and saving (clock), needs you
  (filled triangle), video duration, Live Photo. A photo in the Pixel's Photos
  carries no mark. "Not backed up" is a view, not a mark.

## V6 Illustration

- The duck appears in story moments only: welcome, connecting and connected,
  empty states, the first photo and milestones. At most one per screen.
- Problems, warnings, permissions and working screens never show the duck
  (owner default, October 19; this replaces the earlier "duck accompanies
  problems"). Calm hubs show photos, not the duck.
- The three step marks (yellow circle, blue wing, orange sparkle) carry no
  numerals; their shapes and order tell the steps apart. The welcome screen
  lists all three at full strength beside their sentences. Every later
  first-run step shows the same row of three at the top, the current mark at
  full strength and the others faint (about 25 % opacity). Assistive
  technology reads "Step 2 of 3".
- Animations play once, stop when the page is left, show a still frame under
  Reduce Motion, and are hidden from assistive technology.

## V7 Density

| Row | Height |
| --- | --- |
| iPhone preference row | 52 pt, growing with text |
| iPhone compact row | 44 pt |
| Mac preference and settings row | 41 pt, 24 pt icon tiles, 290 pt list column |
| Pixel one-line and two-line row | 56 and 72 dp |

Calm screens fill with content (photos, the next useful thing) rather than
white space; working screens fit on one screen where they can.

## Decisions

- **October 19, 2026:** photos lead calm states; one card style with neutral
  titles and one colored glyph; one primary capsule per screen with tinted
  capsules inside cards and soft status pills; media marks as white glyphs with
  a soft shadow.
- **October 19, 2026 (canvas review):** the owner approved the overall visual
  and interaction direction from a design canvas that showed the standards and
  every flow on three platforms. Details are adjusted in native review. Defaults
  taken for the open points: no duck on problem states; Mac settings rows at
  41 pt; rounded numerals on hub counts only, as a trial.
- **October 21, 2026:** buttons and every piece of chrome come from the system
  (`platform-expression.md` A0, A1). The capsule look stays, drawn by the
  system button styles rather than by BackupDuck.
