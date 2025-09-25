return {
  "williamboman/mason-lspconfig.nvim",
  dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
  opts = {
    ensure_installed = { "ts_ls", "rust_analyzer", "pyright" },
  },
}
