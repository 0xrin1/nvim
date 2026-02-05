local M = {}

local uv = vim.loop
local git = require("config.git_diff.git")

local POLL_INTERVAL_MS = 500
local is_linux = vim.fn.has("unix") == 1 and vim.fn.has("mac") == 0

--------------------------------------------------------------------------------
-- Linux: Polling-based watcher (fs_event recursive mode doesn't work)
--------------------------------------------------------------------------------
local function setup_poll_watcher(state, on_change)
  state.poll_timer = uv.new_timer()
  state.last_status_hash = nil

  state.poll_timer:start(POLL_INTERVAL_MS, POLL_INTERVAL_MS, function()
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(state.panel_buf) then
        if state.poll_timer then
          pcall(function()
            state.poll_timer:stop()
            state.poll_timer:close()
          end)
          state.poll_timer = nil
        end
        return
      end

      local status_output = git.get_all_repos_status(state)
      local current_hash = vim.fn.sha256(status_output)

      if state.last_status_hash ~= current_hash then
        state.last_status_hash = current_hash
        on_change()
      end
    end)
  end)
end

--------------------------------------------------------------------------------
-- macOS/BSD: Native fs_event with recursive watching
--------------------------------------------------------------------------------
local function setup_fs_event_watcher(state, on_change)
  state.watcher = uv.new_fs_event()
  state.watcher:start(vim.fn.getcwd(), { recursive = true }, vim.schedule_wrap(function(err)
    if err then return end
    on_change()
  end))
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
function M.setup(state, on_change)
  if is_linux then
    setup_poll_watcher(state, on_change)
  else
    setup_fs_event_watcher(state, on_change)
  end
end

function M.cleanup(state)
  if state.watcher and state.watcher:is_active() then
    state.watcher:stop()
  end
  if state.poll_timer then
    state.poll_timer:stop()
    state.poll_timer:close()
    state.poll_timer = nil
  end
end

return M
