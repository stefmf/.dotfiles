-- ~/.config/nvim/lua/plugins/auto_dark_mode.lua
return {
  "f-person/auto-dark-mode.nvim",
  priority = 1001, -- Higher priority than colorscheme
  opts = {
    update_interval = 1000,
    set_dark_mode = function()
      vim.api.nvim_set_option_value("background", "dark", {})
      require("catppuccin").setup({
        flavour = "frappe" -- Your dark theme
      })
      vim.cmd.colorscheme("catppuccin")
    end,
    set_light_mode = function()
      vim.api.nvim_set_option_value("background", "light", {})
      require("catppuccin").setup({
        flavour = "latte" -- Catppuccin light theme
      })
      vim.cmd.colorscheme("catppuccin")
    end,
  },
}