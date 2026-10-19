"""HCT color math for generated design tokens.

HCT combines CAM16 hue and chroma with CIE L* tone, the color space Material 3
uses for tonal palettes. This is a compact port of the published
material-color-utilities algorithms under default viewing conditions (D65,
L* 50 background, average surround). It solves tones by iteration and reduces
chroma to stay in the sRGB gamut, so a value may differ from the reference
implementation by one 8-bit step.
"""
import math

_SRGB_TO_XYZ = ((0.41233895, 0.35762064, 0.18051042),
                (0.2126, 0.7152, 0.0722),
                (0.01932141, 0.11916382, 0.95034478))
_XYZ_TO_SRGB = ((3.2413774792388685, -1.5376652402851851, -0.49885366846268053),
                (-0.9691452513005321, 1.8758853451067872, 0.04156585616912061),
                (0.05562093689691305, -0.20395524564742123, 1.0571799111220335))
_XYZ_TO_CAM = ((0.401288, 0.650173, -0.051461),
               (-0.250268, 1.204414, 0.045854),
               (-0.002079, 0.048952, 0.953127))
_CAM_TO_XYZ = ((1.86206786, -1.01125463, 0.14918677),
               (0.38752654, 0.62144744, -0.00897398),
               (-0.01584150, -0.03412294, 1.04996444))
_WHITE = (95.047, 100.0, 108.883)


def _mul(matrix, vector):
    return tuple(sum(m * v for m, v in zip(row, vector)) for row in matrix)


def _linear(channel):
    c = channel / 255
    return (c / 12.92 if c <= 0.040449936 else ((c + 0.055) / 1.055) ** 2.4) * 100


def _delinear(component):
    c = component / 100
    c = 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
    return c * 255


def y_from_lstar(lstar):
    ft = (lstar + 16) / 116
    return 100 * (ft ** 3 if ft ** 3 > 216 / 24389 else lstar / (24389 / 27))


def lstar_from_y(y):
    t = y / 100
    ft = t ** (1 / 3) if t > 216 / 24389 else (24389 / 27 * t + 16) / 116
    return 116 * ft - 16


def _viewing_conditions():
    adapting = 200 / math.pi * y_from_lstar(50) / 100
    rgb_w = _mul(_XYZ_TO_CAM, _WHITE)
    f, c, nc = 1.0, 0.69, 1.0
    d = max(0.0, min(1.0, f * (1 - (1 / 3.6) * math.exp((-adapting - 42) / 92))))
    rgb_d = tuple(d * (100 / w) + 1 - d for w in rgb_w)
    k = 1 / (5 * adapting + 1)
    fl = k ** 4 * adapting + 0.1 * (1 - k ** 4) ** 2 * (5 * adapting) ** (1 / 3)
    n = y_from_lstar(50) / _WHITE[1]
    z = 1.48 + math.sqrt(n)
    nbb = 0.725 / n ** 0.2
    factors = tuple((fl * dd * w / 100) ** 0.42 for dd, w in zip(rgb_d, rgb_w))
    rgb_a = tuple(400 * x / (x + 27.13) for x in factors)
    aw = (2 * rgb_a[0] + rgb_a[1] + 0.05 * rgb_a[2]) * nbb
    return dict(n=n, aw=aw, nbb=nbb, ncb=nbb, c=c, nc=nc, rgb_d=rgb_d, fl=fl, z=z)


_VC = _viewing_conditions()


def parse_hex(value):
    value = value.lstrip('#')
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def to_hex(rgb):
    return '#' + ''.join(f'{round(max(0, min(255, c))):02X}' for c in rgb)


def cam16(rgb):
    """Return (hue, chroma, J) for an sRGB triple."""
    xyz = _mul(_SRGB_TO_XYZ, tuple(_linear(c) for c in rgb))
    vc = _VC
    rgb_d = tuple(d * c for d, c in zip(vc['rgb_d'], _mul(_XYZ_TO_CAM, xyz)))
    af = tuple((vc['fl'] * abs(c) / 100) ** 0.42 for c in rgb_d)
    ra, ga, ba = (math.copysign(400 * x / (x + 27.13), c) for x, c in zip(af, rgb_d))
    a = (11 * ra - 12 * ga + ba) / 11
    b = (ra + ga - 2 * ba) / 9
    u = (20 * ra + 20 * ga + 21 * ba) / 20
    p2 = (40 * ra + 20 * ga + ba) / 20
    hue = math.degrees(math.atan2(b, a)) % 360
    j = 100 * (p2 * vc['nbb'] / vc['aw']) ** (vc['c'] * vc['z'])
    e_hue = 0.25 * (math.cos(math.radians(hue) + 2) + 3.8)
    t = 50000 / 13 * e_hue * vc['nc'] * vc['ncb'] * math.hypot(a, b) / (u + 0.305)
    alpha = t ** 0.9 * (1.64 - 0.29 ** vc['n']) ** 0.73
    return hue, alpha * math.sqrt(j / 100), j


def hct(value):
    """Return (hue, chroma, tone) for a hex color."""
    rgb = parse_hex(value)
    hue, chroma, _ = cam16(rgb)
    y = _mul(_SRGB_TO_XYZ, tuple(_linear(c) for c in rgb))[1]
    return hue, chroma, lstar_from_y(y)


def _xyz_from_jch(j, chroma, hue):
    vc = _VC
    alpha = 0 if chroma == 0 or j == 0 else chroma / math.sqrt(j / 100)
    t = (alpha / (1.64 - 0.29 ** vc['n']) ** 0.73) ** (1 / 0.9)
    h = math.radians(hue)
    e_hue = 0.25 * (math.cos(h + 2) + 3.8)
    ac = vc['aw'] * (j / 100) ** (1 / vc['c'] / vc['z'])
    p1 = e_hue * 50000 / 13 * vc['nc'] * vc['ncb']
    p2 = ac / vc['nbb']
    gamma = 23 * (p2 + 0.305) * t / (23 * p1 + 11 * t * math.cos(h) + 108 * t * math.sin(h))
    a, b = gamma * math.cos(h), gamma * math.sin(h)
    ra = (460 * p2 + 451 * a + 288 * b) / 1403
    ga = (460 * p2 - 891 * a - 261 * b) / 1403
    ba = (460 * p2 - 220 * a - 6300 * b) / 1403

    def unadapt(component):
        base = max(0.0, 27.13 * abs(component) / (400 - abs(component)))
        return math.copysign(100 / vc['fl'] * base ** (1 / 0.42), component)

    rgb_c = tuple(unadapt(c) / d for c, d in zip((ra, ga, ba), vc['rgb_d']))
    return _mul(_CAM_TO_XYZ, rgb_c)


def _solve(hue, chroma, tone):
    """Return linear sRGB for the color at this HCT, or None outside the gamut."""
    target = y_from_lstar(tone)
    j = math.sqrt(target) * 11
    for _ in range(12):
        xyz = _xyz_from_jch(j, chroma, hue)
        if xyz[1] <= 0:
            return None
        if abs(xyz[1] - target) < 0.002:
            break
        j = max(0.01, j - (xyz[1] - target) * j / (2 * xyz[1]))
    linear = _mul(_XYZ_TO_SRGB, xyz)
    if any(c < -0.01 or c > 100.01 for c in linear):
        return None
    return linear


def from_hct(hue, chroma, tone):
    """Return the hex color for HCT, reducing chroma until it fits sRGB."""
    if tone <= 0.0001:
        return '#000000'
    if tone >= 99.9999:
        return '#FFFFFF'
    linear = _solve(hue, chroma, tone)
    if linear is None:
        low, high = 0.0, chroma
        linear = _solve(hue, 0.0, tone)
        for _ in range(24):
            middle = (low + high) / 2
            candidate = _solve(hue, middle, tone)
            if candidate is None:
                high = middle
            else:
                low, linear = middle, candidate
    if linear is None:
        gray = _delinear(y_from_lstar(tone))
        return to_hex((gray, gray, gray))
    return to_hex(tuple(_delinear(c) for c in linear))


def tone_of(value, tone, chroma=None, hue_offset=0.0):
    """Return the given tone of a source color, keeping its hue and chroma."""
    hue, source_chroma, _ = hct(value)
    return from_hct((hue + hue_offset) % 360, source_chroma if chroma is None else chroma, tone)


def contrast(first, second):
    def luminance(value):
        return _mul(_SRGB_TO_XYZ, tuple(_linear(c) for c in parse_hex(value)))[1] / 100
    lighter, darker = sorted((luminance(first), luminance(second)), reverse=True)
    return (lighter + 0.05) / (darker + 0.05)
