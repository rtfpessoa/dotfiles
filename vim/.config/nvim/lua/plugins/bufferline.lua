return {
  "akinsho/bufferline.nvim",
  dependencies = { "gbprod/nord.nvim" },
  opts = function(_, opts)
    opts.options = {
      separator_style = "thin",
    }
    opts.highlights = require("nord.plugins.bufferline").akinsho()
  end,
}
