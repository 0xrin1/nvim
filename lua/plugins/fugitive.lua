local diff_panel = require("config.git_diff_panel")

return {
  "tpope/vim-fugitive",
  config = function()
    vim.keymap.set("n", "<leader>gd", diff_panel.open, { noremap = true, silent = true })
  end,
}
