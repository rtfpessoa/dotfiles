return {
  {
    "neovim/nvim-lspconfig",
    dependencies = { "jose-elias-alvarez/typescript.nvim" },
    opts = {
      servers = {
        tsserver = {
          -- autostart = false,
          init_options = {
            maxTsServerMemory = 12288,
          },
        },
        eslint = {
          -- autostart = false,
        },
        cssls = {},
        cssmodules_ls = {},
        html = {},
        bashls = {},
        solargraph = {
          mason = false,
        },
      },
      setup = {
        ["*"] = function(_, opts)
          -- Never autostart LSP servers. Do so on-demand with :LspStart
          -- opts["autostart"] = false
        end,
      },
    },
  },
  {
    "williamboman/mason.nvim",
    opts = function(_, opts)
      local solargraphIndex = nil
      for i, v in ipairs(opts.ensure_installed) do
        if v == "solargraph" then
          solargraphIndex = i
        end
      end
      if solargraphIndex then
        table.remove(opts.ensure_installed, solargraphIndex)
      end
    end,
  },
}
