#!/usr/bin/env python3
"""Regenerate grouped notices from locked Cargo and resolved Android graphs.

Run after cargo fetch and scripts/fetch-sparkle.sh, with Java 17 and the Android
SDK configured for Android generation. No machine paths are emitted.
Use --check in CI to detect stale resources after dependency changes.
"""
import argparse
import json
import re
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
RESOURCES = ROOT / 'apps/apple/Resources'


def cargo_notices(target, features):
    command = ['cargo', 'metadata', '--offline', '--locked', '--format-version', '1',
               '--no-default-features', '--filter-platform', target]
    tree = ['cargo', 'tree', '--offline', '--locked', '-p', 'backupduck-native',
            '--no-default-features', '--target', target, '--edges', 'normal,build',
            '--prefix', 'none', '--format', '{p}']
    if features:
        command += ['--features', features]
        tree += ['--features', features]
    # Metadata includes optional dependencies that the native host does not
    # enable. Select the host's actual normal/build graph before reading texts.
    enabled = {(parts[0], parts[1].removeprefix('v'))
               for line in subprocess.check_output(tree, cwd=ROOT, text=True).splitlines()
               if len(parts := line.split()) >= 2}
    data = json.loads(subprocess.check_output(command, cwd=ROOT))
    notices = []
    for package in data['packages']:
        if package['source'] is None or (package['name'], package['version']) not in enabled:
            continue
        directory = Path(package['manifest_path']).parent
        files = set()
        if package.get('license_file'):
            files.add(directory / package['license_file'])
        for pattern in ('LICENSE*', 'LICENCE*', 'COPYING*', 'NOTICE*', 'license*', 'licence*'):
            files.update(path for path in directory.glob(pattern) if path.is_file())
        for folder in ('licenses', 'LICENSES'):
            if (directory / folder).is_dir():
                files.update(path for path in (directory / folder).rglob('*') if path.is_file())
        texts = [path.read_text(encoding='utf-8').strip() for path in sorted(files)]
        override = ROOT / 'apps/apple/Scripts/license-overrides' / f"{package['name']}-{package['version']}.txt"
        if not texts and override.exists():
            texts = [override.read_text()]
        if not texts:
            raise SystemExit(f"Missing bundled license text: {package['name']} {package['version']}")
        notices.append(dict(name=package['name'], version=package['version'],
                            license=package.get('license') or 'See notice',
                            texts=texts))
    return sorted(notices, key=lambda item: (item['name'].casefold(), item['version']))


# Split common license bodies out of combined distributions without dropping
# appendices, copyright notices or additional terms. Only whitespace is ignored
# when grouping; differing terms always remain separate.
COMMON = re.compile(
    r'(?P<apache>Apache License\s+Version 2\.0, January 2004\s+'
    r'https?://www\.apache\.org/licenses/.*?END OF TERMS AND CONDITIONS)'
    r'|(?P<mit>Permission is hereby granted, free of charge, to any person obtaining a copy\s+'
    r'of this software.*?OTHER DEALINGS IN THE SOFTWARE\.)', re.S)


def grouped_document(notices, document_title="Third-party software"):
    groups = {}
    for item in notices:
        for original in item['texts']:
            original = original.replace('\r\n', '\n').strip()
            matches = list(COMMON.finditer(original))
            parts = []
            cursor = 0
            for match in matches:
                parts.append(('Additional terms and attribution', original[cursor:match.start()]))
                parts.append(('Apache License 2.0' if match.lastgroup == 'apache' else 'MIT License', match.group()))
                cursor = match.end()
            parts.append(('Additional terms and attribution' if matches else item['license'], original[cursor:]))
            # Keep copyright lines next to the components using a common body.
            # Complete preambles, including wrapped attribution, also remain
            # grouped below; no source text is discarded.
            attribution = '\n'.join(line.strip() for title, text in parts
                if title == 'Additional terms and attribution'
                for line in text.splitlines()
                if re.match(r'^\s*(?:Copyright\s+(?:\(c\)\s*|\d{4})|©)', line, re.I)
                and not re.search(r'\[(?:yyyy|year)\]', line, re.I))
            for title, body in parts:
                body = body.strip()
                if not body:
                    continue
                key = ' '.join(body.split())
                group = groups.setdefault(key, {'title': title, 'body': body, 'components': {}})
                component = f"{item['name']} {item['version']}"
                group['components'].setdefault(component, set())
                if title in ('MIT License', 'Apache License 2.0') and attribution:
                    group['components'][component].add(attribution)
    sections = [document_title + '\n\nGenerated from the locked shipping dependencies.\n'
                'Each distinct license text is included once, after its components.']
    for key, group in sorted(groups.items(), key=lambda pair: (
            0 if pair[1]['title'] == 'Apache License 2.0' else 1 if pair[1]['title'] == 'MIT License' else 2,
            pair[1]['title'], pair[0])):
        lines = [group['title'], '=' * len(group['title']), '', 'Components:']
        for component, attributions in sorted(group['components'].items()):
            lines.append(component)
            for attribution in sorted(attributions):
                lines.extend('  ' + line for line in attribution.splitlines())
        sections.append('\n'.join(lines) + '\n\n' + group['body'])
    return '\n\n\n'.join(sections) + '\n'


def android_notices(input_path):
    if input_path is None:
        subprocess.run(['./gradlew', '--quiet', ':app:exportLicenseInputs'], cwd=ROOT / 'apps/android',
                       check=True)
        input_path = ROOT / 'apps/android/app/build/license-inputs.json'
    return json.loads(input_path.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--platform', choices=['all', 'ios', 'mac', 'android'], default='all')
    parser.add_argument('--android-input', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    outputs = {}
    if args.platform in ('all', 'ios'):
        outputs[RESOURCES / 'ThirdPartyNotices-ios.txt'] = cargo_notices('aarch64-apple-ios-sim', '')
    if args.platform in ('all', 'mac'):
        mac = cargo_notices('aarch64-apple-darwin', 'backupduck-native/folder-source')
        outputs[RESOURCES / 'ThirdPartyNotices-mac.txt'] = mac
        sparkle = ROOT / 'build/dependencies/sparkle'
        import plistlib
        version = plistlib.loads((sparkle / 'Sparkle.framework/Resources/Info.plist').read_bytes())['CFBundleShortVersionString']
        outputs[RESOURCES / 'ThirdPartyNotices-mac-sparkle.txt'] = mac + [dict(name='Sparkle', version=version,
            license='Sparkle bundled third-party notices', texts=[(sparkle / 'LICENSE').read_text()])]
    if args.platform in ('all', 'android'):
        outputs[ROOT / 'apps/android/app/src/main/assets/third-party-notices.txt'] = (
            cargo_notices('aarch64-linux-android', '') + android_notices(args.android_input))
    stale = []
    if args.platform in ('all', 'android'):
        project = ROOT / 'apps/android/app/src/main/assets/project-license.txt'
        expected = (ROOT / 'LICENSE').read_text()
        if args.check:
            if not project.exists() or project.read_text() != expected:
                stale.append(str(project.relative_to(ROOT)))
        else:
            project.write_text(expected)
    for path, notices in outputs.items():
        text = grouped_document(notices, document_title="Third-Party Software" if path.parent == RESOURCES else "Third-party software")
        if args.check:
            if not path.exists() or path.read_text() != text:
                stale.append(str(path.relative_to(ROOT)))
        else:
            path.write_text(text)
        print(f'{path.name}: {len(notices)} components, {len(text.encode())} bytes')
    if stale:
        raise SystemExit('Stale license resources:\n' + '\n'.join(stale))


if __name__ == '__main__':
    main()
