-- Terminal setup migrated to Rex.
-- Sources: ~/.tmux.conf, ~/.config/herdr/config.toml,
-- ~/.config/ghostty/config (+ config.local, loaded by config-file).

-- tmux (~/.tmux.conf) -- prefix ctrl+a
-- :11 bind C-a send-prefix
rex.bind("ctrl+a>ctrl+a", "pane.send_key", { key = "ctrl+a" })
-- :34 bind | split-window -h -c "#{pane_current_path}"
--     (Herdr :22 split_vertical = "prefix+|" also binds this; tmux kept)
rex.bind("ctrl+a>shift+\\", "pane.split", { direction = "right" })
-- :35 bind - split-window -v -c "#{pane_current_path}"
--     (Herdr :23 split_horizontal = "prefix+minus" also binds this; tmux kept)
rex.bind("ctrl+a>-", "pane.split", { direction = "down" })
-- :38 bind c new-window -a -c "#{pane_current_path}"
--     (Herdr :29 new_tab = "prefix+c" also binds this; tmux kept)
rex.bind("ctrl+a>c", "client.tab.new")
-- :44 bind x kill-pane
--     (Herdr :24 close_pane = "prefix+x" also binds this; tmux kept)
rex.bind("ctrl+a>x", "pane.close")
-- :46 bind q kill-session
--     (Herdr :40 close_workspace = "prefix+q" also binds this; tmux kept)
rex.bind("ctrl+a>q", "session.close")
-- :48 bind Up switch-client -p
--     (Herdr :41 previous_workspace = "prefix+up" also binds this; tmux kept)
rex.bind("ctrl+a>up", "session.previous")
-- :49 bind Down switch-client -n
--     (Herdr :42 next_workspace = "prefix+down" also binds this; tmux kept)
rex.bind("ctrl+a>down", "session.next")
-- :53 bind r source-file ~/.tmux.conf \; display-message "tmux reloaded"
--     (Herdr :47 reload_config = "prefix+r" also binds this; tmux kept)
rex.bind("ctrl+a>r", "client.config.reload")
-- :64 bind-key C-l send-keys C-l \; clear-history
--     (Herdr :25 clear_pane = "prefix+ctrl+l" also binds this; tmux kept.
--     The clear-history part has no counterpart and is not migrated.)
rex.bind("ctrl+a>ctrl+l", "pane.send_key", { key = "ctrl+l" })

-- Herdr (~/.config/herdr/config.toml) -- prefix ctrl+a
-- :26 resize_mode = "prefix+shift+r" -- resize mode (exclusive)
rex.mode("resize", { exclusive = true })
rex.bind("resize/enter", "client.mode.exit")
rex.bind("resize/escape", "client.mode.exit")
rex.bind("resize/left", "pane.resize", { direction = "left" })
rex.bind("resize/down", "pane.resize", { direction = "down" })
rex.bind("resize/up", "pane.resize", { direction = "up" })
rex.bind("resize/right", "pane.resize", { direction = "right" })
rex.bind("ctrl+a>shift+r", "client.mode.enter", { name = "resize" })
-- :30 move_tab_previous = "prefix+shift+comma"
rex.bind("ctrl+a>shift+,", "client.tab.move", { direction = "backward" })
-- :31 move_tab_next = "prefix+shift+period"
rex.bind("ctrl+a>shift+.", "client.tab.move", { direction = "forward" })
-- :32 next_tab = "prefix+n"
rex.bind("ctrl+a>n", "client.tab.next")
-- :33 previous_tab = "prefix+p"
rex.bind("ctrl+a>p", "client.tab.previous")
-- :34 switch_tab = "prefix+1..9"
rex.bind("ctrl+a>1", "client.tab.goto", { index = 1 })
rex.bind("ctrl+a>2", "client.tab.goto", { index = 2 })
rex.bind("ctrl+a>3", "client.tab.goto", { index = 3 })
rex.bind("ctrl+a>4", "client.tab.goto", { index = 4 })
rex.bind("ctrl+a>5", "client.tab.goto", { index = 5 })
rex.bind("ctrl+a>6", "client.tab.goto", { index = 6 })
rex.bind("ctrl+a>7", "client.tab.goto", { index = 7 })
rex.bind("ctrl+a>8", "client.tab.goto", { index = 8 })
rex.bind("ctrl+a>9", "client.tab.goto", { index = 9 })
-- :35 rename_tab = "prefix+comma"
rex.bind("ctrl+a>,", "client.tab.rename")
-- :36 rename_pane = "prefix+period"
rex.bind("ctrl+a>.", "pane.rename")
-- :39 new_workspace = "prefix+shift+s"
rex.bind("ctrl+a>shift+s", "session.new")
-- :44 workspace_picker = "prefix+w"
rex.bind("ctrl+a>w", "session.switch")
-- :49 goto = "prefix+g"
rex.bind("ctrl+a>g", "session.switch")
-- :51 zoom = "prefix+z"
rex.bind("ctrl+a>z", "pane.zoom")
-- :54 focus_pane_left = "prefix+h"
rex.bind("ctrl+a>h", "pane.focus", { direction = "left" })
-- :55 focus_pane_down = "prefix+j"
rex.bind("ctrl+a>j", "pane.focus", { direction = "down" })
-- :56 focus_pane_up = "prefix+k"
rex.bind("ctrl+a>k", "pane.focus", { direction = "up" })
-- :57 focus_pane_right = "prefix+l"
rex.bind("ctrl+a>l", "pane.focus", { direction = "right" })

-- Ghostty (~/.config/ghostty/config)
-- :10 keybind = cmd+k=text:\x0c -- clear the terminal.
--     By decision, cmd+k runs Clear Terminal and replaces Rex's default
--     session picker; the picker moves to cmd+p.
rex.bind("cmd+k", "com.superlogical.terminal.clear")
rex.bind("cmd+p", "session.switch")
-- :22 keybind = cmd+a=text:\x01 -- sends the single key ctrl+a
rex.bind("cmd+a", "pane.send_key", { key = "ctrl+a" })
