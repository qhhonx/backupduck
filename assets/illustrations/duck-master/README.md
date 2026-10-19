# BackupDuck character master

Status: master v3 for review. Nothing in this folder is used by the apps yet.

`duck-master.svg` is the reference geometry for every duck illustration. It is
traced from `assets/AppIcon.png`, not redrawn, and follows the brand-character
section of `design/constitution.md`.

| File | Purpose |
| --- | --- |
| `duck-master.svg` | Layered, rigged master |
| `geometry.json` | Measured circles, pivots, zones, segment counts and input hashes |
| `review-sheet.png` | Icon, master, region difference, poses, layers and measurements |
| `tools/trace_master.py` | Regenerates the master from the icon and tokens |
| `tools/pose.py` | Writes a posed copy using only the rig variations |
| `tools/render.py` | Renders SVGs with the fixed renderer |
| `tools/measure.py` | Compares a render with a reference image |
| `tools/check_pose.py` | Checks a posed SVG against the master, part by part |

## Inputs

| Input | Pinned as |
| --- | --- |
| `assets/AppIcon.png` | SHA-256 in `geometry.json` → `inputs.icon_sha256` |
| `design/backupduck-v1/tokens.json` | Commit `d65dfb4` (branch `claude/amazing-lichterman-d72308`, not yet merged); SHA-256 in `inputs.tokens_sha256` |

Colors come from the tokens:

| Use | Token | Value |
| --- | --- | --- |
| Body and head | `brand.primaries.duckYellow` | `#FEC613` |
| Wing | `brand.primaries.wingBlue` | `#1065E4` |
| Beak | `brand.primaries.beakOrange` | `#FA7212` |
| Eye and drawn lines | `illustration.ink` | `#102346` |
| Eye highlight | `illustration.paper` | `#FEFBF3` |

The icon's faint mottled texture is simplified to flat fills. The highlight uses
the paper color, a chosen flat value close to the icon's off-white highlight.

## Layers and rig

```
duck              tilt pivot (512, 855), bottom centre of the silhouette
├─ body           body, including a hidden neck under the head
├─ wing           two-crest wave; root at (203.8, 642.5), its leftmost point
└─ head
   ├─ head-shape  head outline, including the chin notch
   └─ face        face pivot (608.37, 346.10), the head-circle centre
      ├─ beak
      └─ eye
         ├─ eye-ball
         └─ eye-highlight
```

Each group's `data-pivot` attribute holds its rotation centre. Paint order is
the order above: body, wing, head shape, beak, eye.

Two parts continue where they are hidden, so moving the part on top reveals a
smooth edge instead of a gap:

- **Under the beak** (head-circle angles −11° to 38°), the head edge is a
  monotone cubic bridge between the visible head edge above the beak and the
  chin notch below it, matching radius and slope at both ends.
- **Under the head**, the body continues as a neck (an ellipse centred at
  602.4, 473.1 with radii 125 × 75), rounded where it is hidden.

The chin notch is negative space between the head and the chest. Turning the
whole head would have to redraw that join, so the rig turns the face only.
Larger head movements are redrawn poses.

## Measured geometry

| Feature | Value |
| --- | --- |
| Head circle | Centre (608.37, 346.10), radius 180.55, edge fit RMS 0.68 px |
| Eye | Centre (673.16, 325.79), radius 35.47 |
| Highlight | Centre (684.51, 312.14), radius 9.90 |
| Segments | Body 35, head 24, wing 18, beak 18 cubic curves, fitted to 0.3 px |

Rendered at 1024 px with `tools/render.py` and compared with the icon by
`tools/measure.py`:

| Region | IoU | Edge p99 | Edge max |
| --- | --- | --- | --- |
| Yellow | 0.9972 | 1.0 px | 3.0 px |
| Blue | 0.9987 | 1.0 px | 1.0 px |
| Orange | 0.9968 | 1.0 px | 1.0 px |
| Eye ink | 0.9863 | 1.0 px | 1.0 px |

Eye centre offset 0.0 px, diameter −0.26 px. Keypoints: beak tip 1.0 px, tail
tip 0.0 px, back-to-head corner 1.41 px. The 3 px yellow maximum is three
pixels where the beak's lower edge meets the chin notch; the head under the
beak extends 1 px past the beak there so no seam opens when the face turns.

## Protected outlines and redraw zone

- **Protected**: the visible outline of the head (except the neck join), the
  chin notch, the tail, the lower body, the beak, the eye and the wing. A redrawn
  pose moves these only as rigid parts.
- **Redraw zone**: the neck join, inside the hidden neck ellipse above. A
  redrawn pose may reshape this zone to connect a moved head to the body.

"Fixed" positions are fixed in the part's own group: the eye stays put on the
head, the beak on the face, and so on, while the groups move as the rig allows.

## Variations

| Variation | How | Limit |
| --- | --- | --- |
| Face angle | Rotate `face` around its pivot | −6° to +6° |
| Tilt | Rotate `duck` around its pivot | −6° to +6° |
| Closed eye | Replace `eye` with `eye-arc`, a downward arc | Spans 1.8 × eye radius, centred on the eye, starts 0.1 × radius below the eye centre, sags 0.45 × radius |
| Happy eye | Replace `eye` with `eye-arc`, an upward arc | Same span, starts 0.35 × radius below the eye centre, rises 0.45 × radius |
| Accessories | Extra layers | Never cover the eye |

Arcs use a 14 px round stroke in eye ink. They replace the eye-ball and
highlight; the eye's radius rule applies to open eyes only.

Accessories:

- A **held** prop sits between `body` and `wing`, so the wing overlaps its lower
  edge as if the prop is tucked under the wing.
- A **worn** prop (a crown) sits above `head`, inside the `head` group so it
  follows the head.
- A **standalone** prop (a phone beside the duck, water lines) sits outside the
  `duck` group.

`tools/pose.py` applies the first four and refuses angles outside the limits.
Face angle and tilt can be combined.

## Redrawn poses

Anything beyond the table is a redrawn pose, reviewed on its own: a lowered or
raised head, a raised waving wing, or looking at a prop.

- Move protected parts rigidly; reshape only the redraw zone.
- A raised wing is a new shape attached at the wing root (203.8, 642.5). Its
  outer edge keeps the two crests of the wave. List replaced parts in the root
  element's `data-redrawn` attribute, for example `data-redrawn="wing"`.
- The first approved redrawn pose becomes the example for later ones.

## Not allowed

- Changing proportions, stretching parts, or adding arms or legs.
- Mirroring: the duck faces right, as on the icon.
- Text, logos or interface frames inside an illustration.
- Recoloring parts, or using beak orange for interface states.

## Acceptance

1. **Master against the icon**: render both with `tools/render.py`, then run
   `tools/measure.py`. Pass when IoU is at least 0.99 for yellow, blue and orange
   and 0.98 for eye ink; edge p99 is at most 1.5 px and edge maximum at most 3 px;
   the eye centre is within 1 px and its diameter within ±1 px; keypoints are
   within 2 px; and `status` is `ok`.
2. **Any pose against the master**: run `tools/check_pose.py`. Each part must
   carry only rigid transforms, and either keep its geometry or, rendered alone
   with its transform undone, reach IoU 0.99, edge p99 1.5 px and edge maximum
   3 px. Expression arcs are checked against the variation table within 1 px.
   Parts listed in `data-redrawn` are reported rather than failed.
3. **Exposed joins**: look at the extreme rig angles (face −6° and +6°, tilt
   −6° and +6°) for gaps, hairlines or steps. Static measurements cannot see
   these.
4. A person approves every pose. Model reviews may assist but do not replace it.

## Delivery

- Sources are SVG with transparent backgrounds. The paper color is a preview
  backdrop only.
- Keep at least 64 px of empty margin on the 1024 px canvas.
- Check every pose at 64 pt: the eye, beak and wing must stay distinct.
- Exports are generated per platform: PDF or SVG in the Apple asset catalog,
  VectorDrawable on Android, SVG on Web.

## Reproducing

The tools need Python 3 with NumPy, SciPy and Pillow, and Google Chrome for
rendering (`CHROME` overrides its path). `tools/render.py` records the Chrome
version in `renderer.txt`; v3 was measured with Chrome 155.0.8059.84, headless,
device scale 1, sRGB, on the paper backdrop.

```bash
python3 assets/illustrations/duck-master/tools/trace_master.py assets/AppIcon.png design/backupduck-v1/tokens.json assets/illustrations/duck-master/duck-master.svg assets/illustrations/duck-master/geometry.json
```

```bash
python3 assets/illustrations/duck-master/tools/render.py renders assets/illustrations/duck-master/duck-master.svg
```

```bash
python3 assets/illustrations/duck-master/tools/measure.py assets/AppIcon.png renders/duck-master.png renders/region-diff.png
```

```bash
python3 assets/illustrations/duck-master/tools/pose.py assets/illustrations/duck-master/duck-master.svg renders/pose.svg --face 6 --tilt -6 --eye happy
```

```bash
python3 assets/illustrations/duck-master/tools/check_pose.py assets/illustrations/duck-master/duck-master.svg renders/pose.svg renders/check
```

Tracing is deterministic: the same icon and tokens produce a byte-identical SVG.
Until the token change is merged, pass the `tokens.json` from commit `d65dfb4`.
