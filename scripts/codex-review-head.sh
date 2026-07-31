#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: crh [base-ref]

Review HEAD before pushing it. Codex reviews defects introduced by HEAD while
using the full branch diff against the pull request's base as context.

If base-ref is omitted, crh uses the current GitHub pull request's base when
available, then falls back to origin's default branch, origin/main, or
origin/master.
EOF
}

if [[ $# -gt 1 || ${1:-} == -h || ${1:-} == --help ]]; then
  usage
  if [[ $# -le 1 && (${1:-} == -h || ${1:-} == --help) ]]; then
    exit 0
  fi
  exit 2
fi

if ! command -v git >/dev/null 2>&1; then
  printf 'crh: git is not on PATH\n' >&2
  exit 1
fi
if ! command -v codex >/dev/null 2>&1; then
  printf 'crh: codex is not on PATH\n' >&2
  exit 1
fi

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'crh: run this command inside a Git repository\n' >&2
  exit 1
}
cd "$repo_root"

head_sha=$(git rev-parse --verify HEAD)
parent_sha=$(git rev-parse --verify HEAD^ 2>/dev/null) || {
  printf 'crh: HEAD has no parent commit to review against\n' >&2
  exit 1
}

resolve_base_ref() {
  local candidate=$1

  if git rev-parse --verify --quiet "refs/remotes/origin/$candidate^{commit}" >/dev/null; then
    printf 'origin/%s\n' "$candidate"
  elif git rev-parse --verify --quiet "$candidate^{commit}" >/dev/null; then
    printf '%s\n' "$candidate"
  else
    return 1
  fi
}

base_ref=
if [[ $# -eq 1 ]]; then
  base_ref=$(resolve_base_ref "$1") || {
    printf "crh: base ref '%s' does not resolve to a commit\n" "$1" >&2
    exit 1
  }
else
  if command -v gh >/dev/null 2>&1; then
    pr_base=$(gh pr view --json baseRefName --jq .baseRefName 2>/dev/null || true)
    if [[ -n $pr_base ]]; then
      base_ref=$(resolve_base_ref "$pr_base" || true)
    fi
  fi

  if [[ -z $base_ref ]]; then
    origin_head=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
    if [[ -n $origin_head ]] && git rev-parse --verify --quiet "$origin_head^{commit}" >/dev/null; then
      base_ref=$origin_head
    elif git rev-parse --verify --quiet 'refs/remotes/origin/main^{commit}' >/dev/null; then
      base_ref=origin/main
    elif git rev-parse --verify --quiet 'refs/remotes/origin/master^{commit}' >/dev/null; then
      base_ref=origin/master
    fi
  fi

  if [[ -z $base_ref ]]; then
    printf 'crh: could not determine the PR base; pass it explicitly (for example, crh main)\n' >&2
    exit 1
  fi
fi

merge_base=$(git merge-base "$base_ref" "$head_sha") || {
  printf "crh: '%s' and HEAD do not have a merge base\n" "$base_ref" >&2
  exit 1
}
short_sha=$(git rev-parse --short "$head_sha")
subject=$(git log -1 --format=%s "$head_sha")

printf "crh: reviewing HEAD %s against PR base %s\n" "$short_sha" "$base_ref" >&2

prompt=$(cat <<EOF
Review commit $head_sha ("$subject") before it is pushed.

Review target:
- Report only actionable defects introduced by $head_sha.
- The target diff is $parent_sha..$head_sha.

Pull request context:
- The PR base ref is $base_ref and its merge base with HEAD is $merge_base.
- Inspect the entire $merge_base..$head_sha branch diff, relevant surrounding
  code, tests, and history when that context is needed to judge the target.
- Do not report pre-existing problems or problems introduced only by earlier
  commits on the branch, unless this commit makes them materially worse.
- Evaluate the repository as it exists at $head_sha. Ignore staged, unstaged,
  and untracked working-tree changes.

Prioritize correctness, security, data loss, concurrency, and behavioral
regressions. Keep findings concise, cite exact file and line locations, and do
not modify the working tree. If there are no findings, say so explicitly.
EOF
)

codex review "$prompt"
