# Managed by taj-p/dotfiles. This file is safe to source from Bash and Zsh.

if [ -d /opt/homebrew/bin ]; then
  case ":$PATH:" in
    *":/opt/homebrew/bin:"*) ;;
    *) export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH" ;;
  esac
fi

if [ -d "$HOME/.cargo/bin" ]; then
  case ":$PATH:" in
    *":$HOME/.cargo/bin:"*) ;;
    *) export PATH="$HOME/.cargo/bin:$PATH" ;;
  esac
fi

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

export EDITOR=nvim
export VISUAL=nvim

alias lg='lazygit'
alias g='git'
alias gaf='git commit --amend --no-edit && g push --force'
alias ls='lsd'
alias bur='bazel fetch --repo=@crate_index \
  --repo_env=GITHUB_TOKEN="$(gh auth token)" \
  --repo_env=GIT_ASKPASS="$GIT_ASKPASS" \
  --repo_env=CODER_AGENT_URL="$CODER_AGENT_URL" \
  --repo_env=CODER_AGENT_TOKEN="$CODER_AGENT_TOKEN" \
  --repo_env=CARGO_BAZEL_REPIN=1 \
  --repo_env=CARGO_BAZEL_REPIN_ONLY=crate_index'

# Restrict origin to useful branches and remove other cached remote-tracking refs.
rgr() {
  python3 - <<'PY'
import subprocess


def lines(*args):
    return subprocess.run(
        args,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.splitlines()


subprocess.run(
    ["git", "rev-parse", "--is-inside-work-tree"],
    capture_output=True,
    check=True,
)

upstream_refs = {
    ref
    for ref in lines(
        "git", "for-each-ref", "--format=%(upstream)", "refs/heads"
    )
    if ref.startswith("refs/remotes/origin/")
}
upstream_branches = {
    ref.removeprefix("refs/remotes/origin/") for ref in upstream_refs
}
available = {
    line.split("\t", 1)[1].removeprefix("refs/heads/")
    for line in lines("git", "ls-remote", "--heads", "origin")
}
extras = sorted(
    branch
    for branch in upstream_branches & available
    if branch != "master" and not branch.startswith("tajp/")
)

subprocess.run(
    [
        "git", "remote", "set-branches", "origin",
        "master", "tajp/*", *extras,
    ],
    check=True,
)

commands = ["start\n"]
deleted = 0
for line in lines(
    "git", "for-each-ref",
    "--format=%(refname)%09%(objectname)%09%(symref)",
    "refs/remotes/origin",
):
    name, oid, symref = line.split("\t")
    keep = (
        name in {
            "refs/remotes/origin/HEAD",
            "refs/remotes/origin/master",
        }
        or name.startswith("refs/remotes/origin/tajp/")
        or name in upstream_refs
    )
    if not keep:
        if symref:
            raise RuntimeError(f"Unexpected symbolic ref: {name}")
        commands.append(f"delete {name} {oid}\n")
        deleted += 1

commands += ["prepare\n", "commit\n"]
subprocess.run(
    ["git", "update-ref", "--stdin", "--no-deref"],
    input="".join(commands),
    text=True,
    check=True,
)
subprocess.run(["git", "fetch", "--dry-run", "origin"], check=True)
print(f"rgr: removed {deleted} cached origin refs; dry-run fetch succeeded")
PY
}

if command -v zoxide >/dev/null 2>&1; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval "$(zoxide init zsh --cmd z)"
  elif [ -n "${BASH_VERSION:-}" ]; then
    eval "$(zoxide init bash --cmd z)"
  fi
fi

# Coder containers often have no user systemd session. Keep exactly one small
# updater loop alive as a fallback; the loop uses a per-user directory lock.
if [ "$(uname -s 2>/dev/null)" = Linux ] && [ -x "$HOME/.local/bin/dotfiles-settings-sync-loop" ]; then
  if ! systemctl --user is-active --quiet dotfiles-settings-sync.timer 2>/dev/null; then
    nohup "$HOME/.local/bin/dotfiles-settings-sync-loop" \
      >>"$HOME/.local/state/taj-dotfiles/settings-sync-loop.log" 2>&1 &
  fi
fi
