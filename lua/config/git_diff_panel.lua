local M = {}

--------------------------------------------------------------------------------
-- Constants & Config
--------------------------------------------------------------------------------
local MAX_SCAN_DEPTH = vim.g.git_multi_repo_max_depth or 3
local REPO_RESCAN_INTERVAL_MS = vim.g.git_multi_repo_scan_interval_ms or 10000
local REFRESH_THROTTLE_MS = 500

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

--------------------------------------------------------------------------------
-- Namespaces
--------------------------------------------------------------------------------
local highlight_ns = vim.api.nvim_create_namespace("GitDiffPanelHighlights")
local virt_ns = vim.api.nvim_create_namespace("GitDiffPanelVirtText")

--------------------------------------------------------------------------------
-- State (initialized per panel instance)
--------------------------------------------------------------------------------
local function create_state()
  return {
    -- Buffers & Windows
    panel_buf = nil,
    diff_buf = nil,
    tree_buf = nil,
    diff_win = nil,

    -- Data mappings
    row_to_info = {},
    path_to_entry = {},
    collapsed_repos = {},
    current_line_mapping = {},

    -- Current selection
    resolved_path = nil,
    last_selected_mtime = 0,

    -- Caching
    last_refresh = 0,
    last_repo_scan = 0,
    cached_repos = nil,

    -- Base paths
    project_root = vim.fn.getcwd(),

    -- File watcher
    watcher = nil,
  }
end

--------------------------------------------------------------------------------
-- Path Utilities
--------------------------------------------------------------------------------
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
  for part in path:gmatch("[^/]+") do
    table.insert(parts, part)
  end
  return parts
end

local function rel_to(from, target)
  local norm_from = from:gsub("/+", "/")
  local norm_t = target:gsub("/+", "/")
  if norm_t:sub(1, #norm_from) == norm_from then
    local rest = norm_t:sub(#norm_from + 1)
    if rest:sub(1, 1) == "/" then rest = rest:sub(2) end
    return rest ~= "" and rest or "."
  end
  return target
end

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

--------------------------------------------------------------------------------
-- Color Utilities
--------------------------------------------------------------------------------
local function hex_to_rgb(color)
  color = color:gsub("#", "")
  if #color ~= 6 then return 0, 0, 0 end
  return tonumber(color:sub(1, 2), 16),
         tonumber(color:sub(3, 4), 16),
         tonumber(color:sub(5, 6), 16)
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

--------------------------------------------------------------------------------
-- Git Operations
--------------------------------------------------------------------------------
local function git_systemlist(repo_root, subcmd)
  local cmd = string.format("git -C %s %s", vim.fn.shellescape(repo_root), subcmd)
  return vim.fn.systemlist(cmd)
end

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
      if depth > 0 then return end
    end

    local req = uv.fs_scandir(dir)
    if not req then return end
    while true do
      local name, typ = uv.fs_scandir_next(req)
      if not name then break end
      if typ == "directory" and not IGNORE_DIRS[name] then
        scan(path_join(dir, name), depth + 1)
      end
    end
  end

  scan(root, 0)
  return repos
end

local function ensure_repos(state, force)
  local now = uv.now()
  if force or not state.cached_repos or now - state.last_repo_scan > REPO_RESCAN_INTERVAL_MS then
    state.cached_repos = discover_repos(state.project_root, MAX_SCAN_DEPTH)
    state.last_repo_scan = now
  end
  return state.cached_repos or {}
end

local function resolve_filetype(path)
  if not path or path == "" then return nil end
  local ft = vim.filetype.match({ filename = path })
  if ft == nil or ft == "diff" then
    local ext = path:match("%.([%w]+)$")
    if ext == nil then return nil end
    local ext_map = {
      ts = "typescript", tsx = "typescriptreact",
      js = "javascript", jsx = "javascriptreact",
      lua = "lua", py = "python", rs = "rust", go = "go", rb = "ruby",
      sh = "sh", bash = "sh", json = "json",
      yml = "yaml", yaml = "yaml",
      md = "markdown", markdown = "markdown",
      css = "css", scss = "scss",
    }
    return ext_map[ext]
  end
  return ft
end

--------------------------------------------------------------------------------
-- Tree Building Helpers
--------------------------------------------------------------------------------
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

local function build_display_lines(node, indent, repo_prefix, repo_rel_path, lines, state)
  local keys = {}
  for k in pairs(node) do table.insert(keys, k) end
  table.sort(keys)

  for _, key in ipairs(keys) do
    local child = node[key]
    if child.type == "dir" then
      table.insert(lines, indent .. key .. "/")
      local new_rel = repo_rel_path .. (repo_rel_path == "" and "" or "/") .. key
      build_display_lines(child.children, indent .. "  ", repo_prefix, new_rel, lines, state)
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
      state.row_to_info[#lines] = { path = full_project_rel, entry = child }
      state.path_to_entry[full_project_rel] = child
    end
  end
end

--------------------------------------------------------------------------------
-- Diff Buffer Rendering
--------------------------------------------------------------------------------
local function render_diff_buffer(buf, diff_lines, opts)
  opts = opts or {}
  local display_lines = {}
  local line_meta = {}
  local line_to_file_line = {}
  local filetype = opts.filetype
  local current_path = opts.path

  local function maybe_apply_file(path)
    if not path or path == "/dev/null" then return end
    current_path = path
    local ft = vim.filetype.match({ filename = path })
    if ft and ft ~= "diff" then
      filetype = ft
    end
  end

  local current_new_line = 0
  for _, line in ipairs(diff_lines) do
    do
      local _, b_path = line:match("^diff %-%-git a/(.-)%s+b/(.+)$")
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

  if not vim.api.nvim_buf_is_valid(buf) then
    return filetype, current_path, line_to_file_line
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

  if filetype then
    vim.api.nvim_set_option_value("filetype", filetype, { buf = buf })
    pcall(vim.treesitter.start, buf, filetype)
  else
    vim.api.nvim_set_option_value("filetype", "diff", { buf = buf })
  end

  return filetype, current_path, line_to_file_line
end

--------------------------------------------------------------------------------
-- Highlight Setup
--------------------------------------------------------------------------------
local function setup_highlights()
  local palette = {
    green = "#9ece6a",
    red = "#f7768e",
    surface0 = "#414868"
  }

  vim.cmd('hi GitAdded guifg=' .. palette.green)
  vim.cmd('hi GitRemoved guifg=' .. palette.red)

  local base = vim.api.nvim_get_hl_by_name("Normal", true)
  local normal_bg = base.background and string.format("#%06x", base.background) or "#1a1b26"

  local blended_green = blend_colors(palette.green, normal_bg, 0.08)
  local blended_red = blend_colors(palette.red, normal_bg, 0.10)
  local diff_ctx_bg = blend_colors(palette.surface0, normal_bg, 0.06)

  vim.api.nvim_set_hl(0, "GitDiffAddBackdrop", { bg = blended_green, default = true })
  vim.api.nvim_set_hl(0, "GitDiffDeleteBackdrop", { bg = blended_red, default = true })
  vim.api.nvim_set_hl(0, "GitDiffContextBackdrop", { bg = diff_ctx_bg, default = true })
  vim.api.nvim_set_hl(0, "GitDiffAddText", { fg = palette.text, default = true })
  vim.api.nvim_set_hl(0, "GitDiffDeleteText", { fg = palette.text, default = true })
  vim.api.nvim_set_hl(0, "GitDiffContextText", { fg = palette.overlay2, default = true })
  vim.api.nvim_set_hl(0, "GitRepoHeader", { fg = palette.yellow, bold = true, default = true })
  vim.api.nvim_set_hl(0, "DiffDelete", { fg = palette.red, bg = "NONE", default = true })
  vim.api.nvim_set_hl(0, "diffAdded", { link = "Normal", default = true })
  vim.api.nvim_set_hl(0, "diffRemoved", { link = "DiffDelete", default = true })
end

--------------------------------------------------------------------------------
-- Panel Refresh (Git Data + UI Update)
--------------------------------------------------------------------------------
local function refresh_panel(state)
  local now = uv.now()
  if now - state.last_refresh < REFRESH_THROTTLE_MS then return end
  state.last_refresh = now

  if not (vim.api.nvim_buf_is_valid(state.panel_buf) and vim.api.nvim_buf_is_loaded(state.panel_buf)) then
    return
  end

  local lines = {}
  state.row_to_info = {}
  state.path_to_entry = {}

  local repos = ensure_repos(state, false)
  table.sort(repos)
  local header_rows = {}

  for _, repo_root in ipairs(repos) do
    local repo_rel = rel_to(state.project_root, repo_root)
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
        local entry

        -- Use native Lua file reading instead of spawning processes
        local fh = io.open(abs_path, "r")
        if fh then
          local content = fh:read(512)
          fh:close()
          local is_binary = content and content:find("\0") ~= nil
          if is_binary then
            entry = { type = "binary", is_untracked = true }
          else
            local wc_out = vim.fn.system("wc -l < " .. vim.fn.shellescape(abs_path))
            local line_count = tonumber(wc_out:match("%d+")) or 0
            entry = { type = "file", added = line_count, removed = 0, is_untracked = true }
          end
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
      local is_collapsed = state.collapsed_repos[repo_root] == true
      local header_text = "repo: " .. header_label .. (is_collapsed and " (collapsed)" or "")
      table.insert(lines, header_text)
      table.insert(header_rows, #lines)
      state.row_to_info[#lines] = { kind = "repo_header", repo_key = repo_root }
      if not is_collapsed then
        build_display_lines(repo_tree, "  ", repo_rel, "", lines, state)
      end
      table.insert(lines, "")
    end
  end

  if not vim.api.nvim_buf_is_valid(state.panel_buf) then return end
  vim.api.nvim_buf_set_lines(state.panel_buf, 0, -1, false, lines)

  -- Highlight repo headers
  for _, row in ipairs(header_rows) do
    vim.api.nvim_buf_add_highlight(state.panel_buf, highlight_ns, "GitRepoHeader", row - 1, 0, -1)
  end
end

--------------------------------------------------------------------------------
-- Diff Loading
--------------------------------------------------------------------------------
local function load_diff_for_path(state, path, entry, tree_api)
  if not path or not entry then return end

  state.resolved_path = path

  if vim.api.nvim_win_is_valid(state.diff_win) then
    vim.api.nvim_set_current_win(state.diff_win)
  else
    vim.cmd("wincmd l")
  end

  if not vim.api.nvim_buf_is_valid(state.diff_buf) then
    vim.cmd("enew")
    state.diff_buf = vim.api.nvim_get_current_buf()
    vim.opt_local.buftype = "nofile"
    vim.opt_local.bufhidden = "hide"
    vim.opt_local.swapfile = false
    vim.opt_local.wrap = false
    vim.opt_local.signcolumn = "no"
  end

  if vim.api.nvim_get_current_buf() ~= state.diff_buf then
    vim.api.nvim_win_set_buf(0, state.diff_buf)
  end

  local diff_output = {}
  local override_ft = resolve_filetype(path)

  if entry.type == "binary" then
    table.insert(diff_output, "Binary file differs")
  elseif entry.is_untracked then
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

  local _, _, line_mapping = render_diff_buffer(state.diff_buf, diff_output, { filetype = override_ft, path = path })
  state.current_line_mapping = line_mapping or {}

  -- Expand tree to show file
  if entry.abs_path and tree_api then
    local tree_win = vim.fn.bufwinid(state.tree_buf)
    if tree_win ~= -1 and vim.api.nvim_win_is_valid(tree_win) then
      local prev_win = vim.api.nvim_get_current_win()
      vim.api.nvim_set_current_win(tree_win)
      pcall(tree_api.tree.find_file, { path = entry.abs_path, focus = false, open = false })
      if vim.api.nvim_win_is_valid(prev_win) then
        vim.api.nvim_set_current_win(prev_win)
      end
    end
  end
end

local function pick_latest_changed_with_mtime(state)
  local best_path, best_m = nil, 0
  for p, _ in pairs(state.path_to_entry) do
    local mt = get_mtime(p)
    if mt > best_m then
      best_m = mt
      best_path = p
    end
  end
  return best_path, best_m
end

local function focus_row_for_path(state, path)
  if not path then return end
  local winid = vim.fn.bufwinid(state.panel_buf)
  if winid ~= -1 and vim.api.nvim_win_is_valid(winid) then
    for row, info in pairs(state.row_to_info) do
      if info.path == path then
        vim.api.nvim_win_set_cursor(winid, { row, 0 })
        break
      end
    end
  end
end

local function load_initial_diff(state, tree_api)
  local target_path, mt = pick_latest_changed_with_mtime(state)
  if target_path and state.path_to_entry[target_path] then
    load_diff_for_path(state, target_path, state.path_to_entry[target_path], tree_api)
    focus_row_for_path(state, target_path)
    state.last_selected_mtime = mt or 0
  else
    -- Find first selectable row
    for i = 1, vim.api.nvim_buf_line_count(state.panel_buf) do
      local info = state.row_to_info[i]
      if info and info.entry then
        load_diff_for_path(state, info.path, info.entry, tree_api)
        focus_row_for_path(state, info.path)
        state.last_selected_mtime = get_mtime(info.path)
        return
      end
    end
    -- No changes
    render_diff_buffer(state.diff_buf, {}, {})
    state.resolved_path = nil
    state.last_selected_mtime = 0
  end
end

--------------------------------------------------------------------------------
-- Cursor/Window Helpers
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- File Watcher
--------------------------------------------------------------------------------
local function setup_watcher(state, tree_api)
  state.watcher = uv.new_fs_event()
  state.watcher:start(vim.fn.getcwd(), { recursive = true }, vim.schedule_wrap(function(err)
    if err then return end
    if not vim.api.nvim_buf_is_valid(state.panel_buf) then return end

    ensure_repos(state, false)
    refresh_panel(state)

    local current_buf = vim.api.nvim_get_current_buf()
    if current_buf == state.diff_buf then
      local p, mt = pick_latest_changed_with_mtime(state)
      if p and state.path_to_entry[p] then
        if mt > state.last_selected_mtime or p ~= state.resolved_path then
          load_diff_for_path(state, p, state.path_to_entry[p], tree_api)
          focus_row_for_path(state, p)
          state.last_selected_mtime = mt
        end
      else
        if vim.api.nvim_buf_is_valid(state.diff_buf) then
          render_diff_buffer(state.diff_buf, {}, {})
          state.resolved_path = nil
          state.last_selected_mtime = 0
        end
      end
    end
  end))
end

local function cleanup_watcher(state)
  if state.watcher and state.watcher:is_active() then
    state.watcher:stop()
  end
end

--------------------------------------------------------------------------------
-- Keymap Setup
--------------------------------------------------------------------------------
local function setup_keymaps(state, tree_api)
  local function load_file_diff(use_mouse_pos)
    if not (vim.api.nvim_buf_is_valid(state.panel_buf) and vim.api.nvim_buf_is_loaded(state.panel_buf)) then
      return
    end

    local row
    if use_mouse_pos then
      local mouse = vim.fn.getmousepos()
      if vim.api.nvim_win_get_buf(mouse.winid) == state.panel_buf then
        vim.api.nvim_set_current_win(mouse.winid)
        safe_win_set_cursor(mouse.winid, mouse.line, mouse.column - 1)
      end
      row = mouse.line
    else
      local cursor = vim.api.nvim_win_get_cursor(0)
      row = cursor[1]
    end

    local info = state.row_to_info[row]
    if info and info.entry then
      load_diff_for_path(state, info.path, info.entry, tree_api)
    end
  end

  local function close_all()
    if vim.api.nvim_buf_is_valid(state.panel_buf) then vim.api.nvim_buf_delete(state.panel_buf, { force = true }) end
    if vim.api.nvim_buf_is_valid(state.diff_buf) then vim.api.nvim_buf_delete(state.diff_buf, { force = true }) end
    if vim.api.nvim_buf_is_valid(state.tree_buf) then vim.api.nvim_buf_delete(state.tree_buf, { force = true }) end
  end

  local function tree_open_node(use_mouse)
    if use_mouse then
      local mouse = vim.fn.getmousepos()
      if vim.api.nvim_win_get_buf(mouse.winid) == state.tree_buf then
        vim.api.nvim_set_current_win(mouse.winid)
        safe_win_set_cursor(mouse.winid, mouse.line, mouse.column - 1)
      end
    end
    local node = tree_api.tree.get_node_under_cursor()
    if node then
      if node.type == "directory" then
        tree_api.node.open.edit(node)
      elseif node.type == "file" then
        vim.api.nvim_set_current_win(state.diff_win)
        vim.cmd("edit " .. vim.fn.fnameescape(node.absolute_path))
      end
    end
  end

  -- Panel keymaps
  vim.keymap.set("n", "<CR>", function() load_file_diff(false) end, { buffer = state.panel_buf, silent = true })
  vim.keymap.set("n", "<LeftMouse>", function() load_file_diff(true) end, { buffer = state.panel_buf, silent = true })
  vim.keymap.set("n", "<2-LeftMouse>", function()
    local mouse = vim.fn.getmousepos()
    if vim.api.nvim_win_get_buf(mouse.winid) == state.panel_buf then
      local line = mouse.line
      local info = state.row_to_info[line]
      if info and info.kind == "repo_header" and info.repo_key then
        state.collapsed_repos[info.repo_key] = not state.collapsed_repos[info.repo_key]
        refresh_panel(state)
        return
      end
    end
    load_file_diff(true)
  end, { buffer = state.panel_buf, silent = true })
  vim.keymap.set("n", "q", close_all, { buffer = state.panel_buf, silent = true })

  -- Diff buffer keymaps
  vim.keymap.set("n", "q", close_all, { buffer = state.diff_buf, silent = true })
  vim.keymap.set("n", "go", function()
    if state.resolved_path then
      local cursor_line = vim.fn.line(".")
      local file_line = state.current_line_mapping[cursor_line]
      local info = state.row_to_info[vim.fn.line(".")]
      local abs_path = info and info.entry and info.entry.abs_path or path_join(state.project_root, state.resolved_path)
      if abs_path and is_file(abs_path) then
        vim.cmd("edit " .. vim.fn.fnameescape(abs_path))
        if file_line then
          vim.api.nvim_win_set_cursor(0, { file_line, 0 })
        end
      end
    end
  end, { buffer = state.diff_buf, silent = true })

  -- Tree keymaps
  vim.keymap.set("n", "<CR>", function() tree_open_node(false) end, { buffer = state.tree_buf, silent = true })
  vim.keymap.set("n", "<2-LeftMouse>", function() tree_open_node(true) end, { buffer = state.tree_buf, silent = true })
  vim.keymap.set("n", "q", close_all, { buffer = state.tree_buf, silent = true })
end

--------------------------------------------------------------------------------
-- Buffer Setup Helpers
--------------------------------------------------------------------------------
local function setup_panel_buffer(buf)
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
  vim.bo[buf].filetype = "gitfiles"
  vim.fn.matchadd('GitAdded', [[\v\+\d+]], 100)
  vim.fn.matchadd('GitRemoved', [[\v-\d+]], 100)
end

local function setup_diff_buffer()
  vim.opt_local.buftype = "nofile"
  vim.opt_local.bufhidden = "hide"
  vim.opt_local.swapfile = false
  vim.opt_local.wrap = false
  vim.opt_local.linebreak = false
  vim.opt_local.breakindent = false
  vim.opt_local.showbreak = ""
  vim.opt_local.signcolumn = "no"
end

--------------------------------------------------------------------------------
-- Main Entry Point
--------------------------------------------------------------------------------
function M.open()
  local tree_api = require("nvim-tree.api")
  local state = create_state()

  -- Create panel window (left side, top)
  vim.cmd("leftabove 30vnew")
  vim.cmd("below split")
  tree_api.tree.close()
  tree_api.tree.open({ current_window = true })
  state.tree_buf = vim.api.nvim_get_current_buf()

  -- Move to panel window
  vim.cmd("wincmd k")
  state.panel_buf = vim.api.nvim_get_current_buf()
  local panel_win = vim.fn.bufwinid(state.panel_buf)
  local tree_win = vim.fn.bufwinid(state.tree_buf)

  -- Set window heights (70% panel, 30% tree)
  if panel_win ~= -1 and tree_win ~= -1 then
    local col_h = vim.api.nvim_win_get_height(panel_win) + vim.api.nvim_win_get_height(tree_win)
    local tree_h = math.max(1, math.floor(col_h * 0.30))
    local panel_h = math.max(1, col_h - tree_h)
    vim.api.nvim_win_set_height(panel_win, panel_h)
  end

  setup_panel_buffer(state.panel_buf)
  setup_highlights()

  -- Create diff window (right side)
  vim.cmd("wincmd l")
  vim.cmd("enew")
  state.diff_buf = vim.api.nvim_get_current_buf()
  state.diff_win = vim.api.nvim_get_current_win()
  setup_diff_buffer()

  vim.api.nvim_set_option_value("winhighlight", "CursorLine:CursorLine", { scope = "local", win = state.diff_win })

  -- Initial data load
  refresh_panel(state)
  load_initial_diff(state, tree_api)

  -- Setup keymaps
  setup_keymaps(state, tree_api)

  -- Setup file watcher
  setup_watcher(state, tree_api)

  -- Cleanup autocmds
  local group = vim.api.nvim_create_augroup("GitDiffWatcher", { clear = true })
  local function add_cleanup_autocmd(buf)
    vim.api.nvim_create_autocmd("BufUnload", {
      group = group,
      buffer = buf,
      callback = function() cleanup_watcher(state) end,
    })
  end
  add_cleanup_autocmd(state.panel_buf)
  add_cleanup_autocmd(state.diff_buf)
  add_cleanup_autocmd(state.tree_buf)

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload" }, {
    buffer = state.diff_buf,
    callback = function()
      state.row_to_info = {}
      state.path_to_entry = {}
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = state.panel_buf,
    callback = function()
      if vim.api.nvim_buf_is_valid(state.diff_buf) then
        vim.api.nvim_buf_delete(state.diff_buf, { force = true })
      end
    end,
  })
end

return M
