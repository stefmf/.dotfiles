-- ~/.config/nvim/lua/plugins/telescope.lua
return {
  {
    "nvim-telescope/telescope.nvim",
    branch = "0.1.x",
    dependencies = { 
      "nvim-lua/plenary.nvim",
      -- Optional: Better sorting performance
      {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
        cond = function()
          return vim.fn.executable("make") == 1
        end,
      },
    },
    config = function()
      local telescope = require("telescope")
      local actions = require("telescope.actions")

      telescope.setup({
        defaults = {
          path_display = { "truncate" },
          -- Keymaps that work inside telescope prompt
          mappings = {
            i = {
              -- Navigate up/down in telescope results
              ["<C-k>"] = actions.move_selection_previous, -- Move selection up
              ["<C-j>"] = actions.move_selection_next,     -- Move selection down
              -- Send results to quickfix list and open it
              ["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
              ["<Esc>"] = actions.close,                   -- Close telescope
            },
          },
        },
      })

      -- Enable fzf-native for better sorting performance
      pcall(telescope.load_extension, "fzf")

      -- Global Keymaps for opening Telescope
      -- NOTE: <leader> is your space key based on your config
      local builtin = require("telescope.builtin")
      
      -- Find Files (<leader>ff)
      -- Opens search for files in your current working directory
      -- Respects .gitignore if in a git repo
      -- Usage: Type space+ff, then start typing file name
      vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Find files" })
      
      -- Live Grep (<leader>fg)
      -- Search for a string in your current working directory
      -- Requires ripgrep (https://github.com/BurntSushi/ripgrep)
      -- Usage: Type space+fg, then type your search term
      vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Live grep" })
      
      -- Buffers (<leader>fb)
      -- Shows all open buffers
      -- Usage: Type space+fb to see and search through open files
      vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Find buffers" })
      
      -- Help Tags (<leader>fh)
      -- Search through vim's help documentation
      -- Usage: Type space+fh, then search for help term
      vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Help tags" })
      
      -- Recent Files (<leader>fr)
      -- Shows your recently opened files
      -- Usage: Type space+fr to see and search recent files
      vim.keymap.set("n", "<leader>fr", builtin.oldfiles, { desc = "Recent files" })
      
      -- Git Commits (<leader>gc)
      -- Browse commit history
      -- Usage: Type space+gc to see commit history
      vim.keymap.set("n", "<leader>gc", builtin.git_commits, { desc = "Git commits" })
    end,
  },
}

--[[ TELESCOPE QUICK REFERENCE:

BASIC USAGE:
- All commands start with <leader> (space key)
- After opening any picker, you can:
  - Type to filter/search
  - Use <C-k>/<C-j> to move up/down in results
  - <Enter> to select
  - <Esc> to cancel
  - <C-q> to send results to quickfix list

COMMON COMMANDS:
space+ff -> Find files      (search through files in current directory)
space+fg -> Live grep      (search through content of files)
space+fb -> List buffers   (see and switch between open files)
space+fr -> Recent files   (see recently opened files)
space+fh -> Help tags      (search through vim help)
space+gc -> Git commits    (browse commit history)

WITHIN RESULTS:
<C-k>  -> Move selection up
<C-j>  -> Move selection down
<C-q>  -> Send to quickfix list
<Esc>  -> Close telescope
<Enter> -> Select item

TIPS:
- Live grep (space+fg) is great for searching code
- Find files (space+ff) is perfect for quickly opening files
- Buffers (space+fb) helps manage open files
- Recent files (space+fr) for quickly returning to previous work
]]