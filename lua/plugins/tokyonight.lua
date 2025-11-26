return {
  "folke/tokyonight.nvim",
  priority = 1000,
  config = function()
    require("tokyonight").setup({
      style = "night",
      transparent = true,
      terminal_colors = true,
      styles = {
        comments = { italic = true },
        keywords = { italic = true },
        functions = {},
        variables = {},
        sidebars = "dark",
        floats = "dark",
      },
      on_colors = function(colors) end,
      on_highlights = function(highlights, colors) end,
    })

    vim.cmd.colorscheme("tokyonight-night")
  end,
}
