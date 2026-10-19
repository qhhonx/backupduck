"""Trace the layered BackupDuck character master from AppIcon.png.

Usage: trace_master.py ICON.png TOKENS.json OUT.svg [GEOMETRY.json]

TOKENS.json is design/backupduck-v1/tokens.json; brand and illustration colors come from it.

Each layer is traced from a coverage field: for every pixel, the fraction of the
layer's color in an anti-aliased mix with its neighbour color. Outlines are
taken at 50 % coverage with sub-pixel accuracy, split at corners and fitted with
cubic Bézier curves to a 0.3 px tolerance.
"""
import json
import math
import sys

import hashlib

import numpy as np
from PIL import Image
from scipy import ndimage

ICON, TOKENS, OUT = sys.argv[1:4]
GEOMETRY = sys.argv[4] if len(sys.argv) > 4 else OUT + '.json'

np.seterr(divide='ignore', invalid='ignore', over='ignore')
rgb = np.asarray(Image.open(ICON).convert('RGB'), dtype=float)
H, W, _ = rgb.shape
YY, XX = np.mgrid[0:H, 0:W] + 0.5

# Reference colors of the icon itself, used only to measure coverage.
CREAM = np.array([254, 251, 242.0])
YELLOW = np.array([253, 197, 18.0])
BLUE = np.array([16, 101, 228.0])
ORANGE = np.array([249, 114, 18.0])
NAVY = np.array([16, 36, 71.0])
WHITE = np.array([255, 255, 255.0])


def coverage(target, others):
    """Fraction of `target` in each pixel, mixing with the nearest of `others`."""
    best_alpha = np.zeros((H, W)); best_res = np.full((H, W), np.inf)
    for other in others:
        d = target - other
        alpha = np.clip(((rgb - other) @ d) / (d @ d), 0, 1)
        res = np.linalg.norm(rgb - (other + alpha[..., None] * d), axis=2)
        better = res < best_res
        best_alpha[better] = alpha[better]; best_res[better] = res[better]
    return best_alpha


def box(field, x0, y0, x1, y1):
    out = np.zeros_like(field); out[y0:y1, x0:x1] = field[y0:y1, x0:x1]; return out


def marching_squares(field, level=0.5):
    """Closed contours of `field` at `level`, as lists of (x, y) in pixel-centre coordinates."""
    f = np.pad(field, 1)
    h, w = f.shape
    segs = {}
    def interp(p, q, a, b):
        t = (level - a) / (b - a)
        return (p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1]))
    above = f > level
    mixed = (above[:-1, :-1] != above[:-1, 1:]) | (above[:-1, :-1] != above[1:, 1:]) | (above[:-1, :-1] != above[1:, :-1])
    for y, x in zip(*np.nonzero(mixed)):
        y = int(y); x = int(x)
        if True:
            a, b, c, d = f[y, x], f[y, x + 1], f[y + 1, x + 1], f[y + 1, x]
            idx = (a > level) | (b > level) << 1 | (c > level) << 2 | (d > level) << 3
            if idx in (0, 15):
                continue
            P = [(x, y), (x + 1, y), (x + 1, y + 1), (x, y + 1)]; V = [a, b, c, d]
            e = lambda i, j: (round(interp(P[i], P[j], V[i], V[j])[0], 6), round(interp(P[i], P[j], V[i], V[j])[1], 6))
            top, right, bottom, left = e(0, 1), e(1, 2), e(3, 2), e(0, 3)
            table = {1: [(left, top)], 2: [(top, right)], 3: [(left, right)], 4: [(right, bottom)],
                     5: [(left, top), (right, bottom)], 6: [(top, bottom)], 7: [(left, bottom)],
                     8: [(bottom, left)], 9: [(bottom, top)], 10: [(top, right), (bottom, left)],
                     11: [(bottom, right)], 12: [(right, left)], 13: [(right, top)], 14: [(top, left)]}
            for s, t in table[idx]:
                segs.setdefault(s, []).append(t)
    contours = []
    while segs:
        start = next(iter(segs)); path = [start]; cur = start
        while cur in segs:
            nxt = segs[cur].pop()
            if not segs[cur]:
                del segs[cur]
            path.append(nxt); cur = nxt
            if cur == start:
                break
        contours.append([(px - 1 + 0.5, py - 1 + 0.5) for px, py in path])
    return contours


def outer(field):
    cs = marching_squares(field)
    return max(cs, key=len)


def resample(pts, step=1.5):
    pts = np.array(pts)
    seg = np.linalg.norm(np.diff(np.vstack([pts, pts[:1]]), axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    total = s[-1]
    t = np.arange(0, total, step)
    closed = np.vstack([pts, pts[:1]])
    return np.column_stack([np.interp(t, s, closed[:, 0]), np.interp(t, s, closed[:, 1])])


def corners(pts, window=5, threshold=45):
    n = len(pts); out = []
    for i in range(n):
        a = pts[i] - pts[(i - window) % n]; b = pts[(i + window) % n] - pts[i]
        ang = math.degrees(math.acos(np.clip(a @ b / (np.linalg.norm(a) * np.linalg.norm(b)), -1, 1)))
        out.append(ang)
    out = np.array(out); idx = []
    for i in range(n):
        if out[i] > threshold and out[i] == max(out[(i + k) % n] for k in range(-window, window + 1)):
            idx.append(i)
    return idx


# ---- Schneider's cubic Bézier fitting -------------------------------------------------

def bez(ctrl, t):
    t = np.asarray(t)[:, None]; mt = 1 - t
    return mt ** 3 * ctrl[0] + 3 * mt ** 2 * t * ctrl[1] + 3 * mt * t ** 2 * ctrl[2] + t ** 3 * ctrl[3]


def chord_params(p):
    d = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(p, axis=0), axis=1))])
    return d / d[-1] if d[-1] else d


def generate(p, u, t1, t2):
    A1 = np.outer(3 * (1 - u) ** 2 * u, t1); A2 = np.outer(3 * (1 - u) * u ** 2, t2)
    c00 = (A1 * A1).sum(); c01 = (A1 * A2).sum(); c11 = (A2 * A2).sum()
    tmp = p - bez(np.array([p[0], p[0], p[-1], p[-1]]), u)
    x0 = (A1 * tmp).sum(); x1 = (A2 * tmp).sum()
    det = c00 * c11 - c01 * c01
    seg = np.linalg.norm(p[-1] - p[0])
    if abs(det) > 1e-12:
        a1 = (x0 * c11 - x1 * c01) / det; a2 = (c00 * x1 - c01 * x0) / det
    else:
        a1 = a2 = seg / 3
    if a1 < 1e-6 * seg or a2 < 1e-6 * seg:
        a1 = a2 = seg / 3
    return np.array([p[0], p[0] + t1 * a1, p[-1] + t2 * a2, p[-1]])


def reparam(ctrl, p, u):
    d1 = 3 * (ctrl[1:] - ctrl[:-1]); d2 = 2 * (d1[1:] - d1[:-1])
    out = []
    for pt, t in zip(p, u):
        q = bez(ctrl, [t])[0] - pt
        mt = 1 - t
        q1 = mt ** 2 * d1[0] + 2 * mt * t * d1[1] + t ** 2 * d1[2]
        q2 = mt * d2[0] + t * d2[1]
        den = q1 @ q1 + q @ q2
        out.append(t - (q @ q1) / den if den else t)
    return np.clip(np.array(out), 0, 1)


def fit(p, t1, t2, err):
    if len(p) == 2:
        dist = np.linalg.norm(p[1] - p[0]) / 3
        return [np.array([p[0], p[0] + t1 * dist, p[1] + t2 * dist, p[1]])]
    u = chord_params(p)
    ctrl = generate(p, u, t1, t2)
    for _ in range(6):
        e = np.linalg.norm(bez(ctrl, u) - p, axis=1)
        if e.max() <= err:
            return [ctrl]
        u = reparam(ctrl, p, u)
        ctrl = generate(p, u, t1, t2)
    e = np.linalg.norm(bez(ctrl, u) - p, axis=1)
    if e.max() <= err:
        return [ctrl]
    split = int(np.argmax(e[1:-1])) + 1
    tc = p[split - 1] - p[split + 1]; tc /= np.linalg.norm(tc)
    return fit(p[:split + 1], t1, tc, err) + fit(p[split:], -tc, t2, err)


def unit(v):
    return v / np.linalg.norm(v)


def fit_closed(pts, err=0.3):
    pts = resample(pts)
    # light smoothing removes marching-squares wobble without moving corners much
    sm = (np.roll(pts, 1, 0) + 2 * pts + np.roll(pts, -1, 0)) / 4
    cs = corners(sm)
    n = len(sm)
    if not cs:
        cs = [0]
    curves = []
    for k, start in enumerate(cs):
        end = cs[(k + 1) % len(cs)]
        idx = [(start + i) % n for i in range(((end - start) % n or n) + 1)]
        seg = sm[idx]
        t1 = unit(seg[min(3, len(seg) - 1)] - seg[0]); t2 = unit(seg[max(-4, -len(seg))] - seg[-1])
        if len(cs) == 1:
            # smooth closed curve: matching tangents at the seam
            tc = unit(sm[(start + 1) % n] - sm[(start - 1) % n]); t1 = tc; t2 = -tc
        curves += fit(seg, t1, t2, err)
    return curves


def to_path(curves):
    f = lambda v: f"{v:.2f}".rstrip('0').rstrip('.')
    c0 = curves[0]
    d = f"M{f(c0[0][0])} {f(c0[0][1])}"
    for c in curves:
        d += f"C{f(c[1][0])} {f(c[1][1])} {f(c[2][0])} {f(c[2][1])} {f(c[3][0])} {f(c[3][1])}"
    return d + "Z"


def fit_circle(contour):
    p = np.array(contour)
    A = np.column_stack([2 * p[:, 0], 2 * p[:, 1], np.ones(len(p))])
    b = (p ** 2).sum(1)
    cx, cy, c = np.linalg.lstsq(A, b, rcond=None)[0]
    r = math.sqrt(c + cx * cx + cy * cy)
    rms = float(np.sqrt(((np.hypot(p[:, 0] - cx, p[:, 1] - cy) - r) ** 2).mean()))
    return cx, cy, r, rms


# ---- fields ------------------------------------------------------------------------------
duck_colors = [YELLOW, ORANGE, BLUE, NAVY]
sil = np.max([coverage(c, [CREAM]) for c in duck_colors], axis=0)
sil[(rgb[..., 2] > 150) & (rgb[..., 0] < 120)] = 1  # wing interior
wing = box(coverage(BLUE, [YELLOW]), 150, 470, 860, 850)
beak = box(coverage(ORANGE, [YELLOW, CREAM]), 700, 290, 910, 470)


def main_part(field):
    """Keep the largest connected region: anti-aliased yellow-to-paper edges can read as faint orange."""
    lab, n = ndimage.label(field > 0.5)
    if n <= 1:
        return field
    keep = lab == (1 + int(np.argmax(ndimage.sum(np.ones_like(field), lab, range(1, n + 1)))))
    return field * ndimage.binary_dilation(keep, iterations=2)


beak = main_part(beak)
eye_field = box(np.where(np.hypot(XX - 674, YY - 327) < 30, 1.0, coverage(NAVY, [YELLOW])), 600, 250, 750, 400)

# head circle from the silhouette's head edge (left, top and upper right; the neck and beak excluded)
sil_contour = np.array(outer(sil))
HX0, HY0 = 606.0, 343.0
ang = np.degrees(np.arctan2(sil_contour[:, 1] - HY0, sil_contour[:, 0] - HX0))
rad = np.hypot(sil_contour[:, 0] - HX0, sil_contour[:, 1] - HY0)
head_edge = sil_contour[((ang <= -35) | (ang >= 150)) & (rad > 150) & (rad < 200)]
hx, hy, hr, hrms = fit_circle(head_edge)
head_max = float(np.hypot(head_edge[:, 0] - hx, head_edge[:, 1] - hy).max())

disk_r = head_max + 0.5
disk = np.clip(disk_r - np.hypot(XX - hx, YY - hy), 0, 1)
head_circle = np.clip(hr + 0.5 - np.hypot(XX - hx, YY - hy), 0, 1)
# the head shape stops at the head circle under the beak, so the face can turn without leaving a yellow beak shape behind
head = np.minimum(np.minimum(sil, disk), np.maximum(head_circle, 1 - beak))
NECK = (hx - 6, hy + 127, 125, 75)  # ellipse centre x, y, rx, ry: body continues under the head
neck = (((XX - NECK[0]) / NECK[2]) ** 2 + ((YY - NECK[1]) / NECK[3]) ** 2) < 1
body = np.minimum(sil, np.maximum(1 - disk, neck.astype(float)))


def smooth_under(field, cover, sigma, reach):
    """Round off `field` under `cover` (a layer drawn on top of it), reaching `reach` px past the cover's edge.

    With reach 0 the change stays fully hidden in the rest pose. A small positive reach also rounds the corner
    where a visible edge meets the cover, which a moving cover would otherwise expose as a step.
    """
    mask = cover > 0.5
    if reach > 0:
        mask = ndimage.binary_dilation(mask, iterations=reach)
    else:
        mask = ndimage.binary_erosion(mask, iterations=6)
    weight = np.clip(ndimage.gaussian_filter(mask.astype(float), 1.5) * 1.6 - 0.3, 0, 1)
    return (1 - weight) * field + weight * ndimage.gaussian_filter(field, sigma)




def bridge_under_beak(head_field, beak_field, cx, cy, step=0.25, guard=3.0):
    """Replace the head edge under the beak with a smooth continuation of the visible edge on either side.

    The visible head edge is walked in polar coordinates around the head centre. Where the beak covers it, the
    radius is bridged with a cubic Hermite curve matching radius and slope at both ends, so turning the face
    exposes a head edge that continues the visible one instead of a step or a bump.
    """
    beak_mask = ndimage.binary_dilation(beak_field > 0.5, iterations=1)
    head_out = ndimage.binary_fill_holes((head_field > 0.5) & ~beak_mask)  # the eye highlight is a hole in the trace
    head_full = ndimage.binary_fill_holes(head_field > 0.5)

    def edge(mask, t):
        r = 60.0
        while r < 260 and mask[int(cy + r * math.sin(t)), int(cx + r * math.cos(t))]:
            r += 0.25
        return r

    thetas = np.arange(-80, 80 + step, step)
    radii, covered = [], []
    for th in thetas:
        t = math.radians(th)
        radii.append(edge(head_out, t))
        # covered: the head's own edge at this angle lies under the beak
        rf = edge(head_full, t) - 1
        covered.append(bool(beak_mask[int(cy + rf * math.sin(t)), int(cx + rf * math.cos(t))]))
    radii = np.array(radii); covered = np.array(covered)
    idx = np.nonzero(covered)[0]
    i1, i2 = idx.min(), idx.max()
    g = int(guard / step)
    a, b = i1 - g, i2 + g  # bridge ends just outside the covered sector
    span = thetas[b] - thetas[a]
    k = int(3 / step)
    s1 = (radii[a] - radii[a - k]) / (thetas[a] - thetas[a - k]) * span
    s2 = (radii[b + k] - radii[b]) / (thetas[b + k] - thetas[b]) * span
    # Fritsch-Carlson limits: the bridge never dips below or rises above its two ends
    delta = radii[b] - radii[a]
    s1 = 0.0 if s1 * delta <= 0 else math.copysign(min(abs(s1), 3 * abs(delta)), delta)
    s2 = 0.0 if s2 * delta <= 0 else math.copysign(min(abs(s2), 3 * abs(delta)), delta)
    u = (thetas[a:b + 1] - thetas[a]) / span
    h00, h10, h01, h11 = 2 * u**3 - 3 * u**2 + 1, u**3 - 2 * u**2 + u, -2 * u**3 + 3 * u**2, u**3 - u**2
    bridged = h00 * radii[a] + h10 * s1 + h01 * radii[b] + h11 * s2
    # draw the bridged sector at 4x and downsample for an anti-aliased coverage field
    scale = 4
    from PIL import ImageDraw
    canvas = Image.new('L', (W * scale, H * scale), 0)
    poly = [(cx * scale, cy * scale)] + [((cx + r * math.cos(math.radians(th))) * scale, (cy + r * math.sin(math.radians(th))) * scale)
                                         for th, r in zip(thetas[a:b + 1], bridged)]
    ImageDraw.Draw(canvas).polygon(poly, fill=255)
    sector = np.asarray(canvas.resize((W, H), Image.LANCZOS), dtype=float) / 255
    # only the part the beak covers changes; the visible edge and the chin notch stay as traced
    # the bridge covers the beak's whole footprint plus its 1 px rim, so no seam opens when the beak moves
    under = ndimage.gaussian_filter(ndimage.binary_dilation(beak_field > 0.5, iterations=1).astype(float), 0.5)
    # drop the beak's own anti-aliased rim from the head, or a hairline of head shows when the beak moves
    base = head_field * (1 - np.clip(beak_field, 0, 1))
    return np.maximum((1 - under) * base, under * sector), (float(thetas[a]), float(thetas[b]))


head, BEAK_SECTOR = bridge_under_beak(head, beak, hx, hy)
head = smooth_under(head, beak, 4, reach=0)
body = smooth_under(body, head, 10, reach=0)  # only redrawn poses expose the neck under the head

contours = {name: outer(f) for name, f in [('silhouette', sil), ('head', head), ('body', body), ('wing', wing), ('beak', beak)]}
ex, ey, er, erms = fit_circle(outer(eye_field))
hl_field = np.where(np.hypot(XX - ex, YY - ey) < er - 2, coverage(WHITE, [NAVY]), 0.0)
lx, ly, lr, lrms = fit_circle(outer(hl_field))

paths = {k: fit_closed(v) for k, v in contours.items()}
segments = {k: len(v) for k, v in paths.items()}

tokens = json.load(open(TOKENS))
P = tokens['brand']['primaries']; ILL = tokens['illustration']['colors']
C = {'yellow': P['duckYellow']['value'], 'blue': P['wingBlue']['value'], 'orange': P['beakOrange']['value'],
     'ink': ILL['ink']['value'], 'highlight': ILL['paper']['value']}

# pivot for tilting the whole duck: bottom centre of the silhouette
ys, xs = np.nonzero(sil > 0.5)
tilt_pivot = (round(float(xs.min() + xs.max()) / 2, 1), round(float(ys.max()), 1))

f2 = lambda v: f"{v:.2f}".rstrip('0').rstrip('.')
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <!-- BackupDuck character master v2. Traced from assets/AppIcon.png; colors from design/backupduck-v1/tokens.json. -->
  <!-- Rig: rotate #duck around its data-pivot to tilt; rotate #face around its data-pivot (the head centre) to turn the face. -->
  <g id="duck" data-pivot="{tilt_pivot[0]} {tilt_pivot[1]}">
    <path id="body" d="{to_path(paths['body'])}" fill="{C['yellow']}"/>
    <path id="wing" d="{to_path(paths['wing'])}" fill="{C['blue']}"/>
    <g id="head">
      <path id="head-shape" d="{to_path(paths['head'])}" fill="{C['yellow']}"/>
      <g id="face" data-pivot="{f2(hx)} {f2(hy)}">
        <path id="beak" d="{to_path(paths['beak'])}" fill="{C['orange']}"/>
        <g id="eye">
          <circle id="eye-ball" cx="{f2(ex)}" cy="{f2(ey)}" r="{f2(er)}" fill="{C['ink']}"/>
          <circle id="eye-highlight" cx="{f2(lx)}" cy="{f2(ly)}" r="{f2(lr)}" fill="{C['highlight']}"/>
        </g>
      </g>
    </g>
  </g>
</svg>
'''
open(OUT, 'w').write(svg)
def joint_turns(curves):
    """Tangent change in degrees at every joint between consecutive curves."""
    out = []
    for a, b in zip(curves, curves[1:] + curves[:1]):
        t1 = a[3] - a[2]; t2 = b[1] - b[0]
        if np.linalg.norm(t1) < 1e-6 or np.linalg.norm(t2) < 1e-6:
            continue
        cosang = np.clip(t1 @ t2 / (np.linalg.norm(t1) * np.linalg.norm(t2)), -1, 1)
        out.append((float(np.degrees(np.arccos(cosang))), (float(a[3][0]), float(a[3][1]))))
    return out


def in_mask(mask, pt):
    x, y = int(pt[0]), int(pt[1])
    return 0 <= x < W and 0 <= y < H and bool(mask[y, x])


beak_cover = ndimage.binary_erosion(beak > 0.5, iterations=4)
head_cover = ndimage.binary_erosion(head > 0.5, iterations=4)
hidden_turns = {
    'head_under_beak': max([t for t, p in joint_turns(paths['head']) if in_mask(beak_cover, p)] or [0.0]),
    'body_under_head': max([t for t, p in joint_turns(paths['body']) if in_mask(head_cover, p)] or [0.0]),
}
wing_pts = np.array(contours['wing'])
wing_root = wing_pts[np.argmin(wing_pts[:, 0])]
sha = lambda path: hashlib.sha256(open(path, 'rb').read()).hexdigest()

geometry = {
    'head_circle': {'cx': round(hx, 2), 'cy': round(hy, 2), 'r': round(hr, 2), 'rms': round(hrms, 2), 'max_edge_radius': round(head_max, 2)},
    'eye': {'cx': round(ex, 2), 'cy': round(ey, 2), 'r': round(er, 2), 'rms': round(erms, 2)},
    'highlight': {'cx': round(lx, 2), 'cy': round(ly, 2), 'r': round(lr, 2), 'rms': round(lrms, 2)},
    'face_pivot': (round(hx, 2), round(hy, 2)), 'tilt_pivot': tilt_pivot, 'hidden_neck_ellipse': NECK,
    'segments': segments, 'colors': C,
    'hidden_joint_max_turn_deg': {k: round(v, 1) for k, v in hidden_turns.items()},
    'wing_root': [round(float(wing_root[0]), 1), round(float(wing_root[1]), 1)],
    'beak_sector_deg': [round(v, 2) for v in BEAK_SECTOR],
    'inputs': {'icon_sha256': sha(ICON), 'tokens_sha256': sha(TOKENS)},
}
json.dump(geometry, open(GEOMETRY, 'w'), indent=1)
print(json.dumps(geometry))
