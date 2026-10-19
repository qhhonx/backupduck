import importlib.util
import sys
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import design_color  # noqa: E402

spec = importlib.util.spec_from_file_location('check_design_literals', SCRIPTS / 'check-design-literals.py')
literals = importlib.util.module_from_spec(spec)
spec.loader.exec_module(literals)


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


if __name__ == '__main__':
    unittest.main()
