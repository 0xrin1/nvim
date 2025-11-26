local api = vim.api

local M = {}

function M.show_keybindings()
  local keybinds = {
    {"Keybindings:\\n"},
    {"  <C-p> (Ctrl+P)     - Open file search (Telescope find_files)\\n"},
    {"  <leader>fg (Space fg) - Live grep search (Telescope live_grep)\\n"},
    {"  <leader>e  (Space e)  - Toggle file explorer (NvimTree)\\n"},
    {"  gy                 - Copy selection with context to system clipboard\\n"},
    {"  <leader>gp (Space gp) - Preview Git hunk change\\n"},
    {"  <leader>gu (Space gu) - Undo (reset) Git hunk\\n"},
    {"  <leader>gU (Space gU) - Undo (reset) entire buffer Git changes\\n"},
    {"  <leader>gn (Space gn) - Jump to next Git hunk\\n"},
    {"  <leader>gN (Space gN) - Jump to previous Git hunk\\n"},
    {"  <leader>gd (Space gd) - Open unified Git diff with side panel (top: changed files including untracked, bottom: nvim-tree, auto-updates on file changes)\\n"},
    {"  <leader>gD (Space gD) - Open Git diff view (Diffview)\\n"},
    {"LSP Keybindings (after LSP attaches):\\n"},
    {"  gD                 - Go to declaration\\n"},
    {"  gd                 - Go to definition\\n"},
    {"  K                  - Hover information\\n"},
    {"  gi                 - Go to implementation\\n"},
    {"  <C-k>              - Signature help\\n"},
    {"  <leader>wa         - Add workspace folder\\n"},
    {"  <leader>wr         - Remove workspace folder\\n"},
    {"  <leader>wl         - List workspace folders\\n"},
    {"  <leader>D          - Type definition\\n"},
    {"  <leader>rn         - Rename\\n"},
    {"  <leader>ca         - Code action\\n"},
    {"  gr                 - References\\n"},
    {"  <leader>f          - Format buffer\\n"},
  }

  api.nvim_echo(keybinds, false, {})
end

api.nvim_create_user_command("Keys", function()
  M.show_keybindings()
end, {})

api.nvim_create_user_command("GitDiff", function()
  require("config.git_diff_panel").open()
end, {})

api.nvim_create_autocmd("VimEnter", {
  callback = function()
    if vim.fn.argc() == 0 then
      require("config.git_diff_panel").open()
    end
  end,
})



local function gy_copy_with_context()
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then return end
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
  local file = api.nvim_buf_get_name(0)
  local cwd = vim.fn.getcwd()
  local shown
  if file:sub(1, #cwd + 1) == cwd .. "/" then
    local top = cwd:match("([^/]+)$") or cwd
    local rel = file:sub(#cwd + 2)
    shown = top .. "/" .. rel
  else
    shown = file
  end
  local header = srow == erow and (shown .. ":" .. srow) or (shown .. ":" .. srow .. "-" .. erow)
  local payload = header .. "\n\n" .. table.concat(lines, "\n")
  if vim.fn.executable("pbcopy") == 1 then
    vim.fn.system("pbcopy", payload)
  else
    vim.fn.setreg("+", payload)
    vim.fn.setreg("*", payload)
  end
  vim.notify("Copied: " .. header)
end

vim.keymap.set("v", "gy", gy_copy_with_context, { noremap = true, silent = true, desc = "Copy selection with context to system clipboard" })

vim.keymap.set("n", "<leader>l", function()
  require("config.opencode_chat").open()
  vim.ui.input({ prompt = "opencode: " }, function(text)
    if text and text ~= "" then
      require("config.opencode_chat").send(text)
    end
  end)
end, { noremap = true, silent = true, desc = "Open opencode right-rail" })

vim.keymap.set("v", "<leader>l", function()
  local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "n", false)
  require("config.opencode_chat").open()
  vim.ui.input({ prompt = "opencode: " }, function(text)
    if text and text ~= "" then
      require("config.opencode_chat").send(text, { use_visual = true })
    end
  end)
end, { noremap = true, silent = true, desc = "Open opencode right-rail" })


return M
