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

    def create_rust_source(self, root: Path) -> Path:
        source = root / "rust-source"
        (source / "src").mkdir(parents=True)
        (source / "Cargo.toml").write_text(
            '[package]\nname = "llm-watch"\nversion = "0.2.0"\nedition = "2021"\n'
        )
        (source / "Cargo.lock").write_text("# fixture\n")
        (source / "src/main.rs").write_text("fn main() {}\n")
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

    def install_configurer(self, home: Path) -> None:
        libexec = home / ".local/libexec/taj-dotfiles"
        libexec.mkdir(parents=True)
        configurer = libexec / "configure-llm-watch.py"
        configurer.write_bytes((ROOT / "scripts/configure-llm-watch.py").read_bytes())
        configurer.chmod(0o755)

    def test_clone_link_configure_and_repeat(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self.create_source(root)
            home = root / "home"

            self.install_configurer(home)

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

    def test_rust_release_is_built_before_linking(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self.create_rust_source(root)
            home = root / "home"
            self.install_configurer(home)
            cargo = home / ".cargo/bin/cargo"
            cargo.parent.mkdir(parents=True)
            cargo.write_text(
                "#!/usr/bin/env sh\n"
                "while [ $# -gt 0 ]; do\n"
                "  if [ \"$1\" = --manifest-path ]; then manifest=$2; shift 2; else shift; fi\n"
                "done\n"
                "repo=${manifest%/Cargo.toml}\n"
                "mkdir -p \"$repo/target/release\"\n"
                "printf '#!/usr/bin/env sh\\nexit 0\\n' >\"$repo/target/release/llm-watch\"\n"
                "chmod 755 \"$repo/target/release/llm-watch\"\n"
            )
            cargo.chmod(0o755)

            environment = dict(os.environ)
            environment.update(
                {
                    "HOME": str(home),
                    "PATH": f"{cargo.parent}:{environment['PATH']}",
                    "LLM_WATCH_REPO": str(source),
                    "LLM_WATCH_REPO_DIR": str(home / ".local/share/llm-watch"),
                }
            )
            subprocess.run(
                ["bash", str(ROOT / "scripts/sync-llm-watch.sh")],
                env=environment,
                check=True,
                capture_output=True,
            )

            link = home / ".local/bin/llm-watch"
            expected = home / ".local/share/llm-watch/target/release/llm-watch"
            self.assertEqual(link.resolve(), expected.resolve())

    def test_self_update_installs_llm_watch_immediately(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self.create_source(root)
            choochoo_source = root / "choochoo-source"
            (choochoo_source / "src").mkdir(parents=True)
            (choochoo_source / "Cargo.toml").write_text(
                '[package]\nname = "choochoo"\nversion = "0.1.0"\nedition = "2021"\n'
                '[[bin]]\nname = "choo"\npath = "src/main.rs"\n'
            )
            (choochoo_source / "Cargo.lock").write_text("# fixture\n")
            (choochoo_source / "src/main.rs").write_text("fn main() {}\n")
            subprocess.run(
                ["git", "init", "-b", "main", choochoo_source],
                check=True,
                capture_output=True,
            )
            subprocess.run(["git", "-C", choochoo_source, "add", "."], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    choochoo_source,
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
            home = root / "home"
            local_bin = home / ".local/bin"
            local_bin.mkdir(parents=True)
            for name in ("difit", "zoxide", "lsd", "bat", "mergiraf"):
                stub = local_bin / name
                stub.write_text("#!/usr/bin/env sh\nexit 0\n")
                stub.chmod(0o755)
            cargo = home / ".cargo/bin/cargo"
            cargo.parent.mkdir(parents=True)
            cargo.write_text(
                "#!/usr/bin/env sh\n"
                "while [ $# -gt 0 ]; do\n"
                '  if [ "$1" = --manifest-path ]; then manifest=$2; shift 2; else shift; fi\n'
                "done\n"
                "repo=${manifest%/Cargo.toml}\n"
                'mkdir -p "$repo/target/release"\n'
                "printf '#!/usr/bin/env sh\\nexit 0\\n' >\"$repo/target/release/choo\"\n"
                'chmod 755 "$repo/target/release/choo"\n'
            )
            cargo.chmod(0o755)

            environment = dict(os.environ)
            environment.update(
                {
                    "HOME": str(home),
                    "PATH": f"{cargo.parent}:{local_bin}:{environment['PATH']}",
                    "DOTFILES_SELF_UPDATE": "1",
                    "LLM_WATCH_REPO": str(source),
                    "LLM_WATCH_REPO_DIR": str(home / ".local/share/llm-watch"),
                    "CHOOCHOO_REPO": str(choochoo_source),
                    "CHOOCHOO_REPO_DIR": str(home / ".local/share/choochoo"),
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
            self.assertTrue((home / ".local/bin/choo").is_symlink())
            choochoo_config = home / ".config/choochoo/config.toml"
            self.assertTrue(choochoo_config.is_symlink())
            self.assertIn(
                "git@github.com:taj-p/choochoo-config.git",
                choochoo_config.read_text(),
            )
            self.assertIn(
                '[repo."https://github.com/Canva/canva"]\nbase = "master"',
                choochoo_config.read_text(),
            )
            self.assertTrue((home / ".codex/hooks.json").exists())
            self.assertTrue((home / ".claude/settings.json").exists())
            self.assertTrue(
                (home / ".agents/skills/adversarial-pr-review").is_symlink()
            )
            self.assertTrue(
                (home / ".claude/skills/adversarial-pr-review").is_symlink()
            )


if __name__ == "__main__":
    unittest.main()
