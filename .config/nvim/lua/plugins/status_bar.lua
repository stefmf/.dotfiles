-- ~/.config/nvim/lua/plugins/status_bar.lua
return {
  "nvim-lualine/lualine.nvim",
  dependencies = {
    "nvim-tree/nvim-web-devicons"
  },
  opts = {
    options = {
      theme = "catppuccin",
      component_separators = { left = "", right = "" },
      section_separators = { left = "", right = "" },
      globalstatus = true,
    },
    sections = {
      lualine_a = {
        { "mode", separator = { left = "" }, right_padding = 2 },
      },
      lualine_b = { 
        "branch",
        {
          "diff",
          symbols = {
            added = " ",
            modified = " ",
            removed = " ",
          },
        },
      },
      lualine_c = {
        {
          "filename",
          path = 1,
          symbols = {
            modified = "  ",
            readonly = "  ",
            unnamed = "  ",
          },
        },
      },
      lualine_x = {
        {
          "diagnostics",
          symbols = {
            error = " ",
            warn = " ",
            info = " ",
            hint = " ",
          },
        },
      },
      lualine_y = { "filetype", "encoding" },
      lualine_z = {
        { "location", separator = { right = "" }, left_padding = 2 },
      },
    },
  },
}