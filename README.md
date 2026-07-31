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
- zoxide (`z`), lsd (`ls`), and bat
- `gh-dash`, installed as a GitHub CLI extension when `gh` is available
- `llm-watch`, installed from `taj-p/llm-watch` for cross-devbox agent status
  and completion notifications
- JetBrainsMono Nerd Font on macOS (the font belongs on the local terminal, not
  the remote devbox)

The installer also adds `~/.local/bin` to `PATH` and sets `EDITOR`/`VISUAL` to
`nvim` through a small managed fragment sourced by both Bash and Zsh. It also
provides `g` and `lg` as short aliases for `git` and `lazygit`, initializes
zoxide as `z`, and aliases `ls` to `lsd`.

Run `dotfiles-packages` for a quick reminder of every managed package, its
command name, and what it is used for.

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

Run `llm-watch dashboard` on the laptop to poll running Coder workspaces whose
names start with `dev`. On every machine, managed hooks write Codex and Claude
state beneath `~/.local/state/llm-watch`. Hook configuration is merged into
`~/.codex/hooks.json` and `~/.claude/settings.json`; existing unrelated hooks
are retained and an existing file is backed up before its first change.

Codex requires a one-time trust review for user command hooks. After the first
dotfiles update that installs llm-watch, open `/hooks` in Codex and trust the
llm-watch entries. The managed Codex `Stop` adapter emits the JSON response
Codex expects and deliberately leaves any existing `notify` command untouched.

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

## Automatic updates

The command `dotfiles-sync-settings` updates this dotfiles checkout, Neovim,
tmux, and llm-watch. The individual commands are `dotfiles-sync-repo`,
`dotfiles-sync-nvim`, `dotfiles-sync-tmux`, and
`dotfiles-sync-llm-watch`. Updates use `git fetch` and `git merge --ff-only`,
so they never reset, overwrite, or delete local repository changes. When the
dotfiles checkout advances, the updater reruns `install.sh` without package
upgrades, Neovim initialization, or scheduler restarts.

The tmux checkout is stored at `~/.local/share/tmux/oh-my-tmux`. Both
`~/.config/tmux/tmux.conf` and `tmux.conf.local` are symlinked to the committed
files in that checkout. When a scheduled pull changes the tmux commit, a
running tmux server is reloaded automatically.

The llm-watch checkout is stored at `~/.local/share/llm-watch` and
`~/.local/bin/llm-watch` points to its executable. Its repository and managed
hook definitions are reconciled by every scheduled settings update. Invalid
existing JSON configuration is reported and left untouched.

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
- `LLM_WATCH_REPO` (default `git@github.com:taj-p/llm-watch.git`)
- `LLM_WATCH_BRANCH` (default `main`)
- `LLM_WATCH_REPO_DIR` (default
  `${XDG_DATA_HOME:-$HOME/.local/share}/llm-watch`)
- `LLM_WATCH_SYNC_INTERVAL_SECONDS` (default `600`)
- `TREE_SITTER_CLI_VERSION` on Ubuntu (default `0.25.10`, compatible with
  Ubuntu 22.04's glibc 2.35)

## Notes

- On macOS, install Apple's Command Line Tools first if `xcode-select -p`
  fails: `xcode-select --install`.
- A Nerd Font must be selected in the **local terminal application's** settings.
  Remote Ubuntu/Coder machines do not need the font installed.
- Initial Neovim startup downloads AstroNvim plugins and Mason packages, so it
  requires network access.
- The tmux and llm-watch repositories use their SSH URLs. The Mac or Coder
  workspace therefore needs GitHub SSH access for installation and scheduled
  updates.
