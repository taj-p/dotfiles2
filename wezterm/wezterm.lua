local wezterm = require 'wezterm'
local mux = wezterm.mux

local config = wezterm.config_builder()

wezterm.on('gui-startup', function(cmd)
  -- Preserve explicit invocations such as `wezterm start -- command`.
  if cmd then
    mux.spawn_window(cmd)
    return
  end

  local home = wezterm.home_dir
  local local_tab, _, window = mux.spawn_window {
    cwd = home .. '/bl',
    args = { home .. '/.local/bin/bl-workspace' },
  }
  local_tab:set_title 'bl'

  local hosts = {
    'coder.dev2',
    'coder.dev3',
    'coder.lsr-dash',
    'coder.dev-eu',
  }

  for _, host in ipairs(hosts) do
    local tab = window:spawn_tab {
      args = {
        '/usr/bin/ssh',
        '-t',
        host,
        'tmux new-session -A -s main',
      },
    }
    tab:set_title(host)
  end

  -- The laptop itself, last in the tab list and shaped like a devbox: one tab,
  -- one `main` tmux session. `llm-watch` watches it under the alias `local`, so
  -- the dashboard's jump button finds this tab by title like any other host.
  local laptop_tab = window:spawn_tab {
    cwd = home,
    args = { '/opt/homebrew/bin/tmux', 'new-session', '-A', '-s', 'main' },
  }
  laptop_tab:set_title 'local'

  local_tab:activate()
end)

return config
