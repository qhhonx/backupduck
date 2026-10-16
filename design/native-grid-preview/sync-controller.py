#!/usr/bin/env python3
"""Keep the standalone Grid controller behavior aligned with production."""
from pathlib import Path
import argparse
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
production = (root / 'apps/ios/BackupDuck/CalendarGridController.swift').read_text()
reference_path = Path(__file__).with_name('GridScene.swift')
reference = reference_path.read_text()
start = 'struct CalendarGridAsset:'
end = '/// Review actions keep compact default metrics'
controller = production[production.index(start):production.index(end)]
translations = dict(re.findall(r'"([^"\n]+)"\s*=\s*("(?:[^"\\]|\\.)*")\s*;',
    (root / 'apps/apple/Resources/en.lproj/Localizable.strings').read_text()))
def english(match):
    key = match.group(1)
    if key not in translations:
        raise ValueError(f'Missing English reference text: {key}')
    return translations[key]
controller = re.sub(r'NSLocalizedString\(\s*"([^"]+)",\s*comment:\s*""\)',english,controller)
for token, color in {'canvas':'systemBackground','subtle':'secondarySystemBackground',
                    'text':'label','textSecondary':'secondaryLabel','action':'systemBlue',
                    'failure':'systemRed','saved':'systemGreen','surface':'secondarySystemBackground'}.items():
    controller = controller.replace(f'UIColor(DuckColors.{token})', f'UIColor.{color}')
for production_id, reference_id in {'library.grid':'calendar.grid','library.count':'calendar.subtitle',
    'library.view_mode':'calendar.level','library.filter':'calendar.options',
    'library.select_mode':'calendar.select','library.asset.':'calendar.asset.'}.items():
    controller = controller.replace(f'"{production_id}', f'"{reference_id}')
controller = controller.replace('DuckMediaSelection.configure(check)',
    'check.tintColor = .systemBlue; check.backgroundColor = .white; check.layer.cornerRadius = 11; check.clipsToBounds = true')
controller = controller.replace('DuckMediaSelection.frame(in: bounds)',
    'CGRect(x: bounds.width - 29, y: bounds.height - 29, width: 23, height: 23)')
controller = controller.replace('DuckMediaSelection.apply(selected, enabled: enabled, badge: check, image: image)',
    'check.image = UIImage(systemName: "checkmark.circle.fill"); check.isHidden = !enabled || !selected; image.alpha = selected && enabled ? 0.72 : 1')
controller = controller.replace('"calendar.date_badge"','"calendar.period_heading"')
expected = reference[:reference.index(start)] + controller + reference[reference.index(end):]
if args.check:
    if expected != reference:
        raise SystemExit('Grid reference controller is out of date; run sync-controller.py.')
    print('Grid reference controller verified.')
else:
    reference_path.write_text(expected)
    print('Grid reference controller synchronized; production source was not modified.')
