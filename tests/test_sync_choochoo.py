import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class SyncChoochooTests(unittest.TestCase):
    def create_source(self, root: Path) -> Path:
        source = root / "source"
        (source / "src").mkdir(parents=True)
        (source / "Cargo.toml").write_text(
            '[package]\nname = "choochoo"\nversion = "0.1.0"\nedition = "2021"\n'
            '[[bin]]\nname = "choo"\npath = "src/main.rs"\n'
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

    def install_fake_cargo(self, home: Path) -> Path:
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
        return cargo

    def test_clone_build_link_and_repeat(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self.create_source(root)
            home = root / "home"
            cargo = self.install_fake_cargo(home)

            environment = dict(os.environ)
            environment.update(
                {
                    "HOME": str(home),
                    "PATH": f"{cargo.parent}:{environment['PATH']}",
                    "CHOOCHOO_REPO": str(source),
                    "CHOOCHOO_REPO_DIR": str(home / ".local/share/choochoo"),
                    "CHOOCHOO_SYNC_INTERVAL_SECONDS": "0",
                }
            )
            command = ["bash", str(ROOT / "scripts/sync-choochoo.sh")]
            subprocess.run(command, env=environment, check=True, capture_output=True)
            subprocess.run(command, env=environment, check=True, capture_output=True)

            link = home / ".local/bin/choo"
            expected = home / ".local/share/choochoo/target/release/choo"
            self.assertTrue(link.is_symlink())
            self.assertEqual(link.resolve(), expected.resolve())

    def test_refuses_to_replace_an_existing_command(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self.create_source(root)
            home = root / "home"
            cargo = self.install_fake_cargo(home)
            link = home / ".local/bin/choo"
            link.parent.mkdir(parents=True)
            link.write_text("keep me\n")

            environment = dict(os.environ)
            environment.update(
                {
                    "HOME": str(home),
                    "PATH": f"{cargo.parent}:{environment['PATH']}",
                    "CHOOCHOO_REPO": str(source),
                    "CHOOCHOO_REPO_DIR": str(home / ".local/share/choochoo"),
                }
            )
            result = subprocess.run(
                ["bash", str(ROOT / "scripts/sync-choochoo.sh")],
                env=environment,
                capture_output=True,
                text=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Refusing to replace existing path", result.stderr)
            self.assertEqual(link.read_text(), "keep me\n")


if __name__ == "__main__":
    unittest.main()
