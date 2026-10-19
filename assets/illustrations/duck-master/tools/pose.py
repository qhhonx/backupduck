"""Write a posed copy of the duck master using only the allowed rig variations.

Usage: pose.py MASTER.svg OUT.svg [--face DEG] [--tilt DEG] [--eye open|closed|happy]

--face  turns the face (beak and eye) around the head centre, -6 to +6 degrees.
--tilt  tilts the whole duck around its bottom centre, -6 to +6 degrees.
--eye   replaces the eye with a closed (downward) or happy (upward) arc.
Accessories and redrawn poses are separate layers added on top of this output.
"""
import argparse
import re

parser = argparse.ArgumentParser()
parser.add_argument('master'); parser.add_argument('out')
parser.add_argument('--face', type=float, default=0); parser.add_argument('--tilt', type=float, default=0)
parser.add_argument('--eye', choices=['open', 'closed', 'happy'], default='open')
args = parser.parse_args()
for name, value in (('face', args.face), ('tilt', args.tilt)):
    if not -6 <= value <= 6:
        raise SystemExit(f'--{name} {value} is outside the allowed -6..6 degrees; redraw the pose instead')

svg = open(args.master).read()


def rotate(svg, group, deg):
    m = re.search(rf'<g id="{group}" data-pivot="([\d.]+) ([\d.]+)"', svg)
    x, y = m.group(1), m.group(2)
    return svg.replace(m.group(0), f'{m.group(0)} transform="rotate({deg:g} {x} {y})"', 1)


if args.face:
    svg = rotate(svg, 'face', args.face)
if args.tilt:
    svg = rotate(svg, 'duck', args.tilt)
if args.eye != 'open':
    ball = re.search(r'<circle id="eye-ball" cx="([\d.]+)" cy="([\d.]+)" r="([\d.]+)" fill="([^"]+)"/>', svg)
    cx, cy, r, ink = float(ball.group(1)), float(ball.group(2)), float(ball.group(3)), ball.group(4)
    # arc spans 1.8 r, sags or rises 0.45 r from the eye centre line, 14 px round stroke in eye ink
    sag = 0.45 * r if args.eye == 'closed' else -0.45 * r
    base = cy + 0.1 * r if args.eye == 'closed' else cy + 0.35 * r
    arc = (f'<path id="eye-arc" d="M{cx - 0.9 * r:.1f} {base:.1f} Q{cx:.1f} {base + 2 * sag:.1f} {cx + 0.9 * r:.1f} {base:.1f}" '
           f'fill="none" stroke="{ink}" stroke-width="14" stroke-linecap="round"/>')
    svg = re.sub(r'<g id="eye">.*?</g>', f'<g id="eye">{arc}</g>', svg, count=1, flags=re.S)
open(args.out, 'w').write(svg)
