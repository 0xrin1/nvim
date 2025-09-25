return {
  "nvim-telescope/telescope.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    local telescope = require("telescope")

    telescope.setup({
      defaults = {
        mappings = {
          i = {
            ["<C-j>"] = "move_selection_next",
            ["<C-k>"] = "move_selection_previous",
            ["<C-p>"] = "move_selection_previous",
          },
        },
      },
    })

    local opts = { noremap = true, silent = true }
    vim.keymap.set("n", "<C-p>", ":Telescope find_files<CR>", opts)
    vim.keymap.set("n", "<leader>fg", ":Telescope live_grep<CR>", opts)
  end,
}
