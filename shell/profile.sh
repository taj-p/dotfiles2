# Managed by taj-p/dotfiles. This file is safe to source from Bash and Zsh.

if [ -d /opt/homebrew/bin ]; then
  case ":$PATH:" in
    *":/opt/homebrew/bin:"*) ;;
    *) export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH" ;;
  esac
fi

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

export EDITOR=nvim
export VISUAL=nvim

# Coder containers often have no user systemd session. Keep exactly one small
# updater loop alive as a fallback; the loop uses a per-user directory lock.
if [ "$(uname -s 2>/dev/null)" = Linux ] && [ -x "$HOME/.local/bin/dotfiles-settings-sync-loop" ]; then
  if ! systemctl --user is-active --quiet dotfiles-settings-sync.timer 2>/dev/null; then
    nohup "$HOME/.local/bin/dotfiles-settings-sync-loop" \
      >>"$HOME/.local/state/taj-dotfiles/settings-sync-loop.log" 2>&1 &
  fi
fi
