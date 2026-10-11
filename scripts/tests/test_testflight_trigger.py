"""Distribution guards, exercised without network calls or release mutations."""
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "testflight_trigger", Path(__file__).parents[1] / "trigger-testflight.py")
trigger = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trigger)


class ReleaseMarkerTests(unittest.TestCase):
    def setUp(self):
        self.fixture = tempfile.TemporaryDirectory()
        self.addCleanup(self.fixture.cleanup)
        metadata = Path(self.fixture.name) / "release.json"
        metadata.write_text(json.dumps({"version": "0.3.1"}))
        self.metadata = metadata
        self.environment = patch.dict(os.environ, {
            "GITHUB_REPOSITORY": "example/backupduck", "TESTED_SHA": "tested",
            "GITHUB_STEP_SUMMARY": str(Path(self.fixture.name) / "summary.md"),
        })
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def run_trigger(self, responses):
        with patch.object(trigger, "api", side_effect=responses) as api, \
                patch.object(trigger, "Path", return_value=self.metadata):
            trigger.main()
        return api

    def test_new_version_marks_exact_tested_commit(self):
        api = self.run_trigger([{"object": {"sha": "tested"}}, [], {}])
        self.assertEqual(api.call_args.args, (
            "repos/example/backupduck/git/refs", "--method", "POST",
            "-f", "ref=refs/tags/testflight/v0.3.1", "-f", "sha=tested"))

    def test_newer_main_prevents_distribution_of_old_test_result(self):
        api = self.run_trigger([{"object": {"sha": "newer"}}])
        self.assertEqual(api.call_count, 1)

    def test_existing_version_never_moves_marker_or_restarts_cloud(self):
        api = self.run_trigger([{"object": {"sha": "tested"}},
                                [{"ref": "refs/tags/testflight/v0.3.1"}]])
        self.assertEqual(api.call_count, 2)

    def test_failed_tag_lookup_does_not_publish(self):
        with self.assertRaises(RuntimeError):
            self.run_trigger([{"object": {"sha": "tested"}},
                              RuntimeError("Tag service unavailable")])


if __name__ == "__main__":
    unittest.main()
