-- ~/.config/nvim/lua/plugins/git_fugitive.lua
return {
  "tpope/vim-fugitive",
  event = "VeryLazy",
  config = function()
    -- Fugitive key mappings
    vim.keymap.set("n", "<leader>gs", vim.cmd.Git, { desc = "Git status" })
    vim.keymap.set("n", "<leader>gb", ":Git blame<CR>", { desc = "Git blame" })
    vim.keymap.set("n", "<leader>gd", ":Gdiff<CR>", { desc = "Git diff" })
  end,
}