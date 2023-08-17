return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = {
    enable_normal_mode_for_inputs = true,
    close_if_last_window = true,
    filesystem = {
      bind_to_cwd = true,
      filtered_items = {
        visible = true,
        --hide_dotfiles = false,
        --hide_hidden = false,
        --hide_gitignored = false,
      },
      window = {
        mappings = {
          ["/"] = false,
          ["F"] = "fuzzy_finder",
        },
      },
    },
    window = {
      mappings = {
        ["o"] = "open",
        ["-"] = "open_split",
        ["|"] = "open_vsplit",
        ["s"] = false,
        ["S"] = false,
      },
    },
  },
}
