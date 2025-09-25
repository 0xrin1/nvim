return {
  "bfrg/vim-cuda-syntax",
  config = function()
    vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
      pattern = "*.ptx",
      callback = function()
        vim.bo.filetype = "cuda"
      end,
    })
  end,
}
