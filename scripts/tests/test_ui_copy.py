"""Regressions for Chinese question punctuation in localized format strings."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.punctuation_error


CHECKS = [load('apple_copy', 'apps/apple/Scripts/check-ui-copy.py'),
          load('android_copy', 'apps/android/scripts/check-chinese-copy.py')]


class ChineseQuestionTests(unittest.TestCase):
    def test_rejects_half_width_questions_and_format_strings(self):
        for check in CHECKS:
            for value in ['也备份以前的照片吗?', '也备份以前的 %@ 张照片吗?',
                          '备份 %1$s 张照片吗?', '%@?', r'照片吗\u003f', '%1$s?']:
                with self.subTest(check=check.__module__, value=value):
                    self.assertTrue(check(value))

    def test_accepts_full_width_questions_and_technical_urls(self):
        for check in CHECKS:
            for value in ['也备份以前的 %@ 张照片吗？', '备份 %1$s 张照片吗？',
                          r'照片吗\uFF1F', '帮助：https://example.com/help?topic=photos']:
                with self.subTest(check=check.__module__, value=value):
                    self.assertFalse(check(value))
