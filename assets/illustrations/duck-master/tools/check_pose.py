"""Check a posed duck against the master, part by part.

Usage: check_pose.py MASTER.svg POSE.svg WORK_DIR

For every master part (body, wing, head-shape, beak, eye-ball, eye-highlight):

1. The part's ancestors in the pose may only carry rigid transforms (rotate,
   translate, or a matrix with no scale or skew).
2. If the part's geometry and fill are unchanged, it passes as rigid.
3. Otherwise the part is rendered alone in both files, with the pose's ancestor
   transform undone, and must reach IoU 0.99 with edge p99 at most 1.5 px and edge
   maximum at most 3 px against the master part. Parts that
   a redrawn pose replaces on purpose should be listed in the pose's root
   `data-redrawn` attribute (space separated ids); they are reported, not failed.
4. A replaced eye (an `eye-arc` path) is checked against the README's arc rules
   instead of the eye-ball and highlight.

Prints JSON and exits with status 1 when any check fails.
"""
import json
import math
import pathlib
import re
import sys
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from render import render  # noqa: E402

SVG_NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', SVG_NS)
PARTS = ['body', 'wing', 'head-shape', 'beak', 'eye-ball', 'eye-highlight']
GEOMETRY_ATTRS = ['d', 'cx', 'cy', 'r', 'fill']
IOU_MIN = 0.99
EDGE_P99_MAX = 1.5
EDGE_MAX = 3.0
ARC_TOLERANCE_PX = 1.0

master_path, pose_path, work = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
work.mkdir(parents=True, exist_ok=True)


def tag(el):
    return el.tag.split('}')[-1]


def parse_transform(text):
    m = np.eye(3)
    for name, args in re.findall(r'(\w+)\s*\(([^)]*)\)', text or ''):
        v = [float(x) for x in re.split(r'[\s,]+', args.strip()) if x]
        if name == 'rotate':
            a = math.radians(v[0]); cx, cy = (v[1], v[2]) if len(v) == 3 else (0, 0)
            c, s = math.cos(a), math.sin(a)
            t = np.array([[c, -s, cx - c * cx + s * cy], [s, c, cy - s * cx - c * cy], [0, 0, 1]])
        elif name == 'translate':
            t = np.array([[1, 0, v[0]], [0, 1, v[1] if len(v) > 1 else 0], [0, 0, 1]])
        elif name == 'scale':
            sx = v[0]; sy = v[1] if len(v) > 1 else sx
            t = np.diag([sx, sy, 1.0])
        elif name == 'matrix':
            t = np.array([[v[0], v[2], v[4]], [v[1], v[3], v[5]], [0, 0, 1]])
        else:
            raise SystemExit(f'unsupported transform {name}')
        m = m @ t
    return m


def index(root):
    """Map id -> (element, cumulative ancestor transform)."""
    out = {}

    def walk(el, m):
        m = m @ parse_transform(el.get('transform'))
        if el.get('id'):
            out[el.get('id')] = (el, m)
        for child in el:
            walk(child, m)
    walk(root, np.eye(3))
    return out


def rigid(m):
    a = m[:2, :2]
    return bool(np.allclose(a @ a.T, np.eye(2), atol=1e-6) and np.linalg.det(a) > 0)


def isolate(el, m_inverse, name):
    """An SVG holding only `el` filled black, with `m_inverse` applied, at master size."""
    svg = ET.Element(f'{{{SVG_NS}}}svg', {'viewBox': '0 0 1024 1024', 'width': '1024', 'height': '1024'})
    g = ET.SubElement(svg, f'{{{SVG_NS}}}g', {'transform': 'matrix({} {} {} {} {} {})'.format(
        m_inverse[0, 0], m_inverse[1, 0], m_inverse[0, 1], m_inverse[1, 1], m_inverse[0, 2], m_inverse[1, 2])})
    copy = ET.SubElement(g, el.tag, {k: v for k, v in el.attrib.items() if k != 'transform'})
    own = parse_transform(el.get('transform'))
    if not np.allclose(own, np.eye(3)):
        copy.set('transform', el.get('transform'))
    copy.set('fill', '#000000')
    path = work / f'{name}.svg'
    ET.ElementTree(svg).write(path)
    return path


def mask(png):
    a = np.asarray(Image.open(png).convert('L'), dtype=float)
    return a < 128


master_root = ET.parse(master_path).getroot()
pose_root = ET.parse(pose_path).getroot()
mi, pi = index(master_root), index(pose_root)
redrawn = set((pose_root.get('data-redrawn') or '').split())
report = {'parts': {}, 'passed': True}


def fail(part, why, **extra):
    report['parts'][part] = {'status': 'fail', 'reason': why, **extra}
    report['passed'] = False


to_render = []
for part in PARTS:
    mel, mm = mi[part]
    if part not in pi:
        if part.startswith('eye') and 'eye-arc' in pi:
            report['parts'][part] = {'status': 'replaced by expression'}
        elif part in redrawn:
            report['parts'][part] = {'status': 'redrawn (listed)'}
        else:
            fail(part, 'missing')
        continue
    pel, pm = pi[part]
    if not rigid(pm):
        fail(part, 'ancestor transform scales or skews')
        continue
    same = all(mel.get(a) == pel.get(a) for a in GEOMETRY_ATTRS) and tag(mel) == tag(pel)
    if same:
        report['parts'][part] = {'status': 'pass', 'check': 'geometry unchanged, rigid transform'}
        continue
    to_render.append((part, mel, mm, pel, pm))

if to_render:
    files = []
    for part, mel, mm, pel, pm in to_render:
        files += [isolate(mel, np.linalg.inv(mm), f'master-{part}'), isolate(pel, np.linalg.inv(pm), f'pose-{part}')]
    render(work, files)
    for part, *_ in to_render:
        a, b = mask(work / f'master-{part}.png'), mask(work / f'pose-{part}.png')
        iou = float((a & b).sum() / max((a | b).sum(), 1))
        ea, eb = a & ~ndimage.binary_erosion(a), b & ~ndimage.binary_erosion(b)
        dist = np.concatenate([ndimage.distance_transform_edt(~eb)[ea], ndimage.distance_transform_edt(~ea)[eb]])
        stats = {'iou': round(iou, 4), 'edge_p99_px': round(float(np.percentile(dist, 99)), 2), 'edge_max_px': round(float(dist.max()), 2)}
        ok = iou >= IOU_MIN and stats['edge_p99_px'] <= EDGE_P99_MAX and stats['edge_max_px'] <= EDGE_MAX
        if ok:
            report['parts'][part] = {'status': 'pass', 'check': 'rendered after undoing transform', **stats}
        elif part in redrawn:
            report['parts'][part] = {'status': 'redrawn (listed)', **stats}
        else:
            fail(part, 'geometry changed', **stats)

if 'eye-arc' in pi:
    arc, am = pi['eye-arc']
    ball = mi['eye-ball'][0]
    cx, cy, r = (float(ball.get(k)) for k in ('cx', 'cy', 'r'))
    nums = [float(x) for x in re.findall(r'-?\d+\.?\d*', arc.get('d'))]
    (x0, y0, qx, qy, x1, y1) = nums[:6]
    # path coordinates are local to the eye's group, which is the master's frame; transforms only move it rigidly
    p0, q, p1 = (np.array([x, y, 1.0]) for x, y in ((x0, y0), (qx, qy), (x1, y1)))
    if not rigid(am):
        fail('eye-arc', 'ancestor transform scales or skews')
    span = math.dist(p0[:2], p1[:2]); mid_y = (p0[1] + p1[1]) / 2
    sag = (p0[1] + 2 * q[1] + p1[1]) / 4 - mid_y
    closed = sag > 0
    expected_base = cy + (0.1 if closed else 0.35) * r
    checks = {
        'span': (span, 1.8 * r), 'base_y': (mid_y, expected_base), 'sag': (abs(sag), 0.45 * r),
        'centre_x': ((p0[0] + p1[0]) / 2, cx),
    }
    bad = {k: (round(v, 2), round(e, 2)) for k, (v, e) in checks.items() if abs(v - e) > ARC_TOLERANCE_PX}
    style_ok = arc.get('stroke-width') == '14' and arc.get('stroke-linecap') == 'round' and arc.get('stroke') == ball.get('fill')
    entry = {'kind': 'closed' if closed else 'happy', 'measured_vs_expected': {k: (round(v, 2), round(e, 2)) for k, (v, e) in checks.items()}}
    if bad or not style_ok:
        fail('eye-arc', 'arc outside the README rules', out_of_tolerance=bad, style_ok=style_ok, **entry)
    else:
        report['parts']['eye-arc'] = {'status': 'pass', **entry}

print(json.dumps(report, indent=1))
sys.exit(0 if report['passed'] else 1)
