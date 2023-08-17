return {
  "nvim-treesitter/nvim-treesitter",
  opts = {
    highlight = {
      enable = true,
      additional_vim_regex_highlighting = true,
    },
    indent = {
      -- Issues with typescript indentation (2023/07/25)
      -- https://github.com/nvim-treesitter/nvim-treesitter/issues/1019#issuecomment-811658387
      enable = false,
    },
  },
}
