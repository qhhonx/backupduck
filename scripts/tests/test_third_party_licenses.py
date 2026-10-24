"""Regression checks for grouped notices, attribution and staleness."""
import contextlib
import importlib.util
import io
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    'notices', ROOT / 'apps/apple/Scripts/generate-third-party-licenses.py')
notices = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(notices)


class ThirdPartyNoticesTests(unittest.TestCase):
    def test_shared_body_retains_every_component_and_full_attribution(self):
        apache = (ROOT / 'apps/android/app/license-texts/Apache-2.0.txt').read_text()
        entries = [dict(name=name, version='1.2.3', license='Apache-2.0', texts=[
            f'Copyright 2026 {name}\n  and its contributors\n\n' + body])
            for name, body in [('first', apache), ('second', apache.replace('\n', '\r\n'))]]
        result = notices.grouped_document(entries)
        self.assertEqual(result.count('END OF TERMS AND CONDITIONS'), 1)
        self.assertEqual(result.count('same "printed page"'), 1)
        for name in ('first', 'second'):
            self.assertIn(f'{name} 1.2.3', result)
            self.assertIn(f'Copyright 2026 {name}\n  and its contributors', result)

    def test_combined_distribution_and_differing_terms_are_not_dropped(self):
        apache = (ROOT / 'apps/android/app/license-texts/Apache-2.0.txt').read_text()
        document = apache + '\n\nNOTICE: Retain this credit.\n\nAdditional restriction.'
        changed = apache.replace('January 2004', 'January 2005')
        entries = [dict(name='combined', version='2', license='Bundled notices', texts=[document]),
                   dict(name='different', version='3', license='Modified license', texts=[changed])]
        result = notices.grouped_document(entries)
        self.assertIn('NOTICE: Retain this credit.', result)
        self.assertIn('Additional restriction.', result)
        self.assertIn('January 2005', result)
        self.assertEqual(result.count('END OF TERMS AND CONDITIONS'), 2)

    def test_check_reports_each_stale_distribution_without_writing(self):
        entry = dict(name='fixture', version='1', license='Test', texts=['Fixture license'])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sparkle = root / 'build/dependencies/sparkle'
            (sparkle / 'Sparkle.framework/Resources').mkdir(parents=True)
            (sparkle / 'LICENSE').write_text('Sparkle fixture license')
            (sparkle / 'Sparkle.framework/Resources/Info.plist').write_bytes(
                plistlib.dumps({'CFBundleShortVersionString': '1'}))
            (root / 'LICENSE').write_text('Project fixture license')
            resources = root / 'resources'
            resources.mkdir()
            for name in ('ThirdPartyNotices-ios.txt', 'ThirdPartyNotices-mac.txt',
                         'ThirdPartyNotices-mac-sparkle.txt'):
                (resources / name).write_text('Stale fixture')
            with patch.object(notices, 'ROOT', root), patch.object(notices, 'RESOURCES', root / 'resources'), \
                 patch.object(notices, 'cargo_notices', return_value=[entry]), \
                 patch.object(notices, 'android_notices', return_value=[entry]), \
                 patch('sys.argv', ['generator', '--check']), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit) as failure:
                    notices.main()
            for path in ('ThirdPartyNotices-ios.txt', 'ThirdPartyNotices-mac.txt',
                         'ThirdPartyNotices-mac-sparkle.txt', 'third-party-notices.txt', 'project-license.txt'):
                self.assertIn(path, str(failure.exception))
            self.assertEqual((resources / 'ThirdPartyNotices-ios.txt').read_text(), 'Stale fixture')
            self.assertFalse((root / 'apps/android/app/src/main/assets').exists())


if __name__ == '__main__':
    unittest.main()
