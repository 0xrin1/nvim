return {
  "catppuccin/nvim",
  name = "catppuccin",
  priority = 1000,
  config = function()
    require("catppuccin").setup({
      flavour = "mocha",
      background = {
        light = "latte",
        dark = "mocha",
      },
      transparent_background = false,
      integrations = {
        telescope = true,
        nvimtree = true,
        gitsigns = true,
        diffview = true,
        mason = true,
        cmp = true,
        native_lsp = {
          enabled = true,
          underlines = {
            errors = { "undercurl" },
            hints = { "undercurl" },
            warnings = { "undercurl" },
            information = { "undercurl" },
          },
        },
      },
      styles = {
        comments = { "italic" },
        conditionals = { "italic" },
      },
    })

    vim.cmd.colorscheme("catppuccin-mocha")
  end,
}
