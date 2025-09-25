# Diff-Focused Workflow

## Diff Snapshot
```
@@ lua/plugin/extras.lua @@
-  use("tpope/vim-fugitive")
+  use({
+    "tpope/vim-fugitive",
+    config = function()
+      require("diffview").setup()
+    end,
+  })
```

## Why It Amplifies LLM Sessions
- Highlights intent: the model sees removal and addition in one frame.
- Preserves context: adjacent lines travel with the hunk, lowering misinterpretation risk.
- Speeds iteration: precise hunks let you ask targeted follow-ups instead of re-explaining the file.
- Improves validation: shared diffs make reviewing, testing, and rollback decisions defensible.
- Scales collaboration: one diff artifact keeps humans and models aligned on the same change set.

## Diff View (ASCII)
This is a rough sketch of the layout you get when opening the unified diff panel (`<leader>gd`):

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

Notes:
- Left column: top shows changed files (with +added/-removed counts), bottom shows the project tree.
- Right pane: unified diff content with add/remove/context highlighting.
- Keys: `<leader>gd` to open, `<CR>` on a file in the left panel to load its diff, `q` to close.
