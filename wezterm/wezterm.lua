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

  local_tab:activate()
end)

return config
