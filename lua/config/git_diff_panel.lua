local M = {}

function M.open()
  local api = require("nvim-tree.api")

  vim.cmd("leftabove 30vnew")
  vim.cmd("below split")
  api.tree.close()
  api.tree.open({ current_window = true })
  local tree_buf = vim.api.nvim_get_current_buf()

  vim.cmd("wincmd k")
  vim.cmd("resize 15")

  local panel_buf = vim.api.nvim_get_current_buf()
  vim.opt_local.buftype = "nofile"
  vim.opt_local.bufhidden = "wipe"
  vim.opt_local.swapfile = false
  vim.opt_local.number = false
  vim.opt_local.relativenumber = false
  vim.opt_local.cursorline = true
  vim.bo[panel_buf].filetype = "gitfiles"

  local palette = require("catppuccin.palettes").get_palette("mocha")
  vim.cmd('hi GitAdded guifg=' .. palette.green)
  vim.cmd('hi GitRemoved guifg=' .. palette.red)

  vim.fn.matchadd('GitAdded', '\\v\\+\\d+')
  vim.fn.matchadd('GitRemoved', '\\v-\\d+')

  vim.cmd("wincmd l")
  vim.cmd("enew")
  local diff_buf = vim.api.nvim_get_current_buf()
  vim.opt_local.filetype = "diff"
  vim.opt_local.buftype = "nofile"
  vim.opt_local.bufhidden = "wipe"
  vim.opt_local.swapfile = false

  local diff_win = vim.fn.bufwinid(diff_buf)

  vim.keymap.set("n", "<leader>ac", ":ClaudeCodeAdd %<CR>", { buffer = diff_buf, noremap = true, silent = true, desc = "Add diff to Claude" })
  vim.keymap.set("v", "<leader>as", "<cmd>ClaudeCodeSend<CR>", { buffer = diff_buf, noremap = true, silent = true, desc = "Send selection to Claude" })

  local row_to_info = {}

  local uv = vim.loop
  local last_refresh = 0
  local function refresh()
    local now = uv.now()
    if now - last_refresh < 500 then return end
    last_refresh = now

    if vim.api.nvim_buf_is_valid(panel_buf) then
      local tree = {}
      local function split_path(path)
        local parts = {}
        for part in path:gmatch("[^/]+") do
          table.insert(parts, part)
        end
        return parts
      end
      local function insert_into_tree(current, parts, entry)
        if #parts == 0 then return end
        if #parts == 1 then
          current[parts[1]] = entry
        else
          local dir = parts[1]
          if not current[dir] then
            current[dir] = { type = "dir", children = {} }
          end
          insert_into_tree(current[dir].children, { unpack(parts, 2) }, entry)
        end
      end

      local numstat = vim.fn.systemlist("git diff HEAD --numstat -M")
      for _, line in ipairs(numstat) do
        local added, removed, file_str = line:match("([-%d]+)\t([-%d]+)\t(.-)$")
        if added and file_str then
          local old_path, new_path = file_str:match("^{(.*) => (.*)}$")
          local is_rename = old_path ~= nil
          local file_path = is_rename and new_path or file_str
          local display = is_rename and (old_path .. " => " .. new_path) or nil
          local parts = split_path(file_path)
          local entry
          if added == "-" then
            entry = { type = "binary", is_untracked = false }
          else
            entry = { type = "file", added = tonumber(added), removed = tonumber(removed), is_untracked = false }
          end
          entry.display = display
          insert_into_tree(tree, parts, entry)
        end
      end

      local untracked = vim.fn.systemlist("git ls-files --others --exclude-standard")
      for _, untracked_file in ipairs(untracked) do
        if untracked_file ~= "" then
          local parts = split_path(untracked_file)
          local file_type = vim.fn.system("file -b " .. vim.fn.shellescape(untracked_file)):gsub("\n", "")
          local entry
          if file_type:find("text") then
            local file_lines = vim.fn.systemlist("cat " .. vim.fn.shellescape(untracked_file))
            local added = #file_lines
            entry = { type = "file", added = added, removed = 0, is_untracked = true }
          else
            entry = { type = "binary", is_untracked = true }
          end
          insert_into_tree(tree, parts, entry)
        end
      end

      local lines = {}
      row_to_info = {}
      local function build_lines(node, indent, current_path)
        local keys = {}
        for k in pairs(node) do table.insert(keys, k) end
        table.sort(keys)
        for _, key in ipairs(keys) do
          local child = node[key]
          if child.type == "dir" then
            table.insert(lines, indent .. key .. "/")
            local new_path = current_path .. (current_path == "" and "" or "/") .. key
            build_lines(child.children, indent .. "  ", new_path)
          else
            local display_name = child.display or key
            local line
            local full_path = current_path .. (current_path == "" and "" or "/") .. key
            if child.type == "binary" then
              line = indent .. display_name .. " (binary)"
            else
              line = indent .. display_name .. " +" .. child.added .. " -" .. child.removed
            end
            table.insert(lines, line)
            row_to_info[#lines] = { path = full_path, entry = child }
          end
        end
      end
      build_lines(tree, "", "")

      vim.api.nvim_buf_set_lines(panel_buf, 0, -1, false, lines)
    end

    if vim.api.nvim_buf_is_valid(diff_buf) then
      local diff_output = vim.fn.systemlist("git diff HEAD -M")
      local untracked = vim.fn.systemlist("git ls-files --others --exclude-standard")
      for _, untracked_file in ipairs(untracked) do
        if untracked_file ~= "" then
          local file_type = vim.fn.system("file -b " .. vim.fn.shellescape(untracked_file)):gsub("\n", "")
          table.insert(diff_output, "diff --git a/" .. untracked_file .. " b/" .. untracked_file)
          table.insert(diff_output, "new file mode 100644")
          if file_type:find("text") then
            local file_lines = vim.fn.systemlist("cat " .. vim.fn.shellescape(untracked_file))
            table.insert(diff_output, "--- /dev/null")
            table.insert(diff_output, "+++ b/" .. untracked_file)
            table.insert(diff_output, "@@ -0,0 +1," .. #file_lines .. " @@")
            for _, fline in ipairs(file_lines) do
              table.insert(diff_output, "+" .. fline)
            end
          else
            table.insert(diff_output, "Binary files /dev/null and b/" .. untracked_file .. " differ")
          end
        end
      end
      vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, diff_output)
      local diff_win_refresh = vim.fn.bufwinid(diff_buf)
      if diff_win_refresh ~= -1 then
        vim.api.nvim_win_call(diff_win_refresh, function()
          vim.cmd('normal zR')
        end)
      end
    end
  end

  refresh()

  local function load_file_diff(use_mouse_pos)
    local row
    if use_mouse_pos then
      local mouse = vim.fn.getmousepos()
      if vim.api.nvim_win_get_buf(mouse.winid) == panel_buf then
        vim.api.nvim_set_current_win(mouse.winid)
        vim.api.nvim_win_set_cursor(mouse.winid, { mouse.line, mouse.column - 1 })
      end
      row = mouse.line
    else
      local cursor = vim.api.nvim_win_get_cursor(0)
      row = cursor[1]
    end
    local info = row_to_info[row]
    if info then
      local path = info.path
      local entry = info.entry
      if entry.type == "file" or entry.type == "binary" then
        vim.cmd("wincmd l")
        local diff_output = {}
        if entry.type == "binary" then
          table.insert(diff_output, "Binary file differs")
        else
          if entry.is_untracked then
            local file_lines = vim.fn.systemlist("cat " .. vim.fn.shellescape(path))
            table.insert(diff_output, "diff --git a/" .. path .. " b/" .. path)
            table.insert(diff_output, "new file mode 100644")
            table.insert(diff_output, "--- /dev/null")
            table.insert(diff_output, "+++ b/" .. path)
            table.insert(diff_output, "@@ -0,0 +1," .. #file_lines .. " @@")
            for _, fline in ipairs(file_lines) do
              table.insert(diff_output, "+" .. fline)
            end
          else
            diff_output = vim.fn.systemlist("git diff HEAD -- " .. vim.fn.shellescape(path))
          end
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, diff_output)
        vim.opt_local.filetype = "diff"
        vim.cmd("normal gg")
        vim.cmd("normal zR")
      end
    end
  end

  vim.keymap.set("n", "<CR>", function() load_file_diff(false) end, { buffer = panel_buf, silent = true })
  vim.keymap.set("n", "<LeftMouse>", function() load_file_diff(true) end, { buffer = panel_buf, silent = true })
  vim.keymap.set("n", "<2-LeftMouse>", function() load_file_diff(true) end, { buffer = panel_buf, silent = true })

  local function tree_open_node(use_mouse)
    if use_mouse then
      local mouse = vim.fn.getmousepos()
      if vim.api.nvim_win_get_buf(mouse.winid) == tree_buf then
        vim.api.nvim_set_current_win(mouse.winid)
        vim.api.nvim_win_set_cursor(mouse.winid, { mouse.line, mouse.column - 1 })
      end
    end
    local node = api.tree.get_node_under_cursor()
    if node then
      if node.type == "directory" then
        api.node.open.edit(node)
      elseif node.type == "file" then
        vim.api.nvim_set_current_win(diff_win)
        vim.cmd("edit " .. vim.fn.fnameescape(node.absolute_path))
      end
    end
  end

  vim.keymap.set("n", "<CR>", function() tree_open_node(false) end, { buffer = tree_buf, silent = true })
  vim.keymap.set("n", "<2-LeftMouse>", function() tree_open_node(true) end, { buffer = tree_buf, silent = true })
  vim.keymap.set("n", "q", ":q<CR>", { buffer = panel_buf, silent = true })
  vim.keymap.set("n", "q", ":q<CR>", { buffer = diff_buf, silent = true })
  vim.keymap.set("n", "q", ":q<CR>", { buffer = tree_buf, silent = true })

  local watcher = uv.new_fs_event()
  watcher:start(vim.fn.getcwd(), { recursive = true }, vim.schedule_wrap(function(err)
    if err then return end
    refresh()
  end))

  local group = vim.api.nvim_create_augroup("GitDiffWatcher", { clear = true })
  local function add_unload_autocmd(buf)
    vim.api.nvim_create_autocmd("BufUnload", {
      group = group,
      buffer = buf,
      callback = function()
        if watcher:is_active() then watcher:stop() end
      end,
    })
  end
  add_unload_autocmd(panel_buf)
  add_unload_autocmd(diff_buf)
  add_unload_autocmd(tree_buf)
end

return M
