"""Render duck SVGs to PNG with one fixed renderer, so measurements are comparable.

Usage: render.py OUT_DIR FILE.svg [FILE.svg ...]

Each SVG is drawn at 1024 x 1024 CSS px, device scale 1, onto the paper
backdrop #FEFBF3 (illustration.paper), by headless Google Chrome. Chrome renders
in sRGB. Set CHROME to use another Chrome or Chromium binary. The renderer and
its version are written to OUT_DIR/renderer.txt.
"""
import os
import pathlib
import subprocess
import sys
import tempfile

CHROME = os.environ.get('CHROME', '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
PAPER = '#FEFBF3'


def render(out_dir, svgs):
    """Render each SVG to OUT_DIR/<stem>.png and return the PNG paths."""
    out_dir = pathlib.Path(out_dir); out_dir.mkdir(parents=True, exist_ok=True)
    version = subprocess.run([CHROME, '--version'], capture_output=True, text=True).stdout.strip()
    (out_dir / 'renderer.txt').write_text(f'{version}\n--headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --window-size=1024,1024\nbackground {PAPER}\n')
    pngs = []
    for svg in svgs:
        svg = pathlib.Path(svg).resolve()
        with tempfile.TemporaryDirectory() as tmp:
            page = pathlib.Path(tmp) / 'page.html'
            page.write_text(f'<!doctype html><meta charset="utf-8"><style>html,body{{margin:0;background:{PAPER}}}img{{display:block}}</style>'
                            f'<img src="{svg.as_uri()}" width="1024" height="1024">')
            png = out_dir / (svg.stem + '.png')
            subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
                            '--allow-file-access-from-files', '--window-size=1024,1024', f'--screenshot={png}', page.as_uri()],
                           check=True, capture_output=True)
            pngs.append(png)
    return pngs


if __name__ == '__main__':
    for png in render(sys.argv[1], sys.argv[2:]):
        print(png)
