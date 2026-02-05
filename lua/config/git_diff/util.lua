local M = {}

local uv = vim.loop

--------------------------------------------------------------------------------
-- Path Utilities
--------------------------------------------------------------------------------
function M.path_join(a, b)
  if not a or a == "" then return b end
  if not b or b == "" then return a end
  if a:sub(-1) == "/" then return a .. b end
  return a .. "/" .. b
end

function M.is_dir(path)
  local st = uv.fs_stat(path)
  return st and st.type == "directory" or false
end

function M.is_file(path)
  local st = uv.fs_stat(path)
  return st and st.type == "file" or false
end

function M.is_git_repo(dir)
  local dotgit = M.path_join(dir, ".git")
  return M.is_dir(dotgit) or M.is_file(dotgit)
end

function M.split_path_components(path)
  local parts = {}
  for part in path:gmatch("[^/]+") do
    table.insert(parts, part)
  end
  return parts
end

function M.rel_to(from, target)
  local norm_from = from:gsub("/+", "/")
  local norm_t = target:gsub("/+", "/")
  if norm_t:sub(1, #norm_from) == norm_from then
    local rest = norm_t:sub(#norm_from + 1)
    if rest:sub(1, 1) == "/" then rest = rest:sub(2) end
    return rest ~= "" and rest or "."
  end
  return target
end

function M.get_mtime(path)
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

function M.blend_colors(fg, bg, alpha)
  local fr, fg_, fb = hex_to_rgb(fg)
  local br, bg_, bb = hex_to_rgb(bg)
  local function mix(f, b)
    return math.floor((alpha * f) + ((1 - alpha) * b) + 0.5)
  end
  return rgb_to_hex(mix(fr, br), mix(fg_, bg_), mix(fb, bb))
end

--------------------------------------------------------------------------------
-- Filetype Resolution
--------------------------------------------------------------------------------
function M.resolve_filetype(path)
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

return M
