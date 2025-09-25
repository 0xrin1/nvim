return {
  "lewis6991/gitsigns.nvim",
  config = function()
    require("gitsigns").setup({
      signs = {
        add = { text = "+" },
        change = { text = "~" },
        delete = { text = "-" },
        topdelete = { text = "‾" },
        changedelete = { text = "~" },
      },
    })

    local opts = { noremap = true, silent = true }
    vim.keymap.set("n", "<leader>gp", ":Gitsigns preview_hunk<CR>", opts)
    vim.keymap.set("n", "<leader>gu", ":Gitsigns reset_hunk<CR>", opts)
    vim.keymap.set("n", "<leader>gU", ":Gitsigns reset_buffer<CR>", opts)
    vim.keymap.set("n", "<leader>gn", ":Gitsigns next_hunk<CR>", opts)
    vim.keymap.set("n", "<leader>gN", ":Gitsigns prev_hunk<CR>", opts)
  end,
}
