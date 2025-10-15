# Neovim Git Diff Panel — Diff‑First, Multi‑Repo Neovim Config

A fast, opinionated Neovim configuration that opens to a live unified Git diff panel with a project tree. Designed for code review, staging, and multi‑repo workflows. Includes Telescope, Nvim‑Tree, Gitsigns, Diffview, Fugitive, LSP (Mason + nvim‑lspconfig), nvim‑cmp + Copilot, Toggleterm, and Catppuccin.

> Demo: add a short GIF at docs/demo.gif for best results on GitHub

## Why this Neovim config for Git?
- Diff‑first startup: unified Git diff + project tree
- Multi‑repo aware (recursively scans nested repos)
- Live auto‑refresh on save and file changes
- One‑keystroke jump from diff to the exact file/line
- Rich Git UX: Gitsigns hunks, Fugitive commands, Diffview history/merges
- Productive defaults: Telescope, Nvim‑Tree, Toggleterm
- LSP in minutes: Mason + LSPConfig + nvim‑cmp (+ Copilot)
- Beautiful out of the box (Catppuccin Mocha), CUDA/PTX syntax

## Quick start (Install)
Prereqs: Neovim ≥ 0.9, git, ripgrep (for Telescope live_grep)

Option A
1) Back up your current config: `mv ~/.config/nvim ~/.config/nvim.bak`
2) Copy this folder to `~/.config/nvim`
3) Launch: `nvim` (lazy.nvim bootstraps automatically)

Option B
1) Clone this repo into `~/.config/nvim`
2) Launch: `nvim`

Tips
- First run installs plugins automatically; if not, run `:Lazy`
- `:Keys` shows keybindings at any time

## Usage
- Startup: with no file args, the diff panel opens by default
- Anytime: `<leader>gd` opens panel; `<leader>gD` opens Diffview
- Inside panel: `Enter` or double‑click previews a file’s diff, `go` opens the file at the mapped line, `q` closes
- Multi‑repo: panel aggregates changes from nested repos under your cwd

## Keybindings
- Files/search: `<C-p>` find files, `<leader>fg` live grep, `<leader>e` file tree
- Git panel: `<leader>gd` open, `Enter`/double‑click to preview a file’s diff, `q` close, `go` open file at cursor line
- Diffview: `<leader>gD` open
- Gitsigns: `<leader>gp` preview hunk, `<leader>gu` reset hunk, `<leader>gU` reset buffer, `<leader>gn` next hunk, `<leader>gN` prev hunk
- LSP: `gD` declaration, `gd` definition, `K` hover, `gi` implementation, `<C-k>` signature, `<leader>wa/wr/wl` workspace, `<leader>D` type, `<leader>rn` rename, `<leader>ca` code action, `gr` references, `<leader>f` format
- Terminal: `<C-\>` toggle floating terminal

## Layout (ASCII)
Default layout when opening the unified diff panel (`<leader>gd`):

```
+---------------------------+------------------------------------------------------+
| Changed Files             | Unified Diff                                         |
| src/                      | diff --git a/src/foo.lua b/src/foo.lua               |
|   foo.lua   +12 -4        | @@ -1,5 +1,7 @@                                      |
|   bar.ts    +3  -0        | -local old = 1                                       |
| README.md  +2  -0         | +local new = 2                                       |
|                           | ...                                                  |
|---------------------------+                                                      |
| File Tree                 |                                                      |
| project/                  |                                                      |
| ├─ src/                   |                                                      |
| │  ├─ foo.lua             |                                                      |
| │  └─ bar.ts              |                                                      |
| └─ README.md              |                                                      |
+---------------------------+------------------------------------------------------+
```

Notes
- Left: top shows changed files (+added/−removed), bottom shows project tree
- Right: unified diff with add/remove/context highlighting
- Keys: `<leader>gd` open, `Enter` to load diff, `q` close

## Customize
- Scan depth: set `vim.g.git_multi_repo_max_depth` (default 3)
- Rescan interval (ms): set `vim.g.git_multi_repo_scan_interval_ms` (default 10000)
- Theme: Catppuccin Mocha palette
- Disable auto‑open on start: remove the VimEnter autocmd in lua/config/autocmds.lua:45‑51
- Commands: `:Keys`, `:GitDiff`

## Plugin stack
- Core: [folke/lazy.nvim](https://github.com/folke/lazy.nvim)
- UI: [nvim-tree/nvim-tree.lua](https://github.com/nvim-tree/nvim-tree.lua), [catppuccin/nvim](https://github.com/catppuccin/nvim), [akinsho/toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim)
- Search: [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- Git: [lewis6991/gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim), [tpope/vim-fugitive](https://github.com/tpope/vim-fugitive), [sindrets/diffview.nvim](https://github.com/sindrets/diffview.nvim)
- LSP: [williamboman/mason.nvim](https://github.com/williamboman/mason.nvim), [williamboman/mason-lspconfig.nvim](https://github.com/williamboman/mason-lspconfig.nvim), [neovim/nvim-lspconfig](https://github.com/neovim/nvim-lspconfig)
- Completion: [hrsh7th/nvim-cmp](https://github.com/hrsh7th/nvim-cmp), [hrsh7th/cmp-nvim-lsp](https://github.com/hrsh7th/cmp-nvim-lsp), [hrsh7th/cmp-buffer](https://github.com/hrsh7th/cmp-buffer), [hrsh7th/cmp-path](https://github.com/hrsh7th/cmp-path), [L3MON4D3/LuaSnip](https://github.com/L3MON4D3/LuaSnip), [saadparwaiz1/cmp_luasnip](https://github.com/saadparwaiz1/cmp_luasnip), [zbirenbaum/copilot.lua](https://github.com/zbirenbaum/copilot.lua), [zbirenbaum/copilot-cmp](https://github.com/zbirenbaum/copilot-cmp)
- Extras: [bfrg/vim-cuda-syntax](https://github.com/bfrg/vim-cuda-syntax), [leafgarland/typescript-vim](https://github.com/leafgarland/typescript-vim)

## Notable mappings (source refs)
- Open diff panel mapping: lua/plugins/fugitive.lua:6
- Diffview mapping: lua/plugins/diffview.lua:86
- Panel keys: Enter/Double‑Click to preview, go to open, q to close (lua/config/git_diff_panel.lua:658‑711)
- `:Keys`/`:GitDiff` commands and auto‑open: lua/config/autocmds.lua:37‑51

## Troubleshooting
- Telescope `live_grep` requires ripgrep (`rg`) in PATH
- If highlights look off, ensure Catppuccin is installed and selected
- Neovim 0.9+ recommended (uses modern APIs)
- Health check: `:checkhealth`

## FAQ
- How do I revert to my old config? Move back your backup: `rm -rf ~/.config/nvim && mv ~/.config/nvim.bak ~/.config/nvim`
- How do I disable auto‑open diff on start? See lua/config/autocmds.lua:45‑51

## Search keywords
neovim git, neovim git diff, neovim git panel, unified diff, multi repo git, neovim config, neovim setup, vim git, gitsigns.nvim, diffview.nvim, vim‑fugitive, telescope.nvim, nvim‑tree, lazy.nvim, mason.nvim, nvim‑lspconfig, nvim‑cmp, copilot, toggleterm, catppuccin, code review, staging, developer productivity
