local termFileExecToggleTerms = {}

vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
  pattern = { "*.unit.*" },
  callback = function(ev)
    vim.api.nvim_buf_set_keymap(0, "n", "<C-t>", "", {
      desc = "yarn test",
      noremap = true,
      callback = function() end,
    })
  end,
})

return {
  "akinsho/toggleterm.nvim",
  opts = {
    open_mapping = [[<c-\>]],
    shade_terminals = false,
    winbar = {
      enabled = true,
    },
    size = 20,
    persist_mode = false,
  },
  keys = {
    { [[<C-\>]] },
  },
  cmd = {
    "ToggleTerm",
    "TermExec",
    "TermFileExecToggle",
  },
  config = function(_, opts)
    require("toggleterm").setup(opts)

    vim.api.nvim_create_autocmd("TermOpen", {
      pattern = { "term://*" },
      callback = function()
        local buffer = vim.api.nvim_get_current_buf()
        local mapOpts = { buffer = buffer }
        -- Keymaps to more easily navigate outside of the terminals
        --vim.keymap.set("t", "<esc>", [[<C-\><C-n>]], mapOpts)
        --vim.keymap.set("t", "jk", [[<C-\><C-n>]], mapOpts)
        vim.keymap.set("t", "<C-h>", [[<Cmd>wincmd h<CR>]], mapOpts)
        vim.keymap.set("t", "<C-j>", [[<Cmd>wincmd j<CR>]], mapOpts)
        vim.keymap.set("t", "<C-k>", [[<Cmd>wincmd k<CR>]], mapOpts)
        vim.keymap.set("t", "<C-l>", [[<Cmd>wincmd l<CR>]], mapOpts)
        vim.keymap.set("t", "<C-w>", [[<C-\><C-n><C-w>]], mapOpts)
        vim.keymap.set("t", "<C-1>", [[<C-\><C-n>1<C-\>]], mapOpts)
        vim.keymap.set("t", "<C-2>", [[<C-\><C-n>2<C-\>]], mapOpts)
        vim.keymap.set("t", "<C-3>", [[<C-\><C-n>3<C-\>]], mapOpts)
        vim.keymap.set("t", "<C-4>", [[<C-\><C-n>4<C-\>]], mapOpts)
      end,
    })

    local Terminal = require("toggleterm.terminal").Terminal
    vim.api.nvim_create_user_command("TermFileExecToggle", function(opts)
      local cmd = opts.fargs[1]:gsub("%%file%%", vim.fn.expand("%"))
      local hotkey = string.format("<%s>", opts.fargs[2]) or ""
      local term = termFileExecToggleTerms[hotkey] or nil
      if term and term.cmd ~= cmd then
        term:shutdown()
        term = nil
        termFileExecToggleTerms[hotkey] = nil
      end
      if term == nil then
        term = Terminal:new({
          cmd = cmd,
          close_on_exit = true,
          env = { DISABLE_FANCY_PROMPT = 1 },
          direction = "float",
          hidden = true,
          on_open = function(ev)
            if hotkey then
              vim.api.nvim_buf_set_keymap(ev.bufnr, "n", hotkey, "", {
                noremap = true,
                silent = true,
                callback = function()
                  if term then
                    term:close()
                  end
                end,
              })
              vim.api.nvim_buf_set_keymap(ev.bufnr, "t", hotkey, "", {
                noremap = true,
                silent = true,
                callback = function()
                  if term then
                    term:close()
                  end
                end,
              })
            end
          end,
        })
        termFileExecToggleTerms[hotkey] = term
      end
      term:toggle()
    end, { nargs = "+" })
  end,
}
