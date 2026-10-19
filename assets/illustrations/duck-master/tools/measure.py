"""Measure how closely a rendered duck matches a reference image.

Usage: measure.py REFERENCE.png CANDIDATE.png REGION_DIFF_OUT.png

Render both images with tools/render.py so size, renderer and backdrop match.
Each pixel is labelled with the nearest brand color (yellow, blue, orange, ink,
highlight or paper). The script reports, per color region:

- IoU: overlap of the two regions after dropping specks under 40 px, which are
  anti-aliased pixels between two other colors.
- Edge distance: for every edge pixel of one region, the distance to the nearest
  edge pixel of the other region; mean, 99th percentile and maximum in pixels.
- status: "missing" when a region is absent from either image.

The eye is the largest ink region with its holes filled (the highlight), so the
beak can never contribute. Its centre is the region centroid and its diameter
the equal-area diameter. Keypoints are the beak tip, the tail tip and the corner
where the back meets the head.

REGION_DIFF_OUT marks pixels whose color label differs. It ignores shading inside
a label, so it is a region difference, not an RGB difference. Thresholds live in
the README.
"""
import json
import math
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ref_path, cand_path, diff_path = sys.argv[1:4]

PALETTE = {
    'paper': (254, 251, 242), 'yellow': (253, 197, 18), 'blue': (16, 101, 228),
    'orange': (249, 114, 18), 'ink': (16, 36, 71), 'highlight': (255, 255, 255),
}
NAMES = list(PALETTE)
COLS = np.array([PALETTE[n] for n in NAMES], dtype=float)


def load(path):
    img = Image.open(path).convert('RGBA')
    bg = Image.new('RGBA', img.size, PALETTE['paper'] + (255,)); bg.alpha_composite(img)
    return np.asarray(bg.convert('RGB'), dtype=float)


def classify(img):
    return (((img[..., None, :] - COLS[None, None]) ** 2).sum(-1)).argmin(-1)


def solid(mask, min_px=40):
    lab, n = ndimage.label(mask)
    if n == 0:
        return mask
    sizes = ndimage.sum(mask, lab, range(1, n + 1))
    return np.isin(lab, 1 + np.nonzero(sizes >= min_px)[0])


def edges(mask):
    return mask & ~ndimage.binary_erosion(mask)


def region(a, b):
    if not a.any() or not b.any():
        return {'status': 'missing', 'in_reference': bool(a.any()), 'in_candidate': bool(b.any())}
    ea, eb = edges(a), edges(b)
    da = ndimage.distance_transform_edt(~eb)[ea]; db = ndimage.distance_transform_edt(~ea)[eb]
    both = np.concatenate([da, db])
    return {'status': 'ok', 'iou': round(float((a & b).sum() / (a | b).sum()), 4),
            'edge_mean_px': round(float(both.mean()), 2), 'edge_p99_px': round(float(np.percentile(both, 99)), 2),
            'edge_max_px': round(float(both.max()), 2)}


def eye(c):
    ink = solid(c == NAMES.index('ink'))
    lab, n = ndimage.label(ink)
    if n == 0:
        return None
    largest = lab == (1 + int(np.argmax(ndimage.sum(ink, lab, range(1, n + 1)))))
    filled = ndimage.binary_fill_holes(largest)
    ys, xs = np.nonzero(filled)
    return {'cx': round(float(xs.mean()) + 0.5, 2), 'cy': round(float(ys.mean()) + 0.5, 2),
            'diameter': round(2 * math.sqrt(filled.sum() / math.pi), 2)}


def keypoints(c):
    yellow, orange = NAMES.index('yellow'), NAMES.index('orange')
    out = {}
    ys, xs = np.nonzero(solid(c == orange))
    out['beak_tip'] = (int(xs.max()), int(np.median(ys[xs == xs.max()]))) if len(xs) else None
    tail = solid(c == yellow); tail[:, 300:] = False
    ty, tx = np.nonzero(tail)
    out['tail_tip'] = (int(np.median(tx[ty == ty.min()])), int(ty.min())) if len(ty) else None

    def body_top(x):  # scanning up from just above the wing, the first non-yellow pixel
        y = 505
        while y > 300 and c[y, x] == yellow:
            y -= 1
        return y
    tops = [body_top(x) for x in range(400, 560)]
    out['back_head_corner'] = next(((400 + i, tops[i - 1]) for i in range(1, len(tops)) if tops[i - 1] - tops[i] > 20), None)
    return out


ref, cand = load(ref_path), load(cand_path)
if ref.shape != cand.shape:
    raise SystemExit(f'size mismatch: {ref.shape} vs {cand.shape}')
cr, cc = classify(ref), classify(cand)

regions = {n: region(solid(cr == k), solid(cc == k)) for k, n in enumerate(NAMES) if n not in ('paper', 'highlight')}
er, ec = eye(cr), eye(cc)
kr, kc = keypoints(cr), keypoints(cc)
out = {
    'regions': regions,
    'eye': {'reference': er, 'candidate': ec,
            'center_offset_px': round(math.hypot(er['cx'] - ec['cx'], er['cy'] - ec['cy']), 2) if er and ec else None,
            'diameter_delta_px': round(ec['diameter'] - er['diameter'], 2) if er and ec else None},
    'keypoints': {'reference': kr, 'candidate': kc,
                  'offset_px': {k: (round(math.dist(kr[k], kc[k]), 2) if kr[k] and kc[k] else None) for k in kr}},
}
out['status'] = 'ok' if all(r['status'] == 'ok' for r in regions.values()) and er and ec else 'incomplete'

diff = np.where((cr == cc)[..., None], np.array([235, 235, 235]), np.array([220, 40, 40])).astype(np.uint8)
Image.fromarray(diff).save(diff_path)
print(json.dumps(out, indent=1))
