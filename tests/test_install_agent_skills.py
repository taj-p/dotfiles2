import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/install-agent-skills.sh"
SKILL = ROOT / "agent-skills/adversarial-pr-review"


class InstallAgentSkillsTests(unittest.TestCase):
    def run_installer(self, home: Path) -> subprocess.CompletedProcess[str]:
        environment = dict(os.environ)
        environment["HOME"] = str(home)
        return subprocess.run(
            ["bash", str(SCRIPT)],
            env=environment,
            check=True,
            capture_output=True,
            text=True,
        )

    def test_installs_codex_and_claude_links_idempotently(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)

            self.run_installer(home)
            self.run_installer(home)

            for target in (
                home / ".agents/skills/adversarial-pr-review",
                home / ".claude/skills/adversarial-pr-review",
            ):
                self.assertTrue(target.is_symlink())
                self.assertEqual(target.resolve(), SKILL.resolve())
                self.assertEqual(list(target.parent.glob(f"{target.name}.backup-*")), [])

    def test_backs_up_an_existing_skill_before_linking(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            existing = home / ".claude/skills/adversarial-pr-review"
            existing.mkdir(parents=True)
            (existing / "SKILL.md").write_text("existing skill\n")

            self.run_installer(home)

            self.assertTrue(existing.is_symlink())
            backups = list(existing.parent.glob(f"{existing.name}.backup-*"))
            self.assertEqual(len(backups), 1)
            self.assertEqual((backups[0] / "SKILL.md").read_text(), "existing skill\n")


if __name__ == "__main__":
    unittest.main()
