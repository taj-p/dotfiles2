import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class SyncLlmWatchTests(unittest.TestCase):
    def create_source(self, root: Path) -> Path:
        source = root / "source"
        executable = source / "bin/llm-watch"
        executable.parent.mkdir(parents=True)
        executable.write_text("#!/usr/bin/env sh\nexit 0\n")
        executable.chmod(executable.stat().st_mode | stat.S_IXUSR)
        subprocess.run(
            ["git", "init", "-b", "main", source], check=True, capture_output=True
        )
        subprocess.run(["git", "-C", source, "add", "."], check=True)
        subprocess.run(
            [
                "git",
                "-C",
                source,
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@example.com",
                "commit",
                "-m",
                "fixture",
            ],
            check=True,
            capture_output=True,
        )
        return source

    def test_clone_link_configure_and_repeat(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self.create_source(root)
            home = root / "home"

            libexec = home / ".local/libexec/taj-dotfiles"
            libexec.mkdir(parents=True)
            configurer = libexec / "configure-llm-watch.py"
            configurer.write_bytes((ROOT / "scripts/configure-llm-watch.py").read_bytes())
            configurer.chmod(0o755)

            environment = dict(os.environ)
            environment.update(
                {
                    "HOME": str(home),
                    "LLM_WATCH_REPO": str(source),
                    "LLM_WATCH_REPO_DIR": str(home / ".local/share/llm-watch"),
                    "LLM_WATCH_SYNC_INTERVAL_SECONDS": "0",
                }
            )
            command = ["bash", str(ROOT / "scripts/sync-llm-watch.sh")]
            subprocess.run(command, env=environment, check=True, capture_output=True)
            subprocess.run(command, env=environment, check=True, capture_output=True)

            link = home / ".local/bin/llm-watch"
            self.assertTrue(link.is_symlink())
            expected = home / ".local/share/llm-watch/bin/llm-watch"
            self.assertEqual(link.resolve(), expected.resolve())
            codex = json.loads((home / ".codex/hooks.json").read_text())
            claude = json.loads((home / ".claude/settings.json").read_text())
            self.assertIn("Stop", codex["hooks"])
            self.assertIn("Stop", claude["hooks"])

    def test_self_update_installs_llm_watch_immediately(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self.create_source(root)
            home = root / "home"
            local_bin = home / ".local/bin"
            local_bin.mkdir(parents=True)
            for name in ("difit", "zoxide", "lsd", "bat"):
                stub = local_bin / name
                stub.write_text("#!/usr/bin/env sh\nexit 0\n")
                stub.chmod(0o755)

            environment = dict(os.environ)
            environment.update(
                {
                    "HOME": str(home),
                    "PATH": f"{local_bin}:{environment['PATH']}",
                    "DOTFILES_SELF_UPDATE": "1",
                    "LLM_WATCH_REPO": str(source),
                    "LLM_WATCH_REPO_DIR": str(home / ".local/share/llm-watch"),
                }
            )
            subprocess.run(
                [
                    "bash",
                    str(ROOT / "install.sh"),
                    "--skip-packages",
                    "--skip-nvim-init",
                    "--no-scheduler",
                ],
                env=environment,
                check=True,
                capture_output=True,
            )

            self.assertTrue((home / ".local/bin/llm-watch").is_symlink())
            self.assertTrue((home / ".codex/hooks.json").exists())
            self.assertTrue((home / ".claude/settings.json").exists())


if __name__ == "__main__":
    unittest.main()
