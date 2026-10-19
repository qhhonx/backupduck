"""Build the BackupDuck pose set from the vector master plus simple props.

Usage: build_poses.py MASTER.svg OUT_DIR

Every pose places the master duck with the same scale and position, so the duck
is identical in size across the set. Props are drawn in canvas coordinates
around it, or inside the duck's groups when they move with a part.
"""
import math
import pathlib
import re
import sys

master_path, out_dir = sys.argv[1], pathlib.Path(sys.argv[2])
out_dir.mkdir(parents=True, exist_ok=True)
MASTER = open(master_path).read()

INK, BLUE, YELLOW, ORANGE, PAPER = '#102346', '#1065E4', '#FEC613', '#FA7212', '#FEFBF3'
SKY, LEAF, WATER = '#9CC4E4', '#4C7D4A', '#9CC4E4'
PLACE = 'translate(70.25 147.2) scale(0.78)'  # same for every pose
EYE = re.search(r'<circle id="eye-ball" cx="([\d.]+)" cy="([\d.]+)" r="([\d.]+)"', MASTER)
EX, EY, ER = (float(v) for v in EYE.groups())


def duck_body(svg):
    """The master's <g id="duck">…</g> block."""
    start = svg.index('<g id="duck"'); end = svg.rindex('</svg>')
    return svg[start:end].rstrip()


def eye_arc(kind):
    sag = 0.45 * ER if kind == 'closed' else -0.45 * ER
    base = EY + (0.1 if kind == 'closed' else 0.35) * ER
    return (f'<path id="eye-arc" d="M{EX - 0.9 * ER:.1f} {base:.1f} Q{EX:.1f} {base + 2 * sag:.1f} {EX + 0.9 * ER:.1f} {base:.1f}" '
            f'fill="none" stroke="{INK}" stroke-width="14" stroke-linecap="round"/>')


def pose(eye=None, face=0, tilt=0, head=0, before_wing='', on_head='', before_head=''):
    svg = MASTER
    if eye:
        svg = re.sub(r'<g id="eye">.*?</g>\s*</g>', f'<g id="eye">{eye_arc(eye)}</g>\n        </g>', svg, count=1, flags=re.S)
    if face:
        svg = re.sub(r'(<g id="face" data-pivot="([\d.]+) ([\d.]+)")', lambda m: f'{m.group(1)} transform="rotate({face} {m.group(2)} {m.group(3)})"', svg, count=1)
    if tilt:
        svg = re.sub(r'(<g id="duck" data-pivot="([\d.]+) ([\d.]+)")', lambda m: f'{m.group(1)} transform="rotate({tilt} {m.group(2)} {m.group(3)})"', svg, count=1)
    if head:  # redrawn pose: the whole head turns around the neck; a plain head circle keeps the turned edge smooth
        svg = svg.replace('<g id="head">', f'<g id="head" transform="rotate({head} 602 473)">', 1)
        svg = re.sub(r'<path id="head-shape" d="[^"]*" fill="([^"]+)"/>',
                     lambda m: f'<circle id="head-shape" cx="608.37" cy="346.1" r="180.55" fill="{m.group(1)}"/>', svg, count=1)
    if before_wing:
        svg = svg.replace('<path id="wing"', before_wing + '\n    <path id="wing"', 1)
    if on_head:
        svg = svg.replace('<g id="face"', on_head + '\n      <g id="face"', 1)
    if before_head:
        svg = svg.replace('<g id="head"', before_head + '\n    <g id="head"', 1)
    return duck_body(svg)


def page(name, duck, props='', redrawn='', right=760, left=179):
    """Centre the composition horizontally between its leftmost and rightmost x."""
    attr = f' data-redrawn="{redrawn}"' if redrawn else ''
    dx = 512 - (left + right) / 2
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024"{attr}>\n'
           f'<g id="composition" transform="translate({dx:.1f} 0)">\n'
           f'  <g id="placement" transform="{PLACE}">\n  {duck}\n  </g>\n{props}</g>\n</svg>\n')
    (out_dir / f'{name}.svg').write_text(svg)


def stroke(d, color=BLUE, width=12):
    return f'  <path d="{d}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"/>\n'


def sparkle(cx, cy, r, color=BLUE):
    k = r * 0.22
    return (f'  <path d="M{cx} {cy - r} Q{cx + k} {cy - k} {cx + r} {cy} Q{cx + k} {cy + k} {cx} {cy + r} '
            f'Q{cx - k} {cy + k} {cx - r} {cy} Q{cx - k} {cy - k} {cx} {cy - r}Z" fill="{color}"/>\n')


# 02 pairing: a phone beside the duck, two signal arcs above it; the face turns slightly toward it
phone = (f'  <rect x="806" y="470" width="104" height="190" rx="22" fill="{INK}"/>\n'
         f'  <rect x="818" y="490" width="80" height="140" rx="10" fill="{SKY}"/>\n'
         f'  <rect x="846" y="640" width="24" height="8" rx="4" fill="{SKY}"/>\n'
         + stroke('M828 432 A40 40 0 0 1 888 432') + stroke('M806 404 A64 64 0 0 1 910 404'))
page('02-pairing', pose(face=3), phone, right=910)

# 03 empty: calm water lines under the duck
water = (stroke('M150 846 Q185 832 220 846 T290 846', WATER, 12) + stroke('M330 878 Q390 862 450 878 T570 878 T690 878', WATER, 12)
         + stroke('M720 846 Q755 832 790 846 T860 846', WATER, 12))
page('03-empty', pose(), water, right=860)

# 04 done: happy eye, a photo tucked between body and wing
photo = (f'<g id="photo" transform="rotate(-12 720 600)">'
         f'<rect x="606" y="508" width="230" height="180" rx="22" fill="{PAPER}"/>'
         f'<rect x="626" y="528" width="190" height="118" rx="10" fill="{SKY}"/>'
         f'<path d="M626 646 L626 606 Q676 560 726 600 Q766 578 816 612 L816 646 Z" fill="{LEAF}"/>'
         f'<circle cx="776" cy="562" r="16" fill="{YELLOW}"/></g>')
page('04-done', pose(eye='happy', before_wing=photo))

# 05 waiting: the head lowered 20 degrees, closed eye, two small z marks
zs = stroke('M748 312 L778 312 L748 342 L778 342', BLUE, 11) + stroke('M800 250 L838 250 L800 288 L838 288', BLUE, 13)
def neck_fillet(turn, top_y, start_x=410):
    """A smooth join from the back line up to the turned head circle, tangent to both."""
    t = math.radians(turn); px, py = 602, 473; hx, hy, hr = 608.37, 346.1, 180.55
    cx = px + (hx - px) * math.cos(t) - (hy - py) * math.sin(t); cy = py + (hx - px) * math.sin(t) + (hy - py) * math.cos(t)
    back = 470.5
    bx = cx - math.sqrt(hr * hr - (top_y - cy) ** 2)            # point on the head circle's left side
    tx, ty = (top_y - cy), -(bx - cx); n = math.hypot(tx, ty); tx, ty = tx / n, ty / n  # tangent, pointing down
    if ty < 0:
        tx, ty = -tx, -ty
    s = (back - top_y) / ty; kx = bx + s * tx                   # control point on the back line
    return (f'<path id="neck" d="M{start_x} {back} Q{kx:.1f} {back} {bx:.1f} {top_y} L{cx:.1f} {cy:.1f} L{start_x} {back + 60} Z" '
            f'fill="{YELLOW}"/>')


page('05-waiting', pose(eye='closed', head=20, before_head=neck_fillet(20, 412)), zs, redrawn='head neck', right=838)

# 06 Pro: a crown sitting on top of the head, upright
crown = (f'<path id="crown" d="M530 196 L518 120 L566 156 L606 96 L646 156 L694 120 L682 196 Z" '
         f'fill="{YELLOW}" stroke="{ORANGE}" stroke-width="12" stroke-linejoin="round"/>')
page('06-premium', pose(on_head=crown))

# 01 welcome: happy eye, face tilted up, two sparkles
page('01-welcome', pose(eye='happy', face=-6, tilt=-3), sparkle(812, 300, 30) + sparkle(866, 372, 18), right=884)
