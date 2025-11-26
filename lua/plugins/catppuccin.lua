return {
  "catppuccin/nvim",
  name = "catppuccin",
  enabled = false,
  priority = 1000,
  config = function()
    require("catppuccin").setup({
      flavour = "frappe",
      background = {
        light = "latte",
        dark = "frappe",
      },
      transparent_background = true,
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

    vim.cmd.colorscheme("catppuccin-frappe")
  end,
}
