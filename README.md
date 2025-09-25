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
