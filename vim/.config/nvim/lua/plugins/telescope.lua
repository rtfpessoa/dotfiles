-- Function that can be called from a live grep picker to refine directory
local ts_select_dir_for_live_grep = function(prompt_bufnr)
  local action_state = require("telescope.actions.state")
  local fb = require("telescope").extensions.file_browser
  local live_grep = require("telescope.builtin").live_grep
  local current_line = action_state.get_current_line()

  fb.file_browser({
    files = false,
    depth = false,
    attach_mappings = function(prompt_bufnr)
      require("telescope.actions").select_default:replace(function()
        local entry_path = action_state.get_selected_entry().Path
        local dir = entry_path:is_dir() and entry_path or entry_path:parent()
        local relative = dir:make_relative(vim.fn.getcwd())
        local absolute = dir:absolute()

        live_grep({
          results_title = relative .. "/",
          cwd = absolute,
          default_text = current_line,
        })
      end)

      return true
    end,
  })
end

return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    {
      "nvim-telescope/telescope-fzf-native.nvim",
      build = "make",
      config = function()
        require("telescope").load_extension("fzf")
      end,
    },
    {
      "nvim-telescope/telescope-file-browser.nvim",
      dependencies = { "nvim-lua/plenary.nvim" },
      config = function()
        require("telescope").load_extension("file_browser")
      end,
    },
  },
  opts = {
    defaults = {
      initial_mode = "normal",
      path_display = function(opts, path)
        local tail = require("telescope.utils").path_tail(path)
        return string.format("%s (%s)", tail, path), { { { 1, #tail }, "Constant" } }
      end,
      mappings = {
        n = {
          ["o"] = "select_default",
        },
      },
    },
    pickers = {
      find_files = {
        initial_mode = "insert",
      },
      git_files = {
        initial_mode = "insert",
      },
      grep_string = {
        initial_mode = "insert",
      },
      live_grep = {
        initial_mode = "insert",
        mappings = {
          n = {
            ["o"] = "select_default",
            ["<C-f>"] = ts_select_dir_for_live_grep,
          },
          i = {
            ["<C-f>"] = ts_select_dir_for_live_grep,
          },
        },
      },
    },
  },
}
