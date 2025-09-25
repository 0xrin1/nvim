local M = {}

local highlight_ns = vim.api.nvim_create_namespace("GitDiffPanelHighlights")
local virt_ns = vim.api.nvim_create_namespace("GitDiffPanelVirtText")

local function hex_to_rgb(color)
  color = color:gsub("#", "")
  if #color ~= 6 then
    return 0, 0, 0
  end
  return tonumber(color:sub(1, 2), 16), tonumber(color:sub(3, 4), 16), tonumber(color:sub(5, 6), 16)
end

local function rgb_to_hex(r, g, b)
  return string.format("#%02x%02x%02x", r, g, b)
end

local function blend_colors(fg, bg, alpha)
  local fr, fg_, fb = hex_to_rgb(fg)
  local br, bg_, bb = hex_to_rgb(bg)
  local function mix(f, b)
    return math.floor((alpha * f) + ((1 - alpha) * b) + 0.5)
  end
  return rgb_to_hex(mix(fr, br), mix(fg_, bg_), mix(fb, bb))
end

local function render_diff_buffer(buf, diff_lines, opts)
  opts = opts or {}
  local display_lines = {}
  local line_meta = {}
  local filetype = opts.filetype
  local current_path = opts.path

  local function maybe_apply_file(path)
    if not path or path == "/dev/null" then
      return
    end
    current_path = path
    local ft = vim.filetype.match({ filename = path })
    if ft and ft ~= "diff" then
      filetype = ft
    end
  end

  for _, line in ipairs(diff_lines) do
    if line:match("^diff %-%-git") or line:match("^index ") or line:match("^@@") or line:match("^[-+]{3}") then
      table.insert(display_lines, line)
      line_meta[#display_lines] = "header"
      local path = line:match("^%+%+%+ b/(.+)$") or line:match("^%-%-%- a/(.+)$")
      maybe_apply_file(path)
    elseif vim.startswith(line, "+") and not vim.startswith(line, "+++") then
      table.insert(display_lines, line:sub(2))
      line_meta[#display_lines] = "add"
    elseif vim.startswith(line, "-") and not vim.startswith(line, "---") then
      table.insert(display_lines, line:sub(2))
      line_meta[#display_lines] = "remove"
    elseif vim.startswith(line, " ") then
      table.insert(display_lines, line:sub(2))
      line_meta[#display_lines] = "context"
    else
      table.insert(display_lines, line)
      line_meta[#display_lines] = "header"
    end
  end

  if #display_lines == 0 then
    display_lines = { "(no changes)" }
    line_meta[1] = "header"
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)
  vim.api.nvim_buf_clear_namespace(buf, highlight_ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, virt_ns, 0, -1)

  for idx, kind in ipairs(line_meta) do
    local lnum = idx - 1
    if kind == "add" then
      vim.api.nvim_buf_add_highlight(buf, highlight_ns, "GitDiffAddBackdrop", lnum, 0, -1)
      vim.api.nvim_buf_set_extmark(buf, virt_ns, lnum, 0, {
        virt_text = { { "+", "GitAdded" } },
        virt_text_pos = "inline",
      })
    elseif kind == "remove" then
      vim.api.nvim_buf_add_highlight(buf, highlight_ns, "GitDiffDeleteBackdrop", lnum, 0, -1)
      vim.api.nvim_buf_set_extmark(buf, virt_ns, lnum, 0, {
        virt_text = { { "-", "GitRemoved" } },
        virt_text_pos = "inline",
      })
    elseif kind == "context" then
      vim.api.nvim_buf_add_highlight(buf, highlight_ns, "GitDiffContextBackdrop", lnum, 0, -1)
    elseif kind == "header" then
      vim.api.nvim_buf_add_highlight(buf, highlight_ns, "GitDiffContextBackdrop", lnum, 0, -1)
      vim.api.nvim_buf_add_highlight(buf, highlight_ns, "Title", lnum, 0, -1)
    end
  end

  -- Treesitter
  if filetype then
    vim.api.nvim_set_option_value("filetype", filetype, { buf = buf })
    pcall(vim.treesitter.start, buf, filetype)
  else
    vim.api.nvim_set_option_value("filetype", "diff", { buf = buf })
  end

  return filetype, current_path
end

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

  local base = vim.api.nvim_get_hl_by_name("Normal", true)
  local normal_bg = base.background and string.format("#%06x", base.background) or "#1e1e2e"
  local normal_fg = base.foreground and string.format("#%06x", base.foreground) or palette.text

  local blended_green = blend_colors(palette.green, normal_bg, 0.18)
  local blended_red = blend_colors(palette.red, normal_bg, 0.22)

  vim.api.nvim_set_hl(0, "GitDiffAddBackdrop", {
    bg = blended_green,
    default = true,
  })
  vim.api.nvim_set_hl(0, "GitDiffDeleteBackdrop", {
    bg = blended_red,
    default = true,
  })
  vim.api.nvim_set_hl(0, "GitDiffContextBackdrop", {
    bg = blend_colors(palette.surface0, normal_bg, 0.18),
    default = true,
  })
  vim.api.nvim_set_hl(0, "GitDiffAddText", { fg = palette.text, default = true })
  vim.api.nvim_set_hl(0, "GitDiffDeleteText", { fg = palette.text, default = true })
  vim.api.nvim_set_hl(0, "GitDiffContextText", { fg = palette.overlay2, default = true })
  vim.api.nvim_set_hl(0, "DiffDelete", { fg = palette.red, bg = "NONE", default = true })
  vim.api.nvim_set_hl(0, "diffAdded", { link = "Normal", default = true })
  vim.api.nvim_set_hl(0, "diffRemoved", { link = "DiffDelete", default = true })

  vim.fn.matchadd('GitAdded', [[\v\+\d+]], 100)
  vim.fn.matchadd('GitRemoved', [[\v-\d+]], 100)

  vim.cmd("wincmd l")
  vim.cmd("enew")
  local diff_buf = vim.api.nvim_get_current_buf()
  vim.opt_local.buftype = "nofile"
  vim.opt_local.bufhidden = "wipe"
  vim.opt_local.swapfile = false
  vim.opt_local.wrap = false
  vim.opt_local.signcolumn = "no"

  local function resolve_filetype(path)
    if not path or path == "" then
      return nil
    end
    local ft = vim.filetype.match({ filename = path })
    if ft == nil or ft == "diff" then
      return nil
    end
    return ft
  end


  local function update_diff()
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

    render_diff_buffer(diff_buf, diff_output, { filetype = resolve_filetype(current_path) })
  end


  update_diff()

  local diff_win = vim.fn.bufwinid(diff_buf)
  if diff_win ~= -1 then
    vim.api.nvim_set_option_value("winhighlight", "CursorLine:CursorLine", { scope = "local", win = diff_win })
  end

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
      update_diff()
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
        local override_ft = resolve_filetype(path)
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
        render_diff_buffer(diff_buf, diff_output, { filetype = override_ft })
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
