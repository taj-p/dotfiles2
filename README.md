# taj-p dotfiles

Cross-platform development environment bootstrap for:

- macOS (Intel or Apple Silicon)
- Ubuntu 22.04 (x86-64 or ARM64), including Coder workspaces/devboxes

The installer sets up Neovim, the AstroNvim prerequisites, useful optional
AstroNvim terminal tools, and
[`taj-p/nvim_config`](https://github.com/taj-p/nvim_config). The Neovim config
is checked for fast-forward updates every 10 minutes. It also installs tmux and
the settings from `git@github.com:taj-p/.tmux.git`, which are updated on the
same schedule.

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
while current Neovim, lazygit, Tree-sitter CLI, bottom, and gdu binaries are
installed under `~/.local` from their official release artifacts. This avoids
Ubuntu 22.04's old Neovim package.

- Neovim stable (AstroNvim currently requires 0.11 or newer)
- tmux with `taj-p/.tmux` (Oh My Tmux plus the committed local settings)
- ripgrep, fd, and lazygit
- Tree-sitter CLI and a C compiler/toolchain
- Git, curl, unzip, and a system clipboard provider
- Node.js, npm, Python, and Go for LSPs and AstroNvim terminal integrations
- bottom (`btm`) and go DiskUsage (`gdu`)
- JetBrainsMono Nerd Font on macOS (the font belongs on the local terminal, not
  the remote devbox)

The installer also adds `~/.local/bin` to `PATH` and sets `EDITOR`/`VISUAL` to
`nvim` through a small managed fragment sourced by both Bash and Zsh.

## Settings updates

The command `dotfiles-sync-settings` updates both Neovim and tmux. The
individual commands are `dotfiles-sync-nvim` and `dotfiles-sync-tmux`. Updates
use `git fetch` and `git merge --ff-only`, so they never reset, overwrite, or
delete local changes.

The tmux checkout is stored at `~/.local/share/tmux/oh-my-tmux`. Both
`~/.config/tmux/tmux.conf` and `tmux.conf.local` are symlinked to the committed
files in that checkout. When a scheduled pull changes the tmux commit, a
running tmux server is reloaded automatically.

- macOS: a LaunchAgent updates both settings repositories every 600 seconds.
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

## Notes

- On macOS, install Apple's Command Line Tools first if `xcode-select -p`
  fails: `xcode-select --install`.
- A Nerd Font must be selected in the **local terminal application's** settings.
  Remote Ubuntu/Coder machines do not need the font installed.
- Initial Neovim startup downloads AstroNvim plugins and Mason packages, so it
  requires network access.
- The tmux repository uses its SSH URL. The Mac or Coder workspace therefore
  needs GitHub SSH access for installation and scheduled updates.
