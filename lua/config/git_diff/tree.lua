local M = {}

local util = require("config.git_diff.util")

--- Insert a file entry into a nested tree structure based on its path components.
function M.insert(current, parts, entry)
  if #parts == 0 then return end
  if #parts == 1 then
    current[parts[1]] = entry
  else
    local dir = parts[1]
    if not current[dir] then
      current[dir] = { type = "dir", children = {} }
    end
    M.insert(current[dir].children, { unpack(parts, 2) }, entry)
  end
end

--- Recursively render a tree node into flat display lines, populating
--- state.row_to_info and state.path_to_entry as side effects.
function M.build_display_lines(node, indent, repo_prefix, repo_rel_path, lines, state)
  local keys = {}
  for k in pairs(node) do table.insert(keys, k) end
  table.sort(keys)

  for _, key in ipairs(keys) do
    local child = node[key]
    if child.type == "dir" then
      table.insert(lines, indent .. key .. "/")
      local new_rel = repo_rel_path .. (repo_rel_path == "" and "" or "/") .. key
      M.build_display_lines(child.children, indent .. "  ", repo_prefix, new_rel, lines, state)
    else
      local display_name = child.display or key
      local line
      local in_repo_rel = repo_rel_path .. (repo_rel_path == "" and "" or "/") .. key
      local full_project_rel = repo_prefix ~= "" and util.path_join(repo_prefix, in_repo_rel) or in_repo_rel

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

return M
