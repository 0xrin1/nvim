return {
  "zbirenbaum/copilot.lua",
  cmd = "Copilot",
  event = "InsertEnter",
  config = function()
    require("copilot").setup({
      suggestion = { enabled = false },
      panel = { enabled = false },
      filetypes = {
        markdown = false,
        help = false,
        gitcommit = true,
        lua = true,
        javascript = true,
        typescript = true,
        python = true,
        rust = true,
        sh = true,
        zsh = true,
        bash = true,
      },
      copilot_node_command = vim.fn.exepath("node"),
      server_opts_overrides = {
        settings = {
          advanced = {
            inlineSuggestCount = 3,
          },
        },
      },
    })
  end,
}
