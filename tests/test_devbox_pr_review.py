import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts" / "devbox-pr-review.py"
SPEC = importlib.util.spec_from_file_location("devbox_pr_review", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class DevboxPrReviewTests(unittest.TestCase):
    def test_parses_github_pr(self):
        pr = MODULE.parse_pr_url("https://github.com/Canva/canva/pull/123")
        self.assertEqual(pr.slug, "Canva/canva")
        self.assertEqual(pr.number, "123")

    def test_rejects_non_pr_url(self):
        with self.assertRaises(MODULE.ReviewError):
            MODULE.parse_pr_url("https://example.com/not-a-pr")

    def test_snapshot_busy_only_for_live_codex_or_claude(self):
        self.assertTrue(
            MODULE.snapshot_is_busy(
                {"runs": [{"provider": "codex", "state": "ready"}]}
            )
        )
        self.assertFalse(
            MODULE.snapshot_is_busy(
                {"runs": [{"provider": "claude", "state": "stopped"}]}
            )
        )
        self.assertFalse(
            MODULE.snapshot_is_busy(
                {"runs": [{"provider": "something-else", "state": "running"}]}
            )
        )

    def test_parses_snapshot_after_ssh_banner(self):
        snapshot = MODULE.parse_snapshot(
            'Welcome to the devbox\n{"host":"dev2","runs":[]}\n'
        )
        self.assertEqual(snapshot["host"], "dev2")

    def test_normalizes_https_and_ssh_origins(self):
        self.assertEqual(
            MODULE.normalize_github_origin("git@github.com:Canva/canva.git"),
            "canva/canva",
        )
        self.assertEqual(
            MODULE.normalize_github_origin("https://github.com/Canva/canva.git"),
            "canva/canva",
        )

    def test_remote_launcher_does_not_interpolate_branch_as_shell(self):
        pr = MODULE.parse_pr_url("https://github.com/Canva/canva/pull/123")
        command = MODULE.remote_launcher(pr, "branch; touch /tmp/bad", "/home/coder/repo")
        self.assertIn("base64 --decode", command)
        self.assertNotIn("touch /tmp/bad", command)


if __name__ == "__main__":
    unittest.main()
