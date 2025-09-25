return {
  "sindrets/diffview.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("diffview").setup({
      view = {
        default = {
          layout = "diff2_vertical",
          disable_diagnostics = true,
          winbar_info = false,
        },
        file_history = {
          layout = "diff2_vertical",
          disable_diagnostics = true,
          winbar_info = false,
        },
        merge_tool = {
          layout = "diff3_horizontal",
          disable_diagnostics = true,
          winbar_info = false,
        },
      },
      file_panel = {
        listing_style = "list",
        tree_options = {
          flatten_dirs = true,
          folder_statuses = "only_folded",
        },
      },
      watch_index = true,
    })

    vim.keymap.set("n", "<leader>gD", ":DiffviewOpen<CR>", { noremap = true, silent = true })
  end,
}
