#!/usr/bin/env python3

"""Dispatch an adversarial Codex PR review to a free Coder devbox."""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import PurePosixPath


PR_URL_RE = re.compile(
    r"^https://github\.com/(?P<owner>[^/]+)/(?P<repo>[^/]+)/pull/(?P<number>[0-9]+)(?:/.*)?$",
    re.IGNORECASE,
)
RESERVED_MARKER = "__DEVBOX_PR_REVIEW_RESERVED__"
SESSION_MARKER = "__DEVBOX_PR_REVIEW_SESSION__="
ACTIVE_PROVIDERS = {"codex", "claude"}


class ReviewError(RuntimeError):
    pass


@dataclass(frozen=True)
class PullRequest:
    url: str
    owner: str
    repo: str
    number: str

    @property
    def slug(self) -> str:
        return f"{self.owner}/{self.repo}"


def parse_pr_url(value: str) -> PullRequest:
    match = PR_URL_RE.match(value)
    if not match:
        raise ReviewError(
            "PR must be a full GitHub URL such as "
            "https://github.com/OWNER/REPO/pull/123"
        )
    return PullRequest(value, **match.groupdict())


def run(
    arguments: list[str], *, timeout: float | None = None, check: bool = False
) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            arguments,
            check=check,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as error:
        raise ReviewError(f"command timed out: {shlex.join(arguments)}") from error
    except OSError as error:
        raise ReviewError(f"could not run {arguments[0]}: {error}") from error


def discover_hosts(explicit_hosts: list[str]) -> list[str]:
    if explicit_hosts:
        return sorted(set(explicit_hosts))
    llm_watch = shutil.which("llm-watch")
    if not llm_watch:
        raise ReviewError("llm-watch is not installed or is not on PATH")
    result = run([llm_watch, "hosts"], timeout=15)
    hosts = sorted({line.strip() for line in result.stdout.splitlines() if line.strip()})
    if not hosts:
        detail = result.stderr.strip() or "no hosts were discovered"
        raise ReviewError(f"llm-watch found no devboxes: {detail}")
    return hosts


def parse_snapshot(output: str) -> dict[str, object]:
    for line in reversed(output.splitlines()):
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict) and isinstance(value.get("runs"), list):
            return value
    raise ReviewError("devbox returned no valid llm-watch snapshot")


def snapshot_is_busy(snapshot: dict[str, object]) -> bool:
    runs = snapshot.get("runs", [])
    assert isinstance(runs, list)
    return any(
        isinstance(item, dict)
        and str(item.get("provider", "")).lower() in ACTIVE_PROVIDERS
        and str(item.get("state", "")).lower() != "stopped"
        for item in runs
    )


def probe_host(host: str, timeout: int) -> tuple[bool, str]:
    command = r'''
state_root=${XDG_STATE_HOME:-"$HOME/.local/state"}/taj-dotfiles
lock_file=$state_root/devbox-pr-review.lock
if command -v flock >/dev/null 2>&1; then
  mkdir -p "$state_root"
  if ! flock -n "$lock_file" true; then
    printf '%s\n' '__DEVBOX_PR_REVIEW_RESERVED__'
  fi
fi
"$HOME/.local/bin/llm-watch" snapshot --events 0
'''.strip()
    result = run(
        [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            f"ConnectTimeout={timeout}",
            host,
            command,
        ],
        timeout=timeout + 3,
    )
    if result.returncode:
        return False, result.stderr.strip() or "SSH or llm-watch failed"
    try:
        snapshot = parse_snapshot(result.stdout)
    except ReviewError as error:
        return False, str(error)
    if RESERVED_MARKER in result.stdout:
        return False, "another dispatched review is starting or running"
    if snapshot_is_busy(snapshot):
        return False, "llm-watch reports an active Codex or Claude session"
    return True, "free"


def normalize_github_origin(origin: str) -> str | None:
    match = re.search(
        r"github\.com(?::|/)(?P<slug>[^\s]+?)(?:\.git)?$", origin.strip(), re.IGNORECASE
    )
    if not match:
        return None
    return match.group("slug").removesuffix(".git").strip("/").lower()


def discover_repo(host: str, pr: PullRequest, timeout: int) -> str:
    command = r'''
find "$HOME" -maxdepth 5 -name .git -prune -print 2>/dev/null |
while IFS= read -r marker; do
  repo=${marker%/.git}
  origin=$(git -C "$repo" remote get-url origin 2>/dev/null || true)
  if [ -n "$origin" ]; then
    printf '%s\t%s\n' "$repo" "$origin"
  fi
done
'''.strip()
    result = run(
        [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            f"ConnectTimeout={timeout}",
            host,
            command,
        ],
        timeout=max(timeout + 5, 15),
    )
    if result.returncode:
        raise ReviewError(result.stderr.strip() or "remote repository discovery failed")
    wanted = pr.slug.lower()
    matches: list[str] = []
    for line in result.stdout.splitlines():
        try:
            path, origin = line.split("\t", 1)
        except ValueError:
            continue
        if normalize_github_origin(origin) == wanted:
            matches.append(path)
    if not matches:
        raise ReviewError(f"no checkout of github.com/{pr.slug} found under the remote home")
    return sorted(matches, key=lambda path: (len(PurePosixPath(path).parts), path))[0]


def remote_launcher(pr: PullRequest, remote_ref: str, repo: str) -> str:
    prompt = (
        f"Use $adversarial-pr-review to review GitHub PR {pr.url}. "
        "Review the entire PR against its actual base, report only actionable findings, "
        "and do not modify the working tree."
    )
    review = "\n".join(
        [
            "set +e",
            'touch "$started_marker"',
            f'"$qco_bin" {shlex.quote(remote_ref)}',
            "status=$?",
            'if [ "$status" -eq 0 ]; then',
            '  "$codex_bin" exec --sandbox read-only --cd '
            + shlex.quote(repo)
            + " "
            + shlex.quote(prompt),
            "  status=$?",
            "fi",
            'exit "$status"',
        ]
    )
    tmux_command = "\n".join(
        [
            "set +e",
            "flock -n \"$lock_file\" sh -c " + shlex.quote(review),
            "status=$?",
            'if [ ! -e "$started_marker" ]; then exit 75; fi',
            'rm -f "$started_marker"',
            "printf '\\nReview command exited with status %s. Press Ctrl-D to close this session.\\n' \"$status\"",
            'exec "${SHELL:-/bin/bash}" -l',
        ]
    )
    script = "\n".join(
        [
            "set -eu",
            'command -v flock >/dev/null 2>&1 || { echo "flock is required" >&2; exit 1; }',
            'command -v tmux >/dev/null 2>&1 || { echo "tmux is required" >&2; exit 1; }',
            'qco_bin=$(command -v qco) || { echo "qco is required" >&2; exit 1; }',
            'codex_bin=$(command -v codex) || { echo "codex is required" >&2; exit 1; }',
            'state_root=${XDG_STATE_HOME:-"$HOME/.local/state"}/taj-dotfiles',
            'mkdir -p "$state_root"',
            'lock_file=$state_root/devbox-pr-review.lock',
            f"repo={shlex.quote(repo)}",
            '[ -d "$repo" ] || { echo "repository does not exist: $repo" >&2; exit 1; }',
            f'session="pr-review-{pr.number}-$(date +%Y%m%d-%H%M%S)-$$"',
            f'started_marker="$state_root/devbox-pr-review-{pr.number}-$$.started"',
            'export state_root lock_file started_marker qco_bin codex_bin',
            'tmux new-session -d -s "$session" -n review -c "$repo" '
            + shlex.quote(tmux_command),
            "attempt=0",
            'while [ "$attempt" -lt 30 ]; do',
            '  if [ -e "$started_marker" ]; then',
            f"    printf '{SESSION_MARKER}%s\\n' \"$session\"",
            "    exit 0",
            "  fi",
            '  tmux has-session -t "$session" 2>/dev/null || exit 75',
            "  attempt=$((attempt + 1))",
            "  sleep 0.1",
            "done",
            'echo "timed out waiting for review session to start" >&2',
            "exit 1",
        ]
    )
    encoded = base64.b64encode(script.encode()).decode()
    return f"printf %s {shlex.quote(encoded)} | base64 --decode | sh"


def launch_review(
    host: str, pr: PullRequest, remote_ref: str, repo: str, timeout: int
) -> tuple[str | None, str]:
    result = run(
        [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            f"ConnectTimeout={timeout}",
            host,
            remote_launcher(pr, remote_ref, repo),
        ],
        timeout=max(timeout + 8, 15),
    )
    if result.returncode == 75:
        return None, "devbox was claimed by another review"
    if result.returncode:
        return None, result.stderr.strip() or "remote launch failed"
    for line in reversed(result.stdout.splitlines()):
        if line.startswith(SESSION_MARKER):
            return line.removeprefix(SESSION_MARKER), "started"
    return None, "remote launcher returned no tmux session name"


def argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run an adversarial Codex PR review on a free devbox."
    )
    parser.add_argument("pr_url", help="full GitHub pull-request URL")
    parser.add_argument("remote_ref", help="branch or remote ref passed to qco")
    parser.add_argument(
        "--host",
        action="append",
        default=[],
        help="candidate SSH alias; repeat to provide more than one",
    )
    parser.add_argument(
        "--repo",
        help="repository directory on the devbox; otherwise inferred from the PR URL",
    )
    parser.add_argument(
        "--timeout", type=int, default=5, help="SSH connection timeout in seconds"
    )
    parser.add_argument(
        "--no-attach", action="store_true", help="start the review without attaching"
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    arguments = argument_parser().parse_args(argv)
    try:
        pr = parse_pr_url(arguments.pr_url)
        hosts = discover_hosts(arguments.host)
        failures: list[str] = []
        for host in hosts:
            free, reason = probe_host(host, arguments.timeout)
            if not free:
                failures.append(f"{host}: {reason}")
                continue
            try:
                repo = arguments.repo or discover_repo(host, pr, arguments.timeout)
            except ReviewError as error:
                failures.append(f"{host}: {error}")
                continue
            session, reason = launch_review(
                host, pr, arguments.remote_ref, repo, arguments.timeout
            )
            if not session:
                failures.append(f"{host}: {reason}")
                continue
            print(f"Review started on {host} in tmux session {session}.")
            print(f"Repository: {repo}")
            if arguments.no_attach:
                print(f"Attach with: ssh -t {shlex.quote(host)} tmux attach -t {shlex.quote(session)}")
                return 0
            os.execvp("ssh", ["ssh", "-t", host, "tmux", "attach", "-t", session])
        detail = "\n  ".join(failures) if failures else "no candidate hosts"
        raise ReviewError(f"no free devbox could start the review:\n  {detail}")
    except ReviewError as error:
        print(f"devbox-pr-review: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
