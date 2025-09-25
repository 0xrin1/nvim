local api = vim.api

local M = {}

function M.show_keybindings()
  local keybinds = {
    {"Keybindings:\n"},
    {"  <C-p> (Ctrl+P)     - Open file search (Telescope find_files)\n"},
    {"  <leader>fg (Space fg) - Live grep search (Telescope live_grep)\n"},
    {"  <leader>e  (Space e)  - Toggle file explorer (NvimTree)\n"},
    {"  <leader>gp (Space gp) - Preview Git hunk change\n"},
    {"  <leader>gu (Space gu) - Undo (reset) Git hunk\n"},
    {"  <leader>gU (Space gU) - Undo (reset) entire buffer Git changes\n"},
    {"  <leader>gn (Space gn) - Jump to next Git hunk\n"},
    {"  <leader>gN (Space gN) - Jump to previous Git hunk\n"},
    {"  <leader>gd (Space gd) - Open unified Git diff with side panel (top: changed files including untracked, bottom: nvim-tree, auto-updates on file changes)\n"},
    {"  <leader>gD (Space gD) - Open Git diff view (Diffview)\n"},
    {"Claude Code Keybindings (available in gd diff buffer):\n"},
    {"  <leader>ac  - Add diff to Claude\n"},
    {"  <leader>as (visual) - Send selection to Claude\n"},
    {"Other Claude Code Keybindings:\n"},
    {"  <leader>a   - AI/Claude Code\n"},
    {"  <leader>ac  - Toggle Claude\n"},
    {"  <leader>af  - Focus Claude\n"},
    {"  <leader>ar  - Resume Claude\n"},
    {"  <leader>aC  - Continue Claude\n"},
    {"  <leader>ab  - Add current buffer\n"},
    {"  <leader>as (visual) - Send to Claude\n"},
    {"  <leader>as (file tree) - Add file\n"},
    {"  <leader>aa  - Accept diff\n"},
    {"  <leader>ad  - Deny diff\n"},
    {"LSP Keybindings (after LSP attaches):\n"},
    {"  gD                 - Go to declaration\n"},
    {"  gd                 - Go to definition\n"},
    {"  K                  - Hover information\n"},
    {"  gi                 - Go to implementation\n"},
    {"  <C-k>              - Signature help\n"},
    {"  <leader>wa         - Add workspace folder\n"},
    {"  <leader>wr         - Remove workspace folder\n"},
    {"  <leader>wl         - List workspace folders\n"},
    {"  <leader>D          - Type definition\n"},
    {"  <leader>rn         - Rename\n"},
    {"  <leader>ca         - Code action\n"},
    {"  gr                 - References\n"},
    {"  <leader>f          - Format buffer\n"},
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

return M
