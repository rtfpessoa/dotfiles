-- stylua: ignore

return {
  -- add tokyonight
  {
    "folke/tokyonight.nvim",
    lazy = true,
    opts = { style = "moon" },
  },

  -- Configure LazyVim to load tokyonight
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "tokyonight",
    },
  },

  -- change trouble config
  {
    "folke/trouble.nvim",
    -- opts will be merged with the parent spec
    opts = { use_diagnostic_signs = true },
  },

  -- add symbols-outline
  {
    "simrat39/symbols-outline.nvim",
    cmd = "SymbolsOutline",
    keys = { { "<leader>cs", "<cmd>SymbolsOutline<cr>", desc = "Symbols Outline" } },
    config = true,
  },

  -- override nvim-cmp and add cmp-emoji
  {
    "hrsh7th/nvim-cmp",
    dependencies = { "hrsh7th/cmp-emoji" },
    ---@param opts cmp.ConfigSchema
    opts = function(_, opts)
      local cmp = require("cmp")
      opts.sources = cmp.config.sources(vim.list_extend(opts.sources, { { name = "emoji" } }))
    end,
  },

  -- change some telescope options and a keymap to browse plugin files
  {
    "nvim-telescope/telescope.nvim",
    keys = {
      -- add a keymap to browse plugin files
      -- stylua: ignore
      {
        "<leader>fp",
        function() require("telescope.builtin").find_files({ cwd = require("lazy.core.config").options.root }) end,
        desc = "Find Plugin File",
      },
    },
    -- change some options
    opts = {
      defaults = {
        layout_strategy = "horizontal",
        layout_config = { prompt_position = "top" },
        sorting_strategy = "ascending",
        winblend = 0,
      },
    },
  },

  -- add telescope-fzf-native
  {
    "telescope.nvim",
    dependencies = {
      "nvim-telescope/telescope-fzf-native.nvim",
      build = "make",
      config = function()
        require("telescope").load_extension("fzf")
      end,
    },
  },

  { "jose-elias-alvarez/typescript.nvim" },

  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "folke/which-key.nvim",
      "mfussenegger/nvim-jdtls",
      "jose-elias-alvarez/typescript.nvim",
      "b0o/SchemaStore.nvim",
      version = false,
      init = function()
        require("lazyvim.util").on_attach(function(_, buffer)
          -- stylua: ignore
          vim.keymap.set( "n", "<leader>co", "TypescriptOrganizeImports", { buffer = buffer, desc = "Organize Imports" })
          vim.keymap.set("n", "<leader>cR", "TypescriptRenameFile", { desc = "Rename File", buffer = buffer })
        end)
      end,
    },
    ---@class PluginLspOpts
    opts = {
      ---@type lspconfig.options
      servers = {
        eslint = {
          settings = {
            -- helps eslint find the eslintrc when it's placed in a subfolder instead of the cwd root
            workingDirectory = { mode = "auto" },
          },
        },
        yamlls = {
          -- Have to add this for yamlls to understand that we support line folding
          capabilities = {
            textDocument = {
              foldingRange = {
                dynamicRegistration = false,
                lineFoldingOnly = true,
              },
            },
          },
          -- lazy-load schemastore when needed
          on_new_config = function(new_config)
            new_config.settings.yaml.schemas = new_config.settings.yaml.schemas or {}
            vim.list_extend(new_config.settings.yaml.schemas, require("schemastore").yaml.schemas())
          end,
          settings = {
            redhat = { telemetry = { enabled = false } },
            yaml = {
              keyOrdering = false,
              format = {
                enable = true,
              },
              validate = true,
              schemaStore = {
                -- Must disable built-in schemaStore support to use
                -- schemas from SchemaStore.nvim plugin
                enable = false,
                -- Avoid TypeError: Cannot read properties of undefined (reading 'length')
                url = "",
              },
            },
          },
        },
        ---@type lspconfig.options.tsserver
        tsserver = {
          keys = {
            { "<leader>co", "<cmd>TypescriptOrganizeImports<CR>", desc = "Organize Imports" },
            { "<leader>cR", "<cmd>TypescriptRenameFile<CR>", desc = "Rename File" },
          },
          settings = {
            typescript = {
              format = {
                indentSize = vim.o.shiftwidth,
                convertTabsToSpaces = vim.o.expandtab,
                tabSize = vim.o.tabstop,
              },
            },
            javascript = {
              format = {
                indentSize = vim.o.shiftwidth,
                convertTabsToSpaces = vim.o.expandtab,
                tabSize = vim.o.tabstop,
              },
            },
            completions = {
              completeFunctionCalls = true,
            },
          },
        },
        terraformls = {},
        pyright = {},
        ruff_lsp = {},
        jsonls = {
          -- lazy-load schemastore when needed
          on_new_config = function(new_config)
            new_config.settings.json.schemas = new_config.settings.json.schemas or {}
            vim.list_extend(new_config.settings.json.schemas, require("schemastore").json.schemas())
          end,
          settings = {
            json = {
              format = {
                enable = true,
              },
              validate = { enable = true },
            },
          },
        },
        jdtls = {
          -- stylua: ignore
          keys = {
            { "<leader>co", function() require("jdtls").organize_imports() end, desc = "Organize Imports", },
            { "<leader>cR", function() require("jdtls").rename_file() end, desc = "Rename File", },
            { "<leader>cxv", function() require("jdtls").extract_variable() end, desc = "Extract Variable", },
            { "<leader>cxv", function() require("jdtls").extract_variable({ visual = true }) end, mode = "v", desc = "Extract Variable", },
            { "<leader>cxc", function() require("jdtls").extract_constant() end, desc = "Extract Constant", },
            { "<leader>cxc", function() require("jdtls").extract_constant({ visual = true }) end, mode = "v", desc = "Extract Constant", },
            { "<leader>cxm", function() require("jdtls").extract_method({ visual = true }) end, mode = "v", desc = "Extract Method", },
          },
        },
        gopls = {
          keys = {
            -- Workaround for the lack of a DAP strategy in neotest-go: https://github.com/nvim-neotest/neotest-go/issues/12
            { "<leader>td", "<cmd>lua require('dap-go').debug_test()<CR>", desc = "Debug Nearest (Go)" },
          },
          settings = {
            gopls = {
              gofumpt = true,
              codelenses = {
                gc_details = false,
                generate = true,
                regenerate_cgo = true,
                run_govulncheck = true,
                test = true,
                tidy = true,
                upgrade_dependency = true,
                vendor = true,
              },
              hints = {
                assignVariableTypes = true,
                compositeLiteralFields = true,
                compositeLiteralTypes = true,
                constantValues = true,
                functionTypeParameters = true,
                parameterNames = true,
                rangeVariableTypes = true,
              },
              analyses = {
                fieldalignment = true,
                nilness = true,
                unusedparams = true,
                unusedwrite = true,
                useany = true,
              },
              usePlaceholders = true,
              completeUnimported = true,
              staticcheck = true,
              directoryFilters = { "-.git", "-.vscode", "-.idea", "-.vscode-test", "-node_modules" },
              semanticTokens = true,
            },
          },
        },
        -- pyright will be automatically installed with mason and loaded with lspconfig
        pyright = {},
        -- tsserver will be automatically installed with mason and loaded with lspconfig
        tsserver = {},
        dockerls = {},
        docker_compose_language_service = {},
      },
      -- you can do any additional lsp server setup here
      -- return true if you don't want this server to be setup with lspconfig
      ---@type table<string, fun(server:string, opts:_.lspconfig.options):boolean?>
      setup = {
        eslint = function()
          vim.api.nvim_create_autocmd("BufWritePre", {
            callback = function(event)
              if not require("lazyvim.plugins.lsp.format").enabled() then
                -- exit early if autoformat is not enabled
                return
              end

              local client = vim.lsp.get_active_clients({ bufnr = event.buf, name = "eslint" })[1]
              if client then
                local diag = vim.diagnostic.get(event.buf, { namespace = vim.lsp.diagnostic.get_namespace(client.id) })
                if #diag > 0 then
                  vim.cmd("EslintFixAll")
                end
              end
            end,
          })
        end,
        tsserver = function(_, opts)
          require("typescript").setup({ server = opts })
          return true
        end,
        ruff_lsp = function()
          require("lazyvim.util").on_attach(function(client, _)
            if client.name == "ruff_lsp" then
              -- Disable hover in favor of Pyright
              client.server_capabilities.hoverProvider = false
            end
          end)
        end,
        -- Override the default jdtls server startup to use nvim-jdtls.
        jdtls = function()
          -- The lspconfig configuration for jdtls contains two useful items:
          -- 1. The list of filetypes on which to match.
          -- 2. Custom method for finding the root for a java project.
          local lsp_config = require("lspconfig.server_configurations.jdtls").default_config
          local find_java_project_root = lsp_config.root_dir
          local filetypes = lsp_config.filetypes
          -- lookup paths for java test and debugger package
          local mason_registry = require("mason-registry")
          local bundles = {}
          if mason_registry.has_package("java-test") and mason_registry.has_package("java-debug-adapter") then
            -- jdtls tools configuration for debugging support
            local java_test_pkg = mason_registry.get_package("java-test")
            local java_test_path = java_test_pkg:get_install_path()
            local java_dbg_pkg = mason_registry.get_package("java-debug-adapter")
            local java_dbg_path = java_dbg_pkg:get_install_path()
            local jar_patterns = {
              java_dbg_path .. "/extension/server/com.microsoft.java.debug.plugin-*.jar",
              java_test_path .. "/extension/server/*.jar"
            }
            for _, jar_pattern in ipairs(jar_patterns) do
              for _, bundle in ipairs(vim.split(vim.fn.glob(jar_pattern), '\n')) do
                table.insert(bundles, bundle)
              end
            end
          end
          -- Attach jdtls for the proper filetypes (i.e. java).
          -- Existing server will be reused if the root_dir matches.
          vim.api.nvim_create_autocmd("FileType", {
            group = vim.api.nvim_create_augroup("MyJdtls", { clear = true }),
            pattern = filetypes,
            callback = function()
              local fname = vim.api.nvim_buf_get_name(0)
              local root_dir = find_java_project_root(fname)
              local project_name = root_dir and vim.fs.basename(root_dir)
              local cmd = { "jdtls" }
              if project_name then
                local jdtls_cache_dir = vim.fn.stdpath("cache") .. "/jdtls/" .. project_name
                vim.list_extend(cmd, {
                  "-configuration",
                  jdtls_cache_dir .. "/config",
                  "-data",
                  jdtls_cache_dir .. "/workspace",
                })
              end
              local jdtls_base_config = {
                on_attach = require("lazyvim.util").on_attach(function(client, buffer)
                  if mason_registry.has_package("java-test") then
                    -- custom keymaps for Java test runner (not yet compatible with neotest)
                    vim.keymap.set("n", "<leader>tT", function() require("jdtls").pick_test({ bufnr = buffer }) end, { buffer = buffer, desc = "Run specific Test" })
                    vim.keymap.set("n", "<leader>tt", function() require("jdtls").test_class({ bufnr = buffer }) end, { buffer = buffer, desc = "Run File" })
                    vim.keymap.set("n", "<leader>tr", function() require("jdtls").test_nearest_method({ bufnr = buffer }) end, { buffer = buffer, desc = "Run nearest" })
                  end
                  if mason_registry.has_package("java-debug-adapter") then
                    -- custom init for Java debugger
                    require("jdtls").setup_dap({ hotcodereplace = "auto" })
                    require("jdtls.dap").setup_dap_main_class_configs()
                  end
                  require("jdtls.setup").add_commands()
                end),
                cmd = cmd,
                root_dir = root_dir,
                init_options = {
                  bundles = bundles,
                }
              }
              local jdtls_opts = require("lazyvim.util").opts("nvim-jdtls")
              require("jdtls").start_or_attach(vim.tbl_deep_extend("force", jdtls_opts or {}, jdtls_base_config))
              require("which-key").register({ c = { x = { name = "Extract" } } }, { prefix = "<leader>" })
            end,
          })
          return true -- avoid duplicate servers
        end,
        -- example to setup with typescript.nvim
        tsserver = function(_, opts)
          require("typescript").setup({ server = opts })
          return true
        end,
        -- Specify * to use this function as a fallback for any server
        -- ["*"] = function(server, opts) end,
        gopls = function(_, opts)
          -- workaround for gopls not supporting semanticTokensProvider
          -- https://github.com/golang/go/issues/54531#issuecomment-1464982242
          require("lazyvim.util").on_attach(function(client, _)
            if client.name == "gopls" then
              if not client.server_capabilities.semanticTokensProvider then
                local semantic = client.config.capabilities.textDocument.semanticTokens
                client.server_capabilities.semanticTokensProvider = {
                  full = true,
                  legend = {
                    tokenTypes = semantic.tokenTypes,
                    tokenModifiers = semantic.tokenModifiers,
                  },
                  range = true,
                }
              end
            end
          end)
          -- end workaround
        end,
      },
    },
  },

  {
    "b0o/SchemaStore.nvim",
    version = false,
  },

  {
    "mfussenegger/nvim-dap-python",
    -- stylua: ignore
    keys = {
      { "<leader>dPt", function() require('dap-python').test_method() end, desc = "Debug Method" },
      { "<leader>dPc", function() require('dap-python').test_class() end, desc = "Debug Class" },
    },
    config = function()
      local path = require("mason-registry").get_package("debugpy"):get_install_path()
      require("dap-python").setup(path .. "/venv/bin/python")
    end,
  },

  {
    "linux-cultist/venv-selector.nvim",
    cmd = "VenvSelect",
    opts = {},
    keys = { { "<leader>cv", "<cmd>:VenvSelect<cr>", desc = "Select VirtualEnv" } },
  },

  {
    "mfussenegger/nvim-dap",
    optional = true,
    dependencies = {
      {
        "williamboman/mason.nvim",
        opts = function(_, opts)
          opts.ensure_installed = opts.ensure_installed or {}
          table.insert(opts.ensure_installed, "js-debug-adapter")
        end,
        "mfussenegger/nvim-dap-python",
        -- stylua: ignore
        keys = {
          { "<leader>dPt", function() require('dap-python').test_method() end, desc = "Debug Method" },
          { "<leader>dPc", function() require('dap-python').test_class() end, desc = "Debug Class" },
        },
        config = function()
          local path = require("mason-registry").get_package("debugpy"):get_install_path()
          require("dap-python").setup(path .. "/venv/bin/python")
        end,
      },
    },
    opts = function()
      local dap = require("dap")
      if not dap.adapters["pwa-node"] then
        require("dap").adapters["pwa-node"] = {
          type = "server",
          host = "localhost",
          port = "${port}",
          executable = {
            command = "node",
            -- 💀 Make sure to update this path to point to your installation
            args = {
              require("mason-registry").get_package("js-debug-adapter"):get_install_path()
                .. "/js-debug/src/dapDebugServer.js",
              "${port}",
            },
          },
        }
      end
      for _, language in ipairs({ "typescript", "javascript" }) do
        if not dap.configurations[language] then
          dap.configurations[language] = {
            {
              type = "pwa-node",
              request = "launch",
              name = "Launch file",
              program = "${file}",
              cwd = "${workspaceFolder}",
            },
            {
              type = "pwa-node",
              request = "attach",
              name = "Attach",
              processId = require("dap.utils").pick_process,
              cwd = "${workspaceFolder}",
            },
          }
        end
      end
    end,
  },

  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      vim.list_extend(opts.ensure_installed, {
        "bash",
        "dockerfile",
        "go",
        "gomod",
        "gowork",
        "gosum",
        "html",
        "java",
        "javascript",
        "json",
        "json5",
        "jsonc",
        "lua",
        "markdown",
        "markdown_inline",
        "ninja",
        "python",
        "rst",
        "toml",
        "query",
        "regex",
        "typescript",
        "terraform",
        "hcl",
        "tsx",
        "vim",
        "yaml",
      })
      opts.ignore_install = opts.ignore_install or {}
      vim.list_extend(opts.ignore_install, {
        "c",
        "ruby",
        "perl",
      })
    end,
  },

  {
    "folke/which-key.nvim",
    optional = true,
    opts = {
      defaults = {
        ["<leader>t"] = { name = "+test" },
      },
    },
  },

  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/neotest-go",
    },
    opts = {
      -- Can be a list of adapters like what neotest expects,
      -- or a list of adapter names,
      -- or a table of adapter names, mapped to adapter configs.
      -- The adapter will then be automatically loaded with the config.
      adapters = {
        ["neotest-go"] = {
          -- args = { "-tags=integration" },
        },
        ["neotest-python"] = {},
        ["neotest-plenary"] = {},
        ["neotest-jest"] = {},
      },
      status = { virtual_text = true },
      output = { open_on_run = true },
      quickfix = {
        open = function()
          if require("lazyvim.util").has("trouble.nvim") then
            vim.cmd("Trouble quickfix")
          else
            vim.cmd("copen")
          end
        end,
      },
    },
    config = function(_, opts)
      local neotest_ns = vim.api.nvim_create_namespace("neotest")
      vim.diagnostic.config({
        virtual_text = {
          format = function(diagnostic)
            -- Replace newline and tab characters with space for more compact diagnostics
            local message = diagnostic.message:gsub("\n", " "):gsub("\t", " "):gsub("%s+", " "):gsub("^%s+", "")
            return message
          end,
        },
      }, neotest_ns)

      if opts.adapters then
        local adapters = {}
        for name, config in pairs(opts.adapters or {}) do
          if type(name) == "number" then
            if type(config) == "string" then
              config = require(config)
            end
            adapters[#adapters + 1] = config
          elseif config ~= false then
            local adapter = require(name)
            if type(config) == "table" and not vim.tbl_isempty(config) then
              local meta = getmetatable(adapter)
              if adapter.setup then
                adapter.setup(config)
              elseif meta and meta.__call then
                adapter(config)
              else
                error("Adapter " .. name .. " does not support setup")
              end
            end
            adapters[#adapters + 1] = adapter
          end
        end
        opts.adapters = adapters
      end

      require("neotest").setup(opts)
    end,
    -- stylua: ignore
    keys = {
      { "<leader>tt", function() require("neotest").run.run(vim.fn.expand("%")) end, desc = "Run File" },
      { "<leader>tT", function() require("neotest").run.run(vim.loop.cwd()) end, desc = "Run All Test Files" },
      { "<leader>tr", function() require("neotest").run.run() end, desc = "Run Nearest" },
      { "<leader>ts", function() require("neotest").summary.toggle() end, desc = "Toggle Summary" },
      { "<leader>to", function() require("neotest").output.open({ enter = true, auto_close = true }) end, desc = "Show Output" },
      { "<leader>tO", function() require("neotest").output_panel.toggle() end, desc = "Toggle Output Panel" },
      { "<leader>tS", function() require("neotest").run.stop() end, desc = "Stop" },
    },
  },

  {
    "nvim-neotest/neotest-go",
  },

  {
    "nvim-neotest/neotest-python",
  },

  {
    "nvim-neotest/neotest-jest",
  },

  -- the opts function can also be used to change the default opts:
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = function(_, opts)
      table.insert(opts.sections.lualine_x, "😄")
    end,
  },

  -- use mini.starter instead of alpha
  { import = "lazyvim.plugins.extras.ui.mini-starter" },

  -- add jsonls and schemastore packages, and setup treesitter for json, json5 and jsonc
  { import = "lazyvim.plugins.extras.lang.json" },

  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "stylua",
        "shellcheck",
        "shfmt",
        "flake8",
        "prettierd",
        "java-test",
        "java-debug-adapter",
        "js-debug-adapter",
      },
    },
  },

  {
    "jose-elias-alvarez/null-ls.nvim",
    opts = function(_, opts)
      local nls = require("null-ls")
      opts.sources = opts.sources or {}
      vim.list_extend(opts.sources, {
        nls.builtins.diagnostics.hadolint,
        nls.builtins.formatting.prettierd,
        nls.builtins.code_actions.gomodifytags,
        nls.builtins.code_actions.impl,
        nls.builtins.formatting.gofumpt,
        nls.builtins.formatting.goimports_reviser,
        nls.builtins.formatting.terraform_fmt,
        nls.builtins.diagnostics.terraform_validate,
        require("typescript.extensions.null-ls.code-actions"),
      })
    end,
    dependencies = {
      "mason.nvim",
      opts = function(_, opts)
        opts.ensure_installed = opts.ensure_installed or {}
        vim.list_extend(opts.ensure_installed, { "hadolint" })
      end,
    },
  },

  -- Use <tab> for completion and snippets (supertab)
  -- first: disable default <tab> and <s-tab> behavior in LuaSnip
  {
    "L3MON4D3/LuaSnip",
    keys = function()
      return {}
    end,
  },

  -- then: setup supertab in cmp
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-emoji",
    },
    ---@param opts cmp.ConfigSchema
    opts = function(_, opts)
      local has_words_before = function()
        unpack = unpack or table.unpack
        local line, col = unpack(vim.api.nvim_win_get_cursor(0))
        return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
      end

      local luasnip = require("luasnip")
      local cmp = require("cmp")

      opts.mapping = vim.tbl_extend("force", opts.mapping, {
        ["<Tab>"] = cmp.mapping(function(fallback)
          if cmp.visible() then
            cmp.select_next_item()
            -- You could replace the expand_or_jumpable() calls with expand_or_locally_jumpable()
            -- this way you will only jump inside the snippet region
          elseif luasnip.expand_or_jumpable() then
            luasnip.expand_or_jump()
          elseif has_words_before() then
            cmp.complete()
          else
            fallback()
          end
        end, { "i", "s" }),
        ["<S-Tab>"] = cmp.mapping(function(fallback)
          if cmp.visible() then
            cmp.select_prev_item()
          elseif luasnip.jumpable(-1) then
            luasnip.jump(-1)
          else
            fallback()
          end
        end, { "i", "s" }),
      })
    end,
  },
}
