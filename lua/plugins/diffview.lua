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
      hooks = {
        -- Ensure proper filetype for diff buffers based on buffer name or headers
        -- (supports deep paths, renames, and diffview:// URIs).
        diff_buf_read = function(bufnr)
          local function uridecode(s)
            return (s:gsub("%%(%x%x)", function(h)
              local ok, ch = pcall(function() return string.char(tonumber(h, 16)) end)
              return ok and ch or ("%%" .. h)
            end))
          end

          local function detect_path()
            -- Prefer extracting from the buffer name (diffview URI).
            local name = vim.api.nvim_buf_get_name(bufnr)
            if name:find("^diffview://") then
              local tail = name:match("^diffview://.-/b/(.+)$")
                or name:match("^diffview://.-/a/(.+)$")
                or name:match("^diffview://.+/(.+)$")
              if tail then
                tail = tail:gsub("[?#].*$", "")
                return uridecode(tail)
              end
            end

            -- Fallback: scan diff headers within the buffer (unified diff buffers).
            local max = math.min(200, vim.api.nvim_buf_line_count(bufnr))
            local lines = vim.api.nvim_buf_get_lines(bufnr, 0, max, false)
            for _, l in ipairs(lines) do
              local b = l:match("^%+%+%+ b/(.+)$")
              if b and b ~= "/dev/null" then return b end
              local a = l:match("^%-%-%- a/(.+)$")
              if a and a ~= "/dev/null" then return a end
              local _, rb = l:match("^diff %-%-git a/(.-)%s+b/(.+)$")
              if rb and rb ~= "/dev/null" then return rb end
            end
            return nil
          end

          local path = detect_path()
          if not path then return end

          local ft = require("config.git_diff.util").resolve_filetype(path)
          if ft then
            pcall(vim.api.nvim_set_option_value, "filetype", ft, { buf = bufnr })
            pcall(vim.treesitter.start, bufnr, ft)
          end
        end,
      },
    })

    vim.keymap.set("n", "<leader>gD", ":DiffviewOpen<CR>", { noremap = true, silent = true })
  end,
}
