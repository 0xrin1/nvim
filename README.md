# nvim

Diff-first Neovim config with live multi-repo git panel, LSP, and Telescope.

## Install

Requires Neovim >= 0.9, git, ripgrep.

```sh
git clone <this-repo> ~/.config/nvim
nvim  # plugins install automatically
```

## Keybindings

Run `:Keys` in nvim to see all bindings. Highlights:

| Key | Action |
|-----|--------|
| `<C-p>` | Find files |
| `<leader>fg` | Live grep |
| `<leader>e` | File tree |
| `<leader>gd` | Git diff panel |
| `<leader>gD` | Diffview |
| `<leader>gp/gu/gn/gN` | Hunk preview/reset/next/prev |
| `go` (in diff) | Open file at that line |
| `q` (in panel) | Close |
| `<C-\>` | Floating terminal |
| `gy` (visual) | Copy selection with file context |

## Layout

```
+---------------------------+------------------------------------------+
| Changed Files  +12 -4     | Unified Diff                             |
|   src/foo.lua  +12 -4     | @@ -1,5 +1,7 @@                          |
|   bar.ts       +3  -0     | -local old = 1                           |
|                            | +local new = 2                           |
|----------------------------|                                          |
| File Tree (nvim-tree)      |                                          |
+---------------------------+------------------------------------------+
```

Opens automatically on `nvim` with no file args. `<leader>gd` anytime.

## Config

| Setting | Default |
|---------|---------|
| `vim.g.git_multi_repo_max_depth` | 3 |
| `vim.g.git_multi_repo_scan_interval_ms` | 10000 |

Disable auto-open: remove the `VimEnter` autocmd in `lua/config/autocmds.lua`.

## Structure

```
lua/
  config/
    globals.lua        Leader key, filetype overrides
    options.lua        Vim options
    autocmds.lua       Commands, keymaps, auto-open
    util.lua           Shared helpers (visual selection, paths)
    opencode_chat.lua  OpenCode chat integration
    git_diff/
      init.lua         Entry point, keymaps, state
      git.lua          Git commands, repo discovery
      ui.lua           Diff rendering, highlights
      tree.lua         File tree building
      watcher.lua      File change detection
      util.lua         Path/color/filetype helpers
  plugins/             One file per plugin (lazy.nvim specs)
```

## Plugins

lazy.nvim, telescope, nvim-tree, gitsigns, vim-fugitive, diffview, mason + mason-lspconfig + nvim-lspconfig, nvim-cmp + luasnip, toggleterm, tokyonight.
