#!/usr/bin/env python3
"""Check Chinese Apple UI punctuation without rewriting localization files."""
from pathlib import Path
import re
import sys


def punctuation_error(value):
    # Inspect runtime punctuation too, including escaped marks in format strings.
    value = re.sub(r'\\[uU]([0-9a-fA-F]{4})|\\([0-7]{3})',
                   lambda m: chr(int(m[1], 16) if m[1] else int(m[2], 8)), value)
    prose = re.sub(r'https?://[^\s"<>]+', '', value)
    return '?' in prose or bool(re.search(r"[\u3400-\u9fff]", prose) and re.search(r"[()]", prose))


def main():
    source = Path(__file__).resolve().parents[1] / "Resources/zh-Hans.lproj/Localizable.strings"
    errors = []
    for number, line in enumerate(source.read_text().splitlines(), 1):
        match = re.match(r'"([^"]+)" = "(.*)";$', line)
        if match and punctuation_error(match[2]):
            errors.append(f"{source}:{number}: {match[1]}: Chinese prose requires full-width punctuation")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("Apple Chinese UI punctuation verified.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
