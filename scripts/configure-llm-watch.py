#!/usr/bin/env python3
"""Merge llm-watch hooks into Codex and Claude user configuration."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import shlex
import shutil
import stat
import tempfile
from pathlib import Path
from typing import Any, Mapping


def managed_command(command: object) -> bool:
    if not isinstance(command, str):
        return False
    return (
        "llm-watch hook codex" in command
        or "llm-watch hook claude" in command
        or command.rstrip().endswith("llm-watch-codex-stop-hook")
    )


def remove_managed(groups: object) -> list[dict[str, Any]]:
    if not isinstance(groups, list):
        return []
    result: list[dict[str, Any]] = []
    for raw_group in groups:
        if not isinstance(raw_group, dict):
            continue
        group = dict(raw_group)
        handlers = group.get("hooks")
        if not isinstance(handlers, list):
            result.append(group)
            continue
        remaining = [
            handler
            for handler in handlers
            if not (
                isinstance(handler, Mapping)
                and managed_command(handler.get("command"))
            )
        ]
        if remaining:
            group["hooks"] = remaining
            result.append(group)
    return result


def command_group(command: str, timeout: int, matcher: str | None = None) -> dict[str, Any]:
    group: dict[str, Any] = {
        "hooks": [{"type": "command", "command": command, "timeout": timeout}]
    }
    if matcher is not None:
        group["matcher"] = matcher
    return group


def merge_hooks(
    current: dict[str, Any], desired: Mapping[str, dict[str, Any]]
) -> dict[str, Any]:
    result = dict(current)
    hooks = result.get("hooks")
    merged = dict(hooks) if isinstance(hooks, dict) else {}
    for event, group in desired.items():
        existing = remove_managed(merged.get(event))
        existing.append(group)
        merged[event] = existing
    result["hooks"] = merged
    return result


def read_json(path: Path, default: dict[str, Any]) -> dict[str, Any]:
    if not path.exists():
        return dict(default)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"cannot read valid JSON from {path}: {error}") from error
    if not isinstance(value, dict):
        raise RuntimeError(f"expected a JSON object in {path}")
    return value


def backup(path: Path) -> None:
    if not path.exists():
        return
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    destination = path.with_name(f"{path.name}.backup-{stamp}")
    counter = 0
    while destination.exists():
        counter += 1
        destination = path.with_name(f"{path.name}.backup-{stamp}-{counter}")
    shutil.copy2(path, destination)


def atomic_json(path: Path, value: Mapping[str, Any]) -> bool:
    rendered = json.dumps(value, indent=2, sort_keys=False) + "\n"
    if path.exists():
        existing = path.read_text(encoding="utf-8")
        try:
            if json.loads(existing) == value:
                return False
        except json.JSONDecodeError:
            pass
    path.parent.mkdir(parents=True, exist_ok=True)
    existing_mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    backup(path)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(descriptor, existing_mode)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(rendered)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise
    return True


def desired_codex(home: Path) -> dict[str, dict[str, Any]]:
    watcher = shlex.quote(str(home / ".local/bin/llm-watch"))
    stop = shlex.quote(str(home / ".local/bin/llm-watch-codex-stop-hook"))
    command = f"{watcher} hook codex"
    return {
        "UserPromptSubmit": command_group(command, 2),
        "PermissionRequest": command_group(command, 2),
        "SessionStart": command_group(command, 2, "^(startup|resume|clear)$"),
        "SessionEnd": command_group(command, 1),
        "Stop": command_group(stop, 2),
    }


def desired_claude(home: Path) -> dict[str, dict[str, Any]]:
    watcher = shlex.quote(str(home / ".local/bin/llm-watch"))
    command = f"{watcher} hook claude"
    return {
        "UserPromptSubmit": command_group(command, 2),
        "Notification": command_group(command, 2, "permission_prompt"),
        "Stop": command_group(command, 2),
        "StopFailure": command_group(command, 2),
        "SessionStart": command_group(command, 2, "startup|resume|clear"),
        "SessionEnd": command_group(command, 2),
    }


def configure(home: Path) -> tuple[bool, bool]:
    codex_path = home / ".codex/hooks.json"
    claude_path = home / ".claude/settings.json"

    codex = read_json(
        codex_path,
        {"description": "User hooks managed alongside taj-p/dotfiles."},
    )
    claude = read_json(claude_path, {})

    codex_changed = atomic_json(codex_path, merge_hooks(codex, desired_codex(home)))
    claude_changed = atomic_json(
        claude_path, merge_hooks(claude, desired_claude(home))
    )
    return codex_changed, claude_changed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--home", type=Path, default=Path.home())
    args = parser.parse_args()
    try:
        codex_changed, claude_changed = configure(args.home.expanduser().resolve())
    except RuntimeError as error:
        print(f"[llm-watch-config] {error}", file=os.sys.stderr)
        return 1
    codex_status = "updated" if codex_changed else "unchanged"
    claude_status = "updated" if claude_changed else "unchanged"
    print(f"[llm-watch-config] Codex {codex_status}; Claude {claude_status}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
