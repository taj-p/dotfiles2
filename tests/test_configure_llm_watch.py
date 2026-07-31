import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/configure-llm-watch.py"
SPEC = importlib.util.spec_from_file_location("configure_llm_watch", SCRIPT)
assert SPEC and SPEC.loader
configure_llm_watch = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(configure_llm_watch)


class ConfigureHooksTests(unittest.TestCase):
    def test_merge_preserves_existing_hooks_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            codex_path = home / ".codex/hooks.json"
            claude_path = home / ".claude/settings.json"
            codex_path.parent.mkdir()
            claude_path.parent.mkdir()
            codex_path.write_text(
                json.dumps(
                    {
                        "description": "existing",
                        "hooks": {
                            "Stop": [
                                {
                                    "hooks": [
                                        {
                                            "type": "command",
                                            "command": "/usr/bin/existing-codex-hook",
                                        }
                                    ]
                                }
                            ]
                        },
                    }
                )
            )
            claude_path.write_text(
                json.dumps(
                    {
                        "theme": "dark",
                        "hooks": {
                            "Stop": [
                                {
                                    "hooks": [
                                        {
                                            "type": "command",
                                            "command": "/usr/local/bin/otter agent-hook",
                                        }
                                    ]
                                }
                            ]
                        },
                    }
                )
            )

            first = configure_llm_watch.configure(home)
            second = configure_llm_watch.configure(home)

            self.assertEqual(first, (True, True))
            self.assertEqual(second, (False, False))
            codex = json.loads(codex_path.read_text())
            claude = json.loads(claude_path.read_text())
            self.assertEqual(codex["description"], "existing")
            self.assertEqual(claude["theme"], "dark")

            codex_stop = [
                hook["command"]
                for group in codex["hooks"]["Stop"]
                for hook in group["hooks"]
            ]
            claude_stop = [
                hook["command"]
                for group in claude["hooks"]["Stop"]
                for hook in group["hooks"]
            ]
            self.assertIn("/usr/bin/existing-codex-hook", codex_stop)
            self.assertTrue(
                any(command.endswith("llm-watch-codex-stop-hook") for command in codex_stop)
            )
            self.assertIn("/usr/local/bin/otter agent-hook", claude_stop)
            self.assertTrue(
                any("llm-watch hook claude" in command for command in claude_stop)
            )
            self.assertEqual(len(list(codex_path.parent.glob("hooks.json.backup-*"))), 1)
            self.assertEqual(len(list(claude_path.parent.glob("settings.json.backup-*"))), 1)

    def test_invalid_json_is_left_untouched(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            path = home / ".claude/settings.json"
            path.parent.mkdir(parents=True)
            path.write_text("not json\n")

            with self.assertRaises(RuntimeError):
                configure_llm_watch.configure(home)

            self.assertEqual(path.read_text(), "not json\n")


if __name__ == "__main__":
    unittest.main()
