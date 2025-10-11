local M = {}

local highlight_ns = vim.api.nvim_create_namespace("GitDiffPanelHighlights")
local virt_ns = vim.api.nvim_create_namespace("GitDiffPanelVirtText")

-- Multi-repo settings (scoped to current working directory)
-- You can override via, e.g.: vim.g.git_multi_repo_max_depth = 3
local MAX_SCAN_DEPTH = vim.g.git_multi_repo_max_depth or 3
local REPO_RESCAN_INTERVAL_MS = vim.g.git_multi_repo_scan_interval_ms or 10000
local IGNORE_DIRS = {
  [".git"] = true,
  ["node_modules"] = true,
  [".venv"] = true,
  ["venv"] = true,
  [".direnv"] = true,
  [".next"] = true,
  [".cache"] = true,
  ["dist"] = true,
  ["build"] = true,
  ["target"] = true,
  ["out"] = true,
  [".turbo"] = true,
  [".yarn"] = true,
  [".pnpm-store"] = true,
  ["__pycache__"] = true,
}

local uv = vim.loop

local function path_join(a, b)
  if not a or a == "" then return b end
  if not b or b == "" then return a end
  if a:sub(-1) == "/" then return a .. b end
  return a .. "/" .. b
end

local function is_dir(path)
  local st = uv.fs_stat(path)
  return st and st.type == "directory" or false
end

local function is_file(path)
  local st = uv.fs_stat(path)
  return st and st.type == "file" or false
end

local function is_git_repo(dir)
  local dotgit = path_join(dir, ".git")
  return is_dir(dotgit) or is_file(dotgit)
end

local function split_path_components(path)
  local parts = {}
  for part in path:gmatch("[^/]+") do table.insert(parts, part) end
  return parts
end

local function rel_to(from, target)
  -- Return path of target relative to from. If not prefix, return target.
  local norm_from = from:gsub("/+", "/")
  local norm_t = target:gsub("/+", "/")
  if norm_t:sub(1, #norm_from) == norm_from then
    local rest = norm_t:sub(#norm_from + 1)
    if rest:sub(1, 1) == "/" then rest = rest:sub(2) end
    return rest ~= "" and rest or "."
  end
  return target
end

-- Discover all git repositories under root up to a max depth
local function discover_repos(root, max_depth)
  local repos = {}
  local seen = {}
  local function scan(dir, depth)
    if depth > max_depth then return end
    if seen[dir] then return end
    seen[dir] = true

    local is_repo = is_git_repo(dir)
    if is_repo then
      table.insert(repos, dir)
      if depth > 0 then
        return
      end
    end

    local req = uv.fs_scandir(dir)
    if not req then return end
    while true do
      local name, typ = uv.fs_scandir_next(req)
      if not name then break end
      if typ == "directory" then
        if not IGNORE_DIRS[name] then
          scan(path_join(dir, name), depth + 1)
        end
      end
    end
  end
  scan(root, 0)
  return repos
end

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
  local line_to_file_line = {}
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

  local current_new_line = 0
  for _, line in ipairs(diff_lines) do
    do
      local a_path, b_path = line:match("^diff %-%-git a/(.-)%s+b/(.+)$")
      if b_path and b_path ~= "" and b_path ~= "/dev/null" then
        maybe_apply_file(b_path)
      end
    end
    if line:match("^@@") then
      local new_start = line:match("^@@ %-%d+,%d+ %+(%d+)")
      if new_start then
        current_new_line = tonumber(new_start)
      end
      table.insert(display_lines, line)
      line_meta[#display_lines] = "header"
      local path = line:match("^%+%+%+ b/(.+)$") or line:match("^%-%-%- a/(.+)$")
      maybe_apply_file(path)
    elseif line:match("^diff %-%-git") or line:match("^index ") or line:match("^%-%-%-") or line:match("^%+%+%+") then
      table.insert(display_lines, line)
      line_meta[#display_lines] = "header"
      local path = line:match("^%+%+%+ b/(.+)$") or line:match("^%-%-%- a/(.+)$")
      maybe_apply_file(path)
    elseif vim.startswith(line, "+") and not vim.startswith(line, "+++") then
      table.insert(display_lines, line:sub(2))
      line_meta[#display_lines] = "add"
      line_to_file_line[#display_lines] = current_new_line
      current_new_line = current_new_line + 1
    elseif vim.startswith(line, "-") and not vim.startswith(line, "---") then
      table.insert(display_lines, line:sub(2))
      line_meta[#display_lines] = "remove"
    elseif vim.startswith(line, " ") then
      table.insert(display_lines, line:sub(2))
      line_meta[#display_lines] = "context"
      line_to_file_line[#display_lines] = current_new_line
      current_new_line = current_new_line + 1
    else
      table.insert(display_lines, line)
      line_meta[#display_lines] = "header"
    end
  end

  if #display_lines == 0 then
    display_lines = { "(no changes)" }
    line_meta[1] = "header"
  end

  if not vim.api.nvim_buf_is_valid(buf) then return filetype, current_path end
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

  if filetype then
    vim.api.nvim_set_option_value("filetype", filetype, { buf = buf })
    pcall(vim.treesitter.start, buf, filetype)
  else
    vim.api.nvim_set_option_value("filetype", "diff", { buf = buf })
  end

  return filetype, current_path, line_to_file_line
end

function M.open()
  local api = require("nvim-tree.api")

  vim.cmd("leftabove 30vnew")
  vim.cmd("below split")
  api.tree.close()
  api.tree.open({ current_window = true })
  local tree_buf = vim.api.nvim_get_current_buf()

  vim.cmd("wincmd k")
  local panel_buf = vim.api.nvim_get_current_buf()
  local panel_win = vim.fn.bufwinid(panel_buf)
  local tree_win = vim.fn.bufwinid(tree_buf)
  if panel_win ~= -1 and tree_win ~= -1 then
    local col_h = vim.api.nvim_win_get_height(panel_win) + vim.api.nvim_win_get_height(tree_win)
    local tree_h = math.max(1, math.floor(col_h * 0.30))
    local panel_h = math.max(1, col_h - tree_h)
    vim.api.nvim_win_set_height(panel_win, panel_h)
  end
  vim.opt_local.buftype = "nofile"
  vim.opt_local.bufhidden = "hide"
  vim.opt_local.swapfile = false
  vim.opt_local.number = false
  vim.opt_local.relativenumber = false
  vim.opt_local.cursorline = true
  vim.opt_local.wrap = false
  vim.opt_local.linebreak = false
  vim.opt_local.breakindent = false
  vim.opt_local.showbreak = ""
  vim.bo[panel_buf].filetype = "gitfiles"

  local palette = require("catppuccin.palettes").get_palette("mocha")
  vim.cmd('hi GitAdded guifg=' .. palette.green)
  vim.cmd('hi GitRemoved guifg=' .. palette.red)

  local base = vim.api.nvim_get_hl_by_name("Normal", true)
  local normal_bg = base.background and string.format("#%06x", base.background) or "#1e1e2e"

  local blended_green = blend_colors(palette.green, normal_bg, 0.08)
  local blended_red = blend_colors(palette.red, normal_bg, 0.10)
  local diff_ctx_bg = blend_colors(palette.surface0, normal_bg, 0.06)

  vim.api.nvim_set_hl(0, "GitDiffAddBackdrop", {
    bg = blended_green,
    default = true,
  })
  vim.api.nvim_set_hl(0, "GitDiffDeleteBackdrop", {
    bg = blended_red,
    default = true,
  })
  vim.api.nvim_set_hl(0, "GitDiffContextBackdrop", {
    bg = diff_ctx_bg,
    default = true,
  })
  vim.api.nvim_set_hl(0, "GitDiffAddText", { fg = palette.text, default = true })
  vim.api.nvim_set_hl(0, "GitDiffDeleteText", { fg = palette.text, default = true })
  vim.api.nvim_set_hl(0, "GitDiffContextText", { fg = palette.overlay2, default = true })
  vim.api.nvim_set_hl(0, "GitRepoHeader", { fg = palette.yellow, bold = true, default = true })
  vim.api.nvim_set_hl(0, "DiffDelete", { fg = palette.red, bg = "NONE", default = true })
  vim.api.nvim_set_hl(0, "diffAdded", { link = "Normal", default = true })
  vim.api.nvim_set_hl(0, "diffRemoved", { link = "DiffDelete", default = true })

  vim.fn.matchadd('GitAdded', [[\v\+\d+]], 100)
  vim.fn.matchadd('GitRemoved', [[\v-\d+]], 100)
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = panel_buf,
    callback = function()
      if vim.api.nvim_buf_is_valid(diff_buf) then vim.api.nvim_buf_delete(diff_buf, { force = true }) end
    end,
  })

  vim.cmd("wincmd l")
  vim.cmd("enew")
  local diff_buf = vim.api.nvim_get_current_buf()
  vim.opt_local.buftype = "nofile"
  vim.opt_local.bufhidden = "hide"
  vim.opt_local.swapfile = false
  vim.opt_local.wrap = false
  vim.opt_local.linebreak = false
  vim.opt_local.breakindent = false
  vim.opt_local.showbreak = ""
  vim.opt_local.signcolumn = "no"

  local function resolve_filetype(path)
    if not path or path == "" then
      return nil
    end
    local ft = vim.filetype.match({ filename = path })
    if ft == nil or ft == "diff" then
      local ext = path:match("%.([%w]+)$")
      if ext == nil then return nil end
      if ext == "ts" then return "typescript" end
      if ext == "tsx" then return "typescriptreact" end
      if ext == "js" then return "javascript" end
      if ext == "jsx" then return "javascriptreact" end
      if ext == "lua" then return "lua" end
      if ext == "py" then return "python" end
      if ext == "rs" then return "rust" end
      if ext == "go" then return "go" end
      if ext == "rb" then return "ruby" end
      if ext == "sh" or ext == "bash" then return "sh" end
      if ext == "json" then return "json" end
      if ext == "yml" or ext == "yaml" then return "yaml" end
      if ext == "md" or ext == "markdown" then return "markdown" end
      if ext == "css" then return "css" end
      if ext == "scss" then return "scss" end
      return nil
    end
    return ft
  end

  -- Legacy single-repo summary is superseded by multi-repo aggregation.
  local function update_diff(_initial_path)
    return render_diff_buffer(diff_buf, {}, {})
  end

  local function pick_latest_path()
    return nil
  end

  local diff_win = vim.fn.bufwinid(diff_buf)
  if diff_win ~= -1 then
    vim.api.nvim_set_option_value("winhighlight", "CursorLine:CursorLine", { scope = "local", win = diff_win })
  end

  local function safe_win_set_cursor(winid, line, col)
    if not (winid and vim.api.nvim_win_is_valid(winid)) then return end
    local buf = vim.api.nvim_win_get_buf(winid)
    if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
    local maxline = vim.api.nvim_buf_line_count(buf)
    if maxline < 1 then return end
    if not line or line < 1 then line = 1 end
    if line > maxline then line = maxline end
    local l = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
    local maxcol = #l
    col = col or 0
    if col < 0 then col = 0 end
    if col > maxcol then col = maxcol end
    vim.api.nvim_win_set_cursor(winid, { line, col })
  end

  local row_to_info = {}
  local path_to_entry = {}
  local collapsed_repos = {}
  local resolved_path = nil
  local current_line_mapping = {}

  local last_refresh = 0
  local last_repo_scan = 0
  local cached_repos = nil

  local function git_systemlist(repo_root, subcmd)
    local cmd = string.format("git -C %s %s", vim.fn.shellescape(repo_root), subcmd)
    return vim.fn.systemlist(cmd)
  end

  local project_root = vim.fn.getcwd()

  local function ensure_repos(force)
    local now = uv.now()
    if force or not cached_repos or now - last_repo_scan > REPO_RESCAN_INTERVAL_MS then
      cached_repos = discover_repos(project_root, MAX_SCAN_DEPTH)
      last_repo_scan = now
    end
    return cached_repos or {}
  end

  local last_selected_mtime = 0
  local function get_mtime(path)
    local st = uv.fs_stat(path)
    if not st then return 0 end
    local m = st.mtime
    if type(m) == "table" then
      local sec = m.sec or 0
      local nsec = m.nsec or 0
      return sec + nsec / 1e9
    end
    return m or 0
  end

  local function focus_row_for_path(path)
    if not path then return end
    local winid = vim.fn.bufwinid(panel_buf)
    if winid ~= -1 and vim.api.nvim_win_is_valid(winid) then
      for row, info in pairs(row_to_info) do
        if info.path == path then
          vim.api.nvim_win_set_cursor(winid, { row, 0 })
          break
        end
      end
    end
  end

  local function pick_latest_changed_with_mtime()
    local best_path, best_m = nil, 0
    for p, _ in pairs(path_to_entry) do
      local mt = get_mtime(p)
      if mt > best_m then
        best_m = mt
        best_path = p
      end
    end
    return best_path, best_m
  end

  local function refresh()
    local now = uv.now()
    if now - last_refresh < 500 then return end
    last_refresh = now

    if not (vim.api.nvim_buf_is_valid(panel_buf) and vim.api.nvim_buf_is_loaded(panel_buf)) then return end
    local lines = {}
    row_to_info = {}
    path_to_entry = {}

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

    local function build_lines(node, indent, repo_prefix, repo_rel_path)
      local keys = {}
      for k in pairs(node) do table.insert(keys, k) end
      table.sort(keys)
      for _, key in ipairs(keys) do
        local child = node[key]
        if child.type == "dir" then
          table.insert(lines, indent .. key .. "/")
          local new_rel = repo_rel_path .. (repo_rel_path == "" and "" or "/") .. key
          build_lines(child.children, indent .. "  ", repo_prefix, new_rel)
        else
          local display_name = child.display or key
          local line
          local in_repo_rel = repo_rel_path .. (repo_rel_path == "" and "" or "/") .. key
          local full_project_rel = repo_prefix ~= "" and path_join(repo_prefix, in_repo_rel) or in_repo_rel
          if child.type == "binary" then
            line = indent .. display_name .. " (binary)"
          else
            line = indent .. display_name .. " +" .. child.added .. " -" .. child.removed
          end
          table.insert(lines, line)
          row_to_info[#lines] = { path = full_project_rel, entry = child }
          path_to_entry[full_project_rel] = child
        end
      end
    end

    local repos = ensure_repos(false)
    table.sort(repos)
    local header_rows = {}

    for _, repo_root in ipairs(repos) do
      local repo_rel = rel_to(project_root, repo_root)
      if repo_rel == "." then repo_rel = "" end

      local repo_tree = {}

      -- Modified files
      local numstat = git_systemlist(repo_root, "diff HEAD --numstat -M")
      for _, line in ipairs(numstat) do
        local added, removed, file_str = line:match("([-%d]+)\t([-%d]+)\t(.-)$")
        if added and file_str then
          local pre, old_mid, new_mid, post = file_str:match("^(.-){(.-) %=> (.-)}(.-)$")
          local is_rename = pre ~= nil
          local old_rel, new_rel
          if is_rename then
            old_rel = (pre or "") .. (old_mid or "") .. (post or "")
            new_rel = (pre or "") .. (new_mid or "") .. (post or "")
          end
          local repo_rel_file = is_rename and new_rel or file_str
          local display = is_rename and (old_rel .. " => " .. new_rel) or nil

          local entry
          if added == "-" then
            entry = { type = "binary", is_untracked = false }
          else
            entry = { type = "file", added = tonumber(added), removed = tonumber(removed), is_untracked = false }
          end
          entry.display = display
          entry.repo_root = repo_root
          entry.repo_relpath = repo_rel_file
          entry.abs_path = path_join(repo_root, repo_rel_file)

          insert_into_tree(repo_tree, split_path_components(repo_rel_file), entry)
        end
      end

      -- Untracked files
      local untracked = git_systemlist(repo_root, "ls-files --others --exclude-standard")
      for _, f in ipairs(untracked) do
        if f ~= "" then
          local abs_path = path_join(repo_root, f)
          local file_type = vim.fn.system("file -b " .. vim.fn.shellescape(abs_path)):gsub("\n", "")
          local entry
          if file_type:find("text") then
            local file_lines = vim.fn.systemlist("cat " .. vim.fn.shellescape(abs_path))
            entry = { type = "file", added = #file_lines, removed = 0, is_untracked = true }
          else
            entry = { type = "binary", is_untracked = true }
          end
          entry.repo_root = repo_root
          entry.repo_relpath = f
          entry.abs_path = abs_path

          insert_into_tree(repo_tree, split_path_components(f), entry)
        end
      end

      -- Only render header and tree if there are entries
      if next(repo_tree) ~= nil then
        local header_label = (repo_rel ~= "" and repo_rel or ".")
        local is_collapsed = collapsed_repos[repo_root] == true
        local header_text = "repo: " .. header_label .. (is_collapsed and " (collapsed)" or "")
        table.insert(lines, header_text)
        table.insert(header_rows, #lines)
        row_to_info[#lines] = { kind = "repo_header", repo_key = repo_root }
        if not is_collapsed then
          build_lines(repo_tree, "  ", repo_rel, "")
        end
        table.insert(lines, "")
      end
    end

    if not vim.api.nvim_buf_is_valid(panel_buf) then return end
    vim.api.nvim_buf_set_lines(panel_buf, 0, -1, false, lines)

    -- Highlight repo headers
    for _, row in ipairs(header_rows) do
      vim.api.nvim_buf_add_highlight(panel_buf, highlight_ns, "GitRepoHeader", row - 1, 0, -1)
    end
  end

  refresh()

  local function load_diff_for_path(path, entry)
    if not path or not entry then
      return
    end
    resolved_path = path
    if vim.api.nvim_win_is_valid(diff_win) then
      vim.api.nvim_set_current_win(diff_win)
    else
      vim.cmd("wincmd l")
    end
    if not vim.api.nvim_buf_is_valid(diff_buf) then
      vim.cmd("enew")
      diff_buf = vim.api.nvim_get_current_buf()
      vim.opt_local.buftype = "nofile"
      vim.opt_local.bufhidden = "hide"
      vim.opt_local.swapfile = false
      vim.opt_local.wrap = false
      vim.opt_local.signcolumn = "no"
    end
    if vim.api.nvim_get_current_buf() ~= diff_buf then
      vim.api.nvim_win_set_buf(0, diff_buf)
    end
    local diff_output = {}
    local override_ft = resolve_filetype(path)
    if entry.type == "binary" then
      table.insert(diff_output, "Binary file differs")
    else
      if entry.is_untracked then
        local file_lines = vim.fn.systemlist("cat " .. vim.fn.shellescape(entry.abs_path))
        table.insert(diff_output, "diff --git a/" .. entry.repo_relpath .. " b/" .. entry.repo_relpath)
        table.insert(diff_output, "new file mode 100644")
        table.insert(diff_output, "--- /dev/null")
        table.insert(diff_output, "+++ b/" .. entry.repo_relpath)
        table.insert(diff_output, "@@ -0,0 +1," .. #file_lines .. " @@")
        for _, fline in ipairs(file_lines) do
          table.insert(diff_output, "+" .. fline)
        end
      else
        diff_output = git_systemlist(entry.repo_root, "diff HEAD -- " .. vim.fn.shellescape(entry.repo_relpath))
      end
    end
    local _, _, line_mapping = render_diff_buffer(diff_buf, diff_output, { filetype = override_ft, path = path })
    current_line_mapping = line_mapping or {}
  end

  local function load_initial_diff()
    local target_path, mt = pick_latest_changed_with_mtime()
    if target_path and path_to_entry[target_path] then
      load_diff_for_path(target_path, path_to_entry[target_path])
      focus_row_for_path(target_path)
      last_selected_mtime = mt or 0
    else
      -- Find the first selectable row (skip headers/spacers)
      local first
      for i = 1, vim.api.nvim_buf_line_count(panel_buf) do
        local info = row_to_info[i]
        if info and info.entry then
          first = info
          break
        end
      end
      if first then
        load_diff_for_path(first.path, first.entry)
        focus_row_for_path(first.path)
        last_selected_mtime = get_mtime(first.path)
      else
        -- No changes at open: show placeholder in diff view
        render_diff_buffer(diff_buf, {}, {})
        resolved_path = nil
        last_selected_mtime = 0
      end
    end
  end

  load_initial_diff()

  local function load_file_diff(use_mouse_pos)
    if not (vim.api.nvim_buf_is_valid(panel_buf) and vim.api.nvim_buf_is_loaded(panel_buf)) then return end
    local row
    if use_mouse_pos then
      local mouse = vim.fn.getmousepos()
      if vim.api.nvim_win_get_buf(mouse.winid) == panel_buf then
        vim.api.nvim_set_current_win(mouse.winid)
        safe_win_set_cursor(mouse.winid, mouse.line, mouse.column - 1)
      end
      row = mouse.line
    else
      local cursor = vim.api.nvim_win_get_cursor(0)
      row = cursor[1]
    end
    local info = row_to_info[row]
    if info then
      load_diff_for_path(info.path, info.entry)
    end
  end

  vim.keymap.set("n", "<CR>", function() load_file_diff(false) end, { buffer = panel_buf, silent = true })
  vim.keymap.set("n", "<LeftMouse>", function() load_file_diff(true) end, { buffer = panel_buf, silent = true })
  vim.keymap.set("n", "<2-LeftMouse>", function()
    local mouse = vim.fn.getmousepos()
    if vim.api.nvim_win_get_buf(mouse.winid) == panel_buf then
      local line = mouse.line
      local info = row_to_info[line]
      if info and info.kind == "repo_header" and info.repo_key then
        collapsed_repos[info.repo_key] = not collapsed_repos[info.repo_key]
        refresh()
        return
      end
    end
    load_file_diff(true)
  end, { buffer = panel_buf, silent = true })

  local function tree_open_node(use_mouse)
    if use_mouse then
      local mouse = vim.fn.getmousepos()
      if vim.api.nvim_win_get_buf(mouse.winid) == tree_buf then
        vim.api.nvim_set_current_win(mouse.winid)
        safe_win_set_cursor(mouse.winid, mouse.line, mouse.column - 1)
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
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_buf_is_valid(panel_buf) then vim.api.nvim_buf_delete(panel_buf, { force = true }) end
    if vim.api.nvim_buf_is_valid(diff_buf) then vim.api.nvim_buf_delete(diff_buf, { force = true }) end
    if vim.api.nvim_buf_is_valid(tree_buf) then vim.api.nvim_buf_delete(tree_buf, { force = true }) end
  end, { buffer = panel_buf, silent = true })
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_buf_is_valid(panel_buf) then vim.api.nvim_buf_delete(panel_buf, { force = true }) end
    if vim.api.nvim_buf_is_valid(diff_buf) then vim.api.nvim_buf_delete(diff_buf, { force = true }) end
    if vim.api.nvim_buf_is_valid(tree_buf) then vim.api.nvim_buf_delete(tree_buf, { force = true }) end
  end, { buffer = diff_buf, silent = true })
  vim.keymap.set("n", "go", function()
    if resolved_path then
      local cursor_line = vim.fn.line(".")
      local file_line = current_line_mapping[cursor_line]
      local info = row_to_info[vim.fn.line(".")]
      local abs_path = info and info.entry and info.entry.abs_path or path_join(project_root, resolved_path)
      if abs_path and is_file(abs_path) then
        vim.cmd("edit " .. vim.fn.fnameescape(abs_path))
        if file_line then
          vim.api.nvim_win_set_cursor(0, { file_line, 0 })
        end
      end
    end
  end, { buffer = diff_buf, silent = true })
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_buf_is_valid(panel_buf) then vim.api.nvim_buf_delete(panel_buf, { force = true }) end
    if vim.api.nvim_buf_is_valid(diff_buf) then vim.api.nvim_buf_delete(diff_buf, { force = true }) end
    if vim.api.nvim_buf_is_valid(tree_buf) then vim.api.nvim_buf_delete(tree_buf, { force = true }) end
  end, { buffer = tree_buf, silent = true })

  local watcher = uv.new_fs_event()
  watcher:start(vim.fn.getcwd(), { recursive = true }, vim.schedule_wrap(function(err, fname, status)
    if err then return end
    if vim.api.nvim_buf_is_valid(panel_buf) then
      ensure_repos(false)
      refresh()
      local current_buf = vim.api.nvim_get_current_buf()
      if current_buf == diff_buf then
        local p, mt = pick_latest_changed_with_mtime()
        if p and path_to_entry[p] then
          if mt > last_selected_mtime or p ~= resolved_path then
            load_diff_for_path(p, path_to_entry[p])
            focus_row_for_path(p)
            last_selected_mtime = mt
          end
        else
          if vim.api.nvim_buf_is_valid(diff_buf) then
            render_diff_buffer(diff_buf, {}, {})
            resolved_path = nil
            last_selected_mtime = 0
          end
        end
      end
    end
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

  vim.api.nvim_create_autocmd({"BufWipeout","BufUnload"}, {
    buffer = diff_buf,
    callback = function()
      row_to_info = {}
      path_to_entry = {}
    end,
  })
end

return M
