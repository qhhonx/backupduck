#!/usr/bin/env python3
"""Check Chinese prose punctuation without interpreting resource XML as prose."""
from pathlib import Path
import re
import xml.etree.ElementTree as ET


def punctuation_error(value):
    # Android resolves Unicode escapes after XML parsing, including in format strings.
    value = re.sub(r'\\u([0-9a-fA-F]{4})', lambda m: chr(int(m[1], 16)), value)
    prose = re.sub(r'https?://[^\s"<>]+', '', value)
    return '?' in prose or bool(re.search(r'[\u3400-\u9fff]', prose) and re.search(r'[()]', prose))


def main():
    errors = []
    for file in (Path(__file__).resolve().parents[1] / 'app/src/main/res/values-zh-rCN').glob('*.xml'):
        for node in ET.parse(file).getroot():
            if node.tag not in ('string', 'plurals', 'string-array'):
                continue
            if punctuation_error(''.join(node.itertext())):
                errors.append(f'{file.name}:{node.attrib.get("name")}: use full-width Chinese punctuation')
    if errors:
        raise SystemExit('\n'.join(errors))
    print('Chinese resource punctuation: passed')


if __name__ == '__main__':
    main()
