local M = {}

local chat_buf
local input_buf
local chat_win
local input_win
local last_ctx

local function ensure_windows()
  if chat_win and vim.api.nvim_win_is_valid(chat_win) and chat_buf and vim.api.nvim_buf_is_valid(chat_buf) and input_win and vim.api.nvim_win_is_valid(input_win) and input_buf and vim.api.nvim_buf_is_valid(input_buf) then
    return
  end
  vim.cmd("rightbelow 60vsplit")
  chat_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, chat_buf)
  chat_win = vim.api.nvim_get_current_win()
  vim.bo[chat_buf].buftype = "nofile"
  vim.bo[chat_buf].bufhidden = "hide"
  vim.bo[chat_buf].swapfile = false
  vim.wo[chat_win].number = false
  vim.wo[chat_win].relativenumber = false
  vim.wo[chat_win].wrap = true
  vim.wo[chat_win].signcolumn = "no"
  vim.cmd("below split")
  input_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, input_buf)
  input_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(input_win, 3)
  vim.bo[input_buf].buftype = "nofile"
  vim.bo[input_buf].bufhidden = "wipe"
  vim.bo[input_buf].swapfile = false
  vim.bo[input_buf].modifiable = true
  vim.wo[input_win].number = false
  vim.wo[input_win].relativenumber = false
  vim.wo[input_win].wrap = true
  vim.wo[input_win].signcolumn = "no"
  vim.api.nvim_buf_set_lines(chat_buf, 0, -1, false, {"opencode"})
  if vim.g.opencode_header and vim.g.opencode_header ~= "" then
    append_chat({"", vim.g.opencode_header})
  end
  vim.keymap.set("n", "q", function()
    if chat_win and vim.api.nvim_win_is_valid(chat_win) then vim.api.nvim_win_close(chat_win, true) end
    if input_win and vim.api.nvim_win_is_valid(input_win) then vim.api.nvim_win_close(input_win, true) end
    chat_buf, input_buf, chat_win, input_win = nil, nil, nil, nil
  end, { buffer = chat_buf, silent = true })
  vim.keymap.set("n", "q", function()
    if chat_win and vim.api.nvim_win_is_valid(chat_win) then vim.api.nvim_win_close(chat_win, true) end
    if input_win and vim.api.nvim_win_is_valid(input_win) then vim.api.nvim_win_close(input_win, true) end
    chat_buf, input_buf, chat_win, input_win = nil, nil, nil, nil
  end, { buffer = input_buf, silent = true })
end

local function append_chat(lines)
  if not (chat_buf and vim.api.nvim_buf_is_valid(chat_buf)) then return end
  local existing = vim.api.nvim_buf_get_lines(chat_buf, 0, -1, false)
  for _, l in ipairs(type(lines) == "table" and lines or {lines}) do table.insert(existing, l) end
  vim.api.nvim_buf_set_lines(chat_buf, 0, -1, false, existing)
  if chat_win and vim.api.nvim_win_is_valid(chat_win) then
    local lc = vim.api.nvim_buf_line_count(chat_buf)
    vim.api.nvim_win_set_cursor(chat_win, { lc, 0 })
  end
  last_ctx = current_context()
end

local function current_context(use_visual)
  local api = vim.api
  local buf = api.nvim_get_current_buf()
  local file = api.nvim_buf_get_name(buf)
  local cwd = vim.fn.getcwd()
  local rel
  if file:sub(1, #cwd + 1) == cwd .. "/" then
    local top = cwd:match("([^/]+)$") or cwd
    rel = top .. "/" .. file:sub(#cwd + 2)
  else
    rel = file
  end
  local pos = api.nvim_win_get_cursor(0)
  local line = pos[1]
  local col = pos[2] + 1
  local mode = use_visual and "v" or vim.fn.mode()
  local selection
  if mode == "v" or mode == "V" or mode == "\22" then
    local s = vim.fn.getpos("'<")
    local e = vim.fn.getpos("'>")
    local srow, scol = s[2], s[3]
    local erow, ecol = e[2], e[3]
    if erow < srow or (erow == srow and ecol < scol) then srow, erow = erow, srow; scol, ecol = ecol, scol end
    local lines = api.nvim_buf_get_lines(0, srow - 1, erow, false)
    if mode == "v" then
      if #lines == 1 then
        lines[1] = string.sub(lines[1], scol, ecol)
      else
        lines[1] = string.sub(lines[1], scol)
        lines[#lines] = string.sub(lines[#lines], 1, ecol)
      end
    end
    selection = table.concat(lines, "\n")
  end
  return { cwd = cwd, file = file, rel = rel, line = line, col = col, selection = selection }
end

local function send(prompt, opts)
  opts = opts or {}
  ensure_windows()
  ensure_windows()
  local url = vim.g.opencode_server_url
  if not url or url == "" then
    append_chat({"", "[no server configured: set vim.g.opencode_server_url]"})
    return
  end
  local ctx = current_context(opts.use_visual)
  local payload = { prompt = prompt, cwd = ctx.cwd, file = ctx.file, rel = ctx.rel, line = ctx.line, col = ctx.col, selection = ctx.selection }
  local data = vim.fn.json_encode(payload)
  append_chat({"", "> " .. prompt})
  local job = vim.fn.jobstart({ "curl", "-sS", "-X", "POST", "-H", "Content-Type: application/json", url, "--data-binary", "@-" }, {
    stdin = "pipe",
    on_stdout = function(_, out)
      if out and #out > 0 then append_chat(out) end
    end,
    on_stderr = function(_, err)
      if err and #err > 0 then append_chat(err) end
    end,
  })
  if job > 0 then
    vim.fn.chansend(job, data)
    vim.fn.chanclose(job, "stdin")
  else
    append_chat({"", "[failed to start curl]"})
  end
end

local function get_input_text()
  if not (input_buf and vim.api.nvim_buf_is_valid(input_buf)) then return "" end
  local lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
  local text = table.concat(lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
  return text
end

local function clear_input()
  if input_buf and vim.api.nvim_buf_is_valid(input_buf) then
    vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, {""})
  end
end

local function submit_input()
  local txt = get_input_text()
  if txt == "" then return end
  clear_input()
  send(txt)
end

M.send = send

function M.open()
  ensure_windows()
  if input_win and vim.api.nvim_win_is_valid(input_win) then vim.api.nvim_set_current_win(input_win) end
  vim.keymap.set("i", "<CR>", function()
    submit_input()
    return ""
  end, { buffer = input_buf, expr = true, silent = true })
  vim.keymap.set("n", "<CR>", function()
    submit_input()
  end, { buffer = input_buf, silent = true })
end

return M
