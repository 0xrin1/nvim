local M = {}

--- Get the visual selection text as a list of lines, trimmed to the exact
--- selection bounds in characterwise mode. Returns nil if not in visual mode.
function M.get_visual_lines()
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then return nil end
  local s = vim.fn.getpos("'<")
  local e = vim.fn.getpos("'>")
  local srow, scol = s[2], s[3]
  local erow, ecol = e[2], e[3]
  if erow < srow or (erow == srow and ecol < scol) then
    srow, erow = erow, srow
    scol, ecol = ecol, scol
  end
  local lines = vim.api.nvim_buf_get_lines(0, srow - 1, erow, false)
  if mode == "v" then
    if #lines == 1 then
      lines[1] = string.sub(lines[1], scol, ecol)
    else
      lines[1] = string.sub(lines[1], scol)
      lines[#lines] = string.sub(lines[#lines], 1, ecol)
    end
  end
  return lines, srow, erow
end

--- Return a display path like "project/relative/path.lua" for the current buffer.
--- Falls back to the absolute path if the file is outside cwd.
function M.display_path(file, cwd)
  file = file or vim.api.nvim_buf_get_name(0)
  cwd = cwd or vim.fn.getcwd()
  if file:sub(1, #cwd + 1) == cwd .. "/" then
    local top = cwd:match("([^/]+)$") or cwd
    return top .. "/" .. file:sub(#cwd + 2)
  end
  return file
end

return M
