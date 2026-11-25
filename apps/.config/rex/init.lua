-- # Shortcuts

-- ## Misc
rex.bind("cmd+k", "com.superlogical.terminal.clear")
rex.bind("cmd+r", "client.config.reload")
rex.bind("cmd+shift+p", "client.palette.toggle")

-- ## Session
rex.bind("cmd+p", "session.switch")
rex.bind("cmd+shift+t", "session.new.on_host")
rex.bind("cmd+shift+w", "session.close")
rex.bind("cmd+left", "session.previous")
rex.bind("cmd+right", "session.next")

-- ## Tab
rex.bind("cmd+t", "client.tab.new")
rex.bind("cmd+shift+,", "client.tab.rename")
rex.bind("cmd+down", "client.tab.next")
rex.bind("cmd+up", "client.tab.previous")
rex.bind("cmd+option+[", "client.tab.move", { direction = "backward" })
rex.bind("cmd+option+]", "client.tab.move", { direction = "forward" })

-- ## Pane
rex.bind("cmd+w", "pane.close")
rex.bind("cmd+shift+.", "pane.rename")
rex.bind("cmd+shift+\\", "pane.split", { direction = "right" })
rex.bind("cmd+shift+-", "pane.split", { direction = "down" })
rex.bind("cmd+option+h", "pane.focus", { direction = "left" })
rex.bind("cmd+option+j", "pane.focus", { direction = "down" })
rex.bind("cmd+option+k", "pane.focus", { direction = "up" })
rex.bind("cmd+option+l", "pane.focus", { direction = "right" })
