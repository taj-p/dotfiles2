# taj-p dotfiles

Cross-platform development environment bootstrap for:

- macOS (Intel or Apple Silicon)
- Ubuntu 22.04 (x86-64 or ARM64), including Coder workspaces/devboxes

The installer sets up Neovim, the AstroNvim prerequisites, useful optional
AstroNvim terminal tools, and
[`taj-p/nvim_config`](https://github.com/taj-p/nvim_config). The Neovim config
is checked for fast-forward updates every 10 minutes. It also installs tmux and
the settings from `git@github.com:taj-p/.tmux.git`, which are updated on the
same schedule. The dotfiles checkout itself is also fast-forwarded on that
schedule, and updates are applied automatically with a lightweight reinstall.
It also installs [`taj-p/llm-watch`](https://github.com/taj-p/llm-watch), keeps
it updated on that schedule, and merges its Codex and Claude lifecycle hooks
without replacing other configured hooks.
It installs [`taj-p/choochoo`](https://github.com/taj-p/choochoo) as `choo`
and keeps it updated on the same schedule.

## Install

Clone this repository and run:

```sh
./install.sh
```

Coder recognizes the executable `install.sh` automatically. Set this
repository's URL as your Coder dotfiles URL; no separate startup command is
needed.

The installer is idempotent. It can be run again to repair or update the
setup. Existing `~/.config/nvim` content that is not the expected Git checkout
is moved to a timestamped backup before the config is installed. Existing tmux
config files are handled the same way.

### Options

```text
--skip-packages   Do not install or upgrade command-line tools
--skip-nvim-init  Do not run the initial headless Neovim plugin install
--no-scheduler    Do not install the 10-minute config update service
-h, --help        Show help
```

The equivalent environment switches are `DOTFILES_SKIP_PACKAGES=1`,
`DOTFILES_SKIP_NVIM_INIT=1`, and `DOTFILES_NO_SCHEDULER=1`.

## What is installed

On macOS, packages come from Homebrew. On Ubuntu, base packages come from APT,
while Neovim, lazygit, an Ubuntu-compatible Tree-sitter CLI, bottom, and gdu
binaries are installed under `~/.local` from their official release artifacts.
This avoids Ubuntu 22.04's old Neovim package and incompatible newer
Tree-sitter binaries.

- Neovim stable (AstroNvim currently requires 0.11 or newer)
- tmux with `taj-p/.tmux` (Oh My Tmux plus the committed local settings)
- ripgrep, fd, and lazygit
- Tree-sitter CLI and a C compiler/toolchain
- Git, curl, unzip, and a system clipboard provider
- Node.js, npm, Python, and Go for LSPs and AstroNvim terminal integrations
- bottom (`btm`) and go DiskUsage (`gdu`)
- `difit`, installed with npm under `~/.local`
- zoxide (`z`), lsd (`ls`), bat, and Mergiraf
- `gh-dash`, installed as a GitHub CLI extension when `gh` is available
- `llm-watch`, installed from `taj-p/llm-watch` for cross-devbox agent status
  and completion notifications
- `choochoo` (`choo`), installed from `taj-p/choochoo` for managing stacked
  GitHub pull-request trains
- Shared personal Codex and Claude skills from `agent-skills/`
- LazyGit configuration with automatic background fetching disabled
- JetBrainsMono Nerd Font on macOS (the font belongs on the local terminal, not
  the remote devbox)
- A managed WezTerm startup layout on macOS with a local `bl` tmux session and
  persistent tmux sessions on the configured Coder devboxes

The installer also adds `~/.local/bin` to `PATH` and sets `EDITOR`/`VISUAL` to
`nvim` through a small managed fragment sourced by both Bash and Zsh. It also
provides `g` and `lg` as short aliases for `git` and `lazygit`, initializes
zoxide as `z`, and aliases `ls` to `lsd`.

Run `dotfiles-packages` for a quick reminder of every managed package, its
command name, and what it is used for.

### Mergiraf

[Mergiraf](https://mergiraf.org/) is installed for syntax-aware Git conflict
resolution. The installer also sets Git's global conflict style to `diff3`, so
Mergiraf can reconstruct the base revision. It is deliberately not registered
as the default merge driver: use it after Git reports a conflict, then review
the result before staging it.

```sh
git merge <branch>
git diff --name-only --diff-filter=U
mergiraf solve path/to/conflicted-file
git diff
git add path/to/conflicted-file
git merge --continue
```

Run `mergiraf solve` once for each supported conflicted file. If it cannot
resolve a conflict safely, it leaves conflict markers for manual resolution.
After using it, run the project's formatter and tests before continuing.

For a repository where Mergiraf has proven reliable, it can be enabled as the
automatic merge driver without changing global attributes:

```sh
git config merge.mergiraf.name mergiraf
git config merge.mergiraf.driver \
  'mergiraf merge --git %O %A %B -s %S -x %X -y %Y -p %P -l %L'
printf '* merge=mergiraf\n' >> .git/info/attributes
```

Review syntax-aware automatic resolutions with `mergiraf review <merge-id>`;
Git prints the merge ID when Mergiraf resolves a conflict. Temporarily bypass
an enabled driver with `mergiraf=0 git merge <branch>`.

Use `qco <remote-ref>` for a quick detached checkout. It runs
`git fetch origin <remote-ref>` followed by `git checkout FETCH_HEAD`.

Use `crh` before pushing a commit to have Codex review defects introduced by
`HEAD` while using the full pull-request diff for context. It discovers the
base branch from the current GitHub pull request when possible, then falls back
to the origin default branch. Pass a base explicitly when needed:

```sh
crh
crh main
```

The long command name is `codex-review-head`. It requires an authenticated
Codex CLI. GitHub CLI authentication is optional, but lets `crh` discover the
base branch of an existing pull request.

Use `dpr <PR-URL> <remote-ref>` on the laptop to find a reachable devbox with
no active Codex or Claude session, check out the ref with `qco`, and run the
shared `adversarial-pr-review` skill through `codex exec` in a new tmux session.
For example:

```sh
dpr https://github.com/Canva/canva/pull/12345 my-feature-branch
```

The matching GitHub checkout is discovered beneath the remote home directory.
Use `--repo /path/to/checkout` to select it explicitly, `--host coder.dev2` to
restrict candidate devboxes, or `--no-attach` to leave the review running in
the background. A per-devbox advisory lock prevents simultaneous dispatchers
from claiming the same machine before its Codex session appears in `llm-watch`.

Use the shared `adversarial-pr-review` skill to review the entire current pull
request for subtle correctness, security, data-loss, concurrency, compatibility,
and regression risks. Invoke it with `$adversarial-pr-review` in Codex or
`/adversarial-pr-review` in Claude Code.

Canonical skills live under `agent-skills/`. The installer symlinks each skill
into both `~/.agents/skills` and `~/.claude/skills`, backing up an existing path
before replacing it. This keeps one prompt definition in `dotfiles2` while
making it available across repositories to both tools.

Run `llm-watch dashboard` on the laptop to poll running Coder workspaces whose
names start with `dev`. On every machine, managed hooks write Codex and Claude
state beneath `~/.local/state/llm-watch`. Hook configuration is merged into
`~/.codex/hooks.json` and `~/.claude/settings.json`; existing unrelated hooks
are retained and an existing file is backed up before its first change.

Codex requires a one-time trust review for user command hooks. After the first
dotfiles update that installs llm-watch, open `/hooks` in Codex and trust the
llm-watch entries. The managed Codex `Stop` adapter emits the JSON response
Codex expects and deliberately leaves any existing `notify` command untouched.

On macOS, WezTerm starts with five tabs. The first reuses a local tmux session
that is already editing `~/bl/tasks.md`, or creates a session named `bl` with a
`tasks` window for that file and a `server` window running
`~/repos/backlog/target/release/bl start` from `~/bl`. The remaining tabs
connect to `coder.dev2`, `coder.dev3`, `coder.lsr-dash`, and `coder.dev-eu`.
Each SSH connection attaches to, or creates, a remote tmux session named `main`,
so its processes survive SSH and WezTerm restarts. The managed configuration is
linked at `~/.config/wezterm/wezterm.lua`; a conflicting file is backed up on
first installation.

The `dfh` command starts difit in the background, passes through any difit
arguments, and connects it through `infra highway http`. Highway's tunnel cache
reuses the same hostname so difit's browser-local state remains available
between runs. For example:

```sh
dfh working --include-untracked
dfh HEAD~3
dfh https://github.com/Canva/canva/pull/123456
```

GitHub pull-request URLs are automatically passed to difit's `--pr` option;
both the main PR URL and its `/changes` URL are accepted. Pressing Ctrl+C stops
both the Highway tunnel and the local difit server.

When `llm-watch` is installed, `dfh` also publishes its tunnel URL to the
llm-watch web dashboard, so the difit page for each devbox is one click away
instead of something to hunt for in a terminal. The URL is printed as
`difit-highway: dashboard link <url>` and republished on a heartbeat while the
tunnel runs; it is withdrawn when `dfh` exits, and expires on its own if `dfh`
is killed. Publishing is best-effort — if `llm-watch` is missing or the URL
cannot be detected, `dfh` behaves exactly as before.

The `dfh-train` command reviews a whole [choochoo](https://github.com/taj-p/choochoo)
train behind a single URL. It reads `choo show --json`, starts one difit per
branch showing that branch against its parent — plus one for the combined
branch, if the train has one — and fronts them all with a small router, so only
one Highway tunnel is involved and reviewers already allowed onto that hostname
need no further access:

```sh
dfh-train             # the active train
dfh-train flat-text   # a train by name
```

The printed URL ends in `/_train`, an index of every branch in stack order.
Every difit page also carries a bar in its bottom-left corner for stepping to
the previous or next branch, so a train can be read straight through. Review
comments are kept separately per branch. A branch difit refuses — one that
isn't checked out locally, say — is reported on the index page and the rest of
the train stays usable. Pressing Ctrl+C stops the tunnel, the router, and every
difit server.

Both commands share `scripts/highway-tunnel.sh`, installed to
`~/.local/libexec/taj-dotfiles/`, which owns starting the tunnel and keeping
the dashboard link alive.

## Automatic updates

The command `dotfiles-sync-settings` updates this dotfiles checkout, Neovim,
tmux, llm-watch, and choochoo. The individual commands are
`dotfiles-sync-repo`, `dotfiles-sync-nvim`, `dotfiles-sync-tmux`,
`dotfiles-sync-llm-watch`, and `dotfiles-sync-choochoo`. Updates use `git fetch`
and `git merge --ff-only`,
so they never reset, overwrite, or delete local repository changes. When the
dotfiles checkout advances, the updater reruns `install.sh` without package
upgrades, Neovim initialization, or scheduler restarts.

The tmux checkout is stored at `~/.local/share/tmux/oh-my-tmux`. Both
`~/.config/tmux/tmux.conf` and `tmux.conf.local` are symlinked to the committed
files in that checkout. When a scheduled pull changes the tmux commit, a
running tmux server is reloaded automatically.

The llm-watch checkout is stored at `~/.local/share/llm-watch`. The updater
builds its locked Rust release and points `~/.local/bin/llm-watch` at the
native binary. If Cargo is missing, the first Rust-based update installs a
minimal per-user toolchain from the official rustup installer; later updates
reuse it and rebuild incrementally. Its repository and managed hook definitions
are reconciled by every scheduled settings update. Invalid existing JSON
configuration is reported and left untouched.

The choochoo checkout is stored at `~/.local/share/choochoo`. Its locked Rust
release is rebuilt after fast-forward updates and exposed as
`~/.local/bin/choo`. It reuses the same per-user Rust toolchain and requires
`git` and an authenticated `gh` command when operating on GitHub pull requests.
The managed `~/.config/choochoo/config.toml` points its shared train state at
the private `taj-p/choochoo-config` repository, so trains are available across
the laptop and devboxes. An existing config file is moved to a timestamped
backup before the managed symlink is installed.

- macOS: a LaunchAgent runs the combined updater every 600 seconds.
- Ubuntu with a user systemd session: a user timer runs every 10 minutes.
- Coder/container environments without user systemd: a lightweight per-user
  loop is started by the bootstrap and by the shell profile as a restart
  fallback.

Useful checks:

```sh
dotfiles-sync-settings
systemctl --user status dotfiles-settings-sync.timer  # Ubuntu/systemd
launchctl print "gui/$(id -u)/com.tajp.dotfiles-settings-sync"  # macOS
```

Logs are written to `~/.local/state/taj-dotfiles/` on macOS and fallback-loop
systems; systemd systems also expose logs through `journalctl --user`.

## Overrides

These are mainly useful for testing or forks:

- `NVIM_CONFIG_REPO` (default `https://github.com/taj-p/nvim_config.git`)
- `NVIM_CONFIG_BRANCH` (default `main`)
- `NVIM_CONFIG_DIR` (default `${XDG_CONFIG_HOME:-$HOME/.config}/nvim`)
- `TMUX_CONFIG_REPO` (default `git@github.com:taj-p/.tmux.git`)
- `TMUX_CONFIG_BRANCH` (default `master`)
- `TMUX_REPO_DIR` (default `${XDG_DATA_HOME:-$HOME/.local/share}/tmux/oh-my-tmux`)
- `TMUX_CONFIG_DIR` (default `${XDG_CONFIG_HOME:-$HOME/.config}/tmux`)
- `LLM_WATCH_REPO` (default `https://github.com/taj-p/llm-watch.git`)
- `LLM_WATCH_BRANCH` (default `main`)
- `LLM_WATCH_REPO_DIR` (default
  `${XDG_DATA_HOME:-$HOME/.local/share}/llm-watch`)
- `LLM_WATCH_SYNC_INTERVAL_SECONDS` (default `600`)
- `CHOOCHOO_REPO` (default `https://github.com/taj-p/choochoo.git`)
- `CHOOCHOO_BRANCH` (default `main`)
- `CHOOCHOO_REPO_DIR` (default
  `${XDG_DATA_HOME:-$HOME/.local/share}/choochoo`)
- `CHOOCHOO_SYNC_INTERVAL_SECONDS` (default `600`)
- `TREE_SITTER_CLI_VERSION` on Ubuntu (default `0.25.10`, compatible with
  Ubuntu 22.04's glibc 2.35)

## Notes

- On macOS, install Apple's Command Line Tools first if `xcode-select -p`
  fails: `xcode-select --install`.
- A Nerd Font must be selected in the **local terminal application's** settings.
  Remote Ubuntu/Coder machines do not need the font installed.
- Initial Neovim startup downloads AstroNvim plugins and Mason packages, so it
  requires network access.
- The tmux repository uses its SSH URL, so the Mac or Coder workspace needs
  GitHub SSH access for its installation and scheduled updates. The public
  llm-watch repository uses HTTPS and does not require GitHub credentials.
