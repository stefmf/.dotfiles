-- ~/.config/nvim/lua/plugins/treesitter.lua
return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    priority = 1000,
    config = function()
      require("nvim-treesitter.configs").setup({
        -- A list of parser names, or "all"
        ensure_installed = {
          -- Shell/System Administration
          "awk",
          "bash",
          "fish",
          "make",
          "passwd",
          "regex",
          "tmux",
          
          -- Infrastructure as Code / DevOps
          "dockerfile",
          "hcl",
          "puppet",
          "ninja",
          "meson",
          "cmake",
          
          -- Version Control
          "git_config",
          "git_rebase",
          "gitattributes",
          "gitcommit",
          "gitignore",
          "diff",
          
          -- Databases and Query Languages
          "sql",
          "graphql",
          
          -- Web Development
          "html",
          "css",
          "javascript",
          "typescript",
          "tsx",
          "http",
          "json",
          "json5",
          "jsonc", -- JSON with comments
          "yaml",
          "toml",
          "xml",
          "nginx",
          "php",
          
          -- Programming Languages
          "python",
          "go",
          "java",
          "lua",
          "rust",
          "c",
          "cpp",
          "c_sharp",
          
          -- Configuration
          "ini",
          "properties",
          "csv",
          "tsv",
          "psv",
          
          -- Documentation
          "markdown",
          "markdown_inline",
          
          -- Neovim-specific
          "vim",
          "vimdoc",
          "query", -- treesitter query language
        },

        -- Install parsers synchronously (only applied to `ensure_installed`)
        sync_install = false,

        -- Automatically install missing parsers when entering buffer
        auto_install = true,

        highlight = {
          enable = true,
          additional_vim_regex_highlighting = false,
        },

        indent = { enable = true },
        
        -- Optional features
        incremental_selection = {
          enable = true,
          keymaps = {
            init_selection = "gnn",
            node_incremental = "grn",
            scope_incremental = "grc",
            node_decremental = "grm",
          },
        },
        
        textobjects = {
          select = {
            enable = true,
            lookahead = true,
            keymaps = {
              -- You can use the capture groups defined in textobjects.scm
              ["af"] = "@function.outer",
              ["if"] = "@function.inner",
              ["ac"] = "@class.outer",
              ["ic"] = "@class.inner",
            },
          },
        },
      })

      -- Set foldmethod to expr and use treesitter for folding
      vim.opt.foldmethod = "expr"
      vim.opt.foldexpr = "nvim_treesitter#foldexpr()"
      -- Start with all folds open
      vim.opt.foldenable = false
    end,
  },
  -- Optional: Additional textobjects for treesitter
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
  }
}