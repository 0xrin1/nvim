local M = {}

local util = require("config.git_diff.util")

--------------------------------------------------------------------------------
-- Namespaces (shared across all panel instances)
--------------------------------------------------------------------------------
M.highlight_ns = vim.api.nvim_create_namespace("GitDiffPanelHighlights")
M.virt_ns = vim.api.nvim_create_namespace("GitDiffPanelVirtText")

--------------------------------------------------------------------------------
-- Highlight Setup
--------------------------------------------------------------------------------
function M.setup_highlights()
  local palette = {
    green = "#9ece6a",
    red = "#f7768e",
    yellow = "#e0af68",
    text = "#c0caf5",
    overlay2 = "#9aa5ce",
    surface0 = "#414868",
  }

  vim.api.nvim_set_hl(0, "GitAdded", { fg = palette.green, default = true })
  vim.api.nvim_set_hl(0, "GitRemoved", { fg = palette.red, default = true })

  local base = vim.api.nvim_get_hl(0, { name = "Normal" })
  local normal_bg = base.bg and string.format("#%06x", base.bg) or "#1a1b26"

  local blended_green = util.blend_colors(palette.green, normal_bg, 0.08)
  local blended_red = util.blend_colors(palette.red, normal_bg, 0.10)
  local diff_ctx_bg = util.blend_colors(palette.surface0, normal_bg, 0.06)

  vim.api.nvim_set_hl(0, "GitDiffAddBackdrop", { bg = blended_green, default = true })
  vim.api.nvim_set_hl(0, "GitDiffDeleteBackdrop", { bg = blended_red, default = true })
  vim.api.nvim_set_hl(0, "GitDiffContextBackdrop", { bg = diff_ctx_bg, default = true })
  vim.api.nvim_set_hl(0, "GitDiffAddText", { fg = palette.text, default = true })
  vim.api.nvim_set_hl(0, "GitDiffDeleteText", { fg = palette.text, default = true })
  vim.api.nvim_set_hl(0, "GitDiffContextText", { fg = palette.overlay2, default = true })
  vim.api.nvim_set_hl(0, "GitRepoHeader", { fg = palette.yellow, bold = true, default = true })
  vim.api.nvim_set_hl(0, "DiffDelete", { fg = palette.red, bg = "NONE", default = true })
  vim.api.nvim_set_hl(0, "diffAdded", { link = "Normal", default = true })
  vim.api.nvim_set_hl(0, "diffRemoved", { link = "DiffDelete", default = true })
end

--------------------------------------------------------------------------------
-- Diff Buffer Rendering
--------------------------------------------------------------------------------
function M.render_diff_buffer(buf, diff_lines, opts)
  opts = opts or {}
  local display_lines = {}
  local line_meta = {}
  local line_to_file_line = {}
  local filetype = opts.filetype
  local current_path = opts.path

  local function maybe_apply_file(path)
    if not path or path == "/dev/null" then return end
    current_path = path
    local ft = vim.filetype.match({ filename = path })
    if ft and ft ~= "diff" then
      filetype = ft
    end
  end

  local current_new_line = 0
  for _, line in ipairs(diff_lines) do
    do
      local _, b_path = line:match("^diff %-%-git a/(.-)%s+b/(.+)$")
      if b_path and b_path ~= "" and b_path ~= "/dev/null" then
        maybe_apply_file(b_path)
      end
    end

    if line:match("^@@") then
      local new_start = line:match("^@@ %-%d+,%d+ %+(%d+)")
      if new_start then
        current_new_line = tonumber(new_start)
      end
      table.insert(display_lines, line)
      line_meta[#display_lines] = "header"
      local path = line:match("^%+%+%+ b/(.+)$") or line:match("^%-%-%- a/(.+)$")
      maybe_apply_file(path)
    elseif line:match("^diff %-%-git") or line:match("^index ") or line:match("^%-%-%-") or line:match("^%+%+%+") then
      table.insert(display_lines, line)
      line_meta[#display_lines] = "header"
      local path = line:match("^%+%+%+ b/(.+)$") or line:match("^%-%-%- a/(.+)$")
      maybe_apply_file(path)
    elseif vim.startswith(line, "+") and not vim.startswith(line, "+++") then
      table.insert(display_lines, line:sub(2))
      line_meta[#display_lines] = "add"
      line_to_file_line[#display_lines] = current_new_line
      current_new_line = current_new_line + 1
    elseif vim.startswith(line, "-") and not vim.startswith(line, "---") then
      table.insert(display_lines, line:sub(2))
      line_meta[#display_lines] = "remove"
    elseif vim.startswith(line, " ") then
      table.insert(display_lines, line:sub(2))
      line_meta[#display_lines] = "context"
      line_to_file_line[#display_lines] = current_new_line
      current_new_line = current_new_line + 1
    else
      table.insert(display_lines, line)
      line_meta[#display_lines] = "header"
    end
  end

  if #display_lines == 0 then
    display_lines = { "(no changes)" }
    line_meta[1] = "header"
  end

  if not vim.api.nvim_buf_is_valid(buf) then
    return filetype, current_path, line_to_file_line
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)
  vim.api.nvim_buf_clear_namespace(buf, M.highlight_ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, M.virt_ns, 0, -1)

  for idx, kind in ipairs(line_meta) do
    local lnum = idx - 1
    if kind == "add" then
      vim.api.nvim_buf_add_highlight(buf, M.highlight_ns, "GitDiffAddBackdrop", lnum, 0, -1)
      vim.api.nvim_buf_set_extmark(buf, M.virt_ns, lnum, 0, {
        virt_text = { { "+", "GitAdded" } },
        virt_text_pos = "inline",
      })
    elseif kind == "remove" then
      vim.api.nvim_buf_add_highlight(buf, M.highlight_ns, "GitDiffDeleteBackdrop", lnum, 0, -1)
      vim.api.nvim_buf_set_extmark(buf, M.virt_ns, lnum, 0, {
        virt_text = { { "-", "GitRemoved" } },
        virt_text_pos = "inline",
      })
    elseif kind == "context" then
      vim.api.nvim_buf_add_highlight(buf, M.highlight_ns, "GitDiffContextBackdrop", lnum, 0, -1)
    elseif kind == "header" then
      vim.api.nvim_buf_add_highlight(buf, M.highlight_ns, "GitDiffContextBackdrop", lnum, 0, -1)
      vim.api.nvim_buf_add_highlight(buf, M.highlight_ns, "Title", lnum, 0, -1)
    end
  end

  if filetype then
    vim.api.nvim_set_option_value("filetype", filetype, { buf = buf })
    pcall(vim.treesitter.start, buf, filetype)
  else
    vim.api.nvim_set_option_value("filetype", "diff", { buf = buf })
  end

  return filetype, current_path, line_to_file_line
end

--------------------------------------------------------------------------------
-- Buffer Setup Helpers
--------------------------------------------------------------------------------
function M.setup_panel_buffer(buf)
  vim.opt_local.buftype = "nofile"
  vim.opt_local.bufhidden = "hide"
  vim.opt_local.swapfile = false
  vim.opt_local.number = false
  vim.opt_local.relativenumber = false
  vim.opt_local.cursorline = true
  vim.opt_local.wrap = false
  vim.opt_local.linebreak = false
  vim.opt_local.breakindent = false
  vim.opt_local.showbreak = ""
  vim.bo[buf].filetype = "gitfiles"
  vim.fn.matchadd("GitAdded", [[\v\+\d+]], 100)
  vim.fn.matchadd("GitRemoved", [[\v-\d+]], 100)
end

function M.setup_diff_buffer()
  vim.opt_local.buftype = "nofile"
  vim.opt_local.bufhidden = "hide"
  vim.opt_local.swapfile = false
  vim.opt_local.wrap = false
  vim.opt_local.linebreak = false
  vim.opt_local.breakindent = false
  vim.opt_local.showbreak = ""
  vim.opt_local.signcolumn = "no"
end

--------------------------------------------------------------------------------
-- Cursor Helpers
--------------------------------------------------------------------------------
function M.safe_win_set_cursor(winid, line, col)
  if not (winid and vim.api.nvim_win_is_valid(winid)) then return end
  local buf = vim.api.nvim_win_get_buf(winid)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
  local maxline = vim.api.nvim_buf_line_count(buf)
  if maxline < 1 then return end
  if not line or line < 1 then line = 1 end
  if line > maxline then line = maxline end
  local l = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
  local maxcol = #l
  col = col or 0
  if col < 0 then col = 0 end
  if col > maxcol then col = maxcol end
  vim.api.nvim_win_set_cursor(winid, { line, col })
end

return M
