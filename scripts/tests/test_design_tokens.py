import importlib.util
import sys
import unittest
from unittest.mock import patch
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import design_color  # noqa: E402

spec = importlib.util.spec_from_file_location('check_design_literals', SCRIPTS / 'check-design-literals.py')
literals = importlib.util.module_from_spec(spec)
spec.loader.exec_module(literals)

export_spec = importlib.util.spec_from_file_location('export_design_tokens', SCRIPTS / 'export-design-tokens.py')
exporter = importlib.util.module_from_spec(export_spec)
export_spec.loader.exec_module(exporter)


class AttentionGlyphContrastTests(unittest.TestCase):
    def test_current_roles_meet_their_contrast_floors(self):
        self.assertEqual(exporter.check_contrast(), [])

    def test_invisible_glyph_is_rejected_in_every_appearance(self):
        for appearance in exporter.APPEARANCES:
            mode = 'dark' if appearance.startswith('dark') else 'light'
            surface = exporter.NEUTRAL['groupedSurface']['web'][mode]
            with self.subTest(appearance=appearance), patch.dict(exporter.ATTENTION_GLYPH, {appearance: surface}):
                failures = exporter.check_contrast()
                self.assertTrue(any(f'attentionGlyph {appearance}:' in failure for failure in failures))

    def test_android_page_and_card_are_checked_independently(self):
        for index, mode in enumerate(('light', 'dark')):
            for role in ('background', 'groupedSurface'):
                surface = exporter.SCHEME[exporter.NEUTRAL[role]['android']][index]
                with self.subTest(mode=mode, role=role), patch.dict(exporter.ATTENTION_GLYPH, {mode: surface}):
                    failures = exporter.check_contrast()
                    self.assertTrue(any(f'android attentionGlyph on {role} {mode}:' in failure for failure in failures))


def matches(language, line):
    return [label for _, label, pattern in literals.RULES[language] if pattern.search(line)]


class ColorMathTests(unittest.TestCase):
    def test_matches_material_baseline_palette(self):
        hue, _, tone = design_color.hct('#6750A4')
        self.assertAlmostEqual(tone, 40, delta=0.2)
        # Reference tones from the Material 3 baseline primary palette, within one 8-bit step.
        for tone, expected in ((40, '#6750A4'), (80, '#D0BCFF'), (90, '#EADDFF'), (10, '#21005D')):
            actual = design_color.parse_hex(design_color.from_hct(hue, 48, tone))
            for a, e in zip(actual, design_color.parse_hex(expected)):
                self.assertLessEqual(abs(a - e), 1, f'tone {tone}')

    def test_round_trips_brand_primaries(self):
        for value in ('#1065E4', '#FEC613', '#FA7212'):
            self.assertEqual(design_color.from_hct(*design_color.hct(value)), value)

    def test_reduces_chroma_out_of_gamut(self):
        value = design_color.from_hct(90, 200, 50)
        self.assertRegex(value, r'^#[0-9A-F]{6}$')
        self.assertAlmostEqual(design_color.hct(value)[2], 50, delta=0.5)


class LiteralRuleTests(unittest.TestCase):
    def test_swift_literals(self):
        self.assertTrue(matches('swift', 'Color(red: 1, green: 0, blue: 0)'))
        self.assertTrue(matches('swift', '.foregroundStyle(.orange)'))
        self.assertTrue(matches('swift', 'label.textColor = .white'))
        self.assertTrue(matches('swift', 'Text(x).font(.system(size: 14))'))
        self.assertTrue(matches('swift', 'label.font = .systemFont(ofSize: 13, weight: .bold)'))

    def test_swift_semantic_uses_pass(self):
        for line in ('.foregroundStyle(.secondary)', '.font(.headline)', 'DuckRole.accent',
                     '.duckTextStyle(.body)', 'label.font = .preferredFont(forTextStyle: .body)',
                     'case .red: break', 'Color(uiColor: .label)'):
            self.assertFalse(matches('swift', line), line)

    def test_android_literals(self):
        self.assertTrue(matches('kotlin', 'duckText(title, 13, true)'))
        self.assertTrue(matches('kotlin', 'textSize = 16f'))
        self.assertTrue(matches('kotlin', 'Color.parseColor("#FFFFFF")'))
        self.assertFalse(matches('kotlin', 'duckText(getString(R.string.x))'))
        self.assertTrue(matches('xml', '<item name="android:textSize">24sp</item>'))
        self.assertTrue(matches('xml', 'android:fillColor="#202C3E"'))
        self.assertFalse(matches('xml', 'android:fillColor="?attr/colorOnSurface"'))

    def test_tinted_vector_exempts_only_paint_literals(self):
        source = ('<vector xmlns:android="http://schemas.android.com/apk/res/android" '
                  'android:tint="#ABCDEF"><path android:fillColor="#123456" '
                  'android:strokeColor="#654321" android:color="#FEDCBA"/></vector>')
        masked = literals.tinted_vector_source(source)
        self.assertEqual(len(masked), len(source))
        self.assertEqual(literals.RULES['xml'][0][2].findall(masked), ['#ABCDEF', '#FEDCBA'])

    def test_vector_exemption_requires_explicit_root_tint(self):
        prefix = '<vector xmlns:android="http://schemas.android.com/apk/res/android" '
        for source in (
            prefix + '><path android:fillColor="#123456"/></vector>',
            prefix + 'android:tint="@null"><path android:fillColor="#123456"/></vector>',
            prefix + 'android:tint=""><path android:fillColor="#123456"/></vector>',
            prefix + '><path android:tint="@color/token" android:fillColor="#123456"/></vector>',
            prefix + '><!-- android:tint="@color/token" --><path android:fillColor="#123456"/></vector>',
            prefix + 'android:tint="@color/token"><path android:fillColor="#123456"></vector>',
            '<shape xmlns:android="http://schemas.android.com/apk/res/android" '
            'android:tint="@color/token"><solid android:fillColor="#123456"/></shape>',
        ):
            with self.subTest(source=source):
                self.assertEqual(literals.tinted_vector_source(source), source)

    def test_tinted_vector_preserves_multiline_diagnostic_positions(self):
        source = ('<vector xmlns:android="http://schemas.android.com/apk/res/android" '
                  'android:tint="?attr/colorOnSurface">\n<path android:fillColor=\n'
                  '"#123456" android:strokeColor=\n\'#654321\'/></vector>')
        masked = literals.tinted_vector_source(source)
        self.assertEqual([len(line) for line in masked.splitlines()],
                         [len(line) for line in source.splitlines()])
        self.assertFalse(matches('xml', masked))


if __name__ == '__main__':
    unittest.main()
