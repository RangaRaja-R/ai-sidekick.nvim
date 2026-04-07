local M = {}

M.defaults = {
  check = { "kitty", "@", "ls" },
  list = { "kitty", "@", "ls" },
  launch = { "kitty", "@", "launch", "--type=tab" },
  focus_tab = { "kitty", "@", "focus-tab", "--match" },
  send_text = { "kitty", "@", "send-text", "--stdin", "--match" },
  close_window = { "kitty", "@", "close-window", "--match" },
  shell = { "sh", "-lc" },
  title = "ai-sidekick",
}

local state = {
  window_id = nil,
  tab_id = nil,
}

local ROOT_USER_VAR = "AI_SIDEKICK_ROOT"

local function clone_argv(argv)
  return vim.deepcopy(argv)
end

local function normalize_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end

  return path:gsub("\\", "/"):gsub("/+$", "")
end

local function normalize_exec(arg)
  if type(arg) ~= "string" or arg == "" then
    return nil
  end

  local normalized = arg:gsub("\\", "/")
  local leaf = normalized:match("([^/]+)$")
  return leaf or normalized
end

local function cmdline_matches_provider(cmdline, provider_cmd)
  if type(cmdline) ~= "table" or type(provider_cmd) ~= "string" or provider_cmd == "" then
    return false
  end

  local provider_exec = normalize_exec(provider_cmd)
  if not provider_exec then
    return false
  end

  for _, arg in ipairs(cmdline) do
    local arg_exec = normalize_exec(arg)
    if arg_exec and (arg_exec == provider_exec or arg == provider_cmd) then
      return true
    end
  end

  return false
end

local function command(cfg, key, extra)
  local value = cfg[key]

  if type(value) == "function" then
    return value(extra)
  end

  if type(value) == "table" and not vim.tbl_isempty(value) then
    local argv = clone_argv(value)

    if extra then
      if type(extra) == "table" then
        vim.list_extend(argv, extra)
      else
        table.insert(argv, extra)
      end
    end

    return argv
  end

  return nil
end

local function list_data(cfg)
  local argv = command(cfg, "list")

  if not argv then
    return nil
  end

  local raw = vim.fn.system(argv)
  if vim.v.shell_error ~= 0 then
    return nil
  end

  local ok, data = pcall(vim.fn.json_decode, raw)
  if not ok or type(data) ~= "table" then
    return nil
  end

  return data
end

local function find_window(data, window_id)
  if not data or not window_id then
    return nil, nil
  end

  for _, os_window in ipairs(data) do
    for _, tab in ipairs(os_window.tabs or {}) do
      for _, win in ipairs(tab.windows or {}) do
        if tostring(win.id) == tostring(window_id) then
          return win, tab
        end
      end
    end
  end

  return nil, nil
end

local function refresh_state(cfg)
  if not state.window_id then
    return false
  end

  local _, tab = find_window(list_data(cfg), state.window_id)
  if not tab then
    state.window_id = nil
    state.tab_id = nil
    return false
  end

  state.tab_id = tab.id
  return true
end

local function title_has_sidekick(tab, win)
  local tab_title = string.lower(tab and tab.title or "")
  local win_title = string.lower(win and win.title or "")
  return tab_title:find("ai%-sidekick", 1, false) ~= nil or win_title:find("ai%-sidekick", 1, false) ~= nil
end

local function build_candidates(data, root, provider_cmd)
  local normalized_root = normalize_path(root)
  if not normalized_root then
    return {}
  end

  local candidates = {}

  for _, os_window in ipairs(data or {}) do
    for _, tab in ipairs(os_window.tabs or {}) do
      for _, win in ipairs(tab.windows or {}) do
        local user_vars = win.user_vars or {}
        local user_var_root = normalize_path(user_vars[ROOT_USER_VAR])
        local title_boost = title_has_sidekick(tab, win) and 1 or 0

        if user_var_root and user_var_root == normalized_root then
          table.insert(candidates, {
            window_id = win.id,
            tab_id = tab.id,
            title_boost = title_boost,
            tab_active = tab.is_active and 1 or 0,
            created_at = tonumber(win.created_at) or 0,
            rank = 2,
          })
        else
          local process_root_match = false
          local process_matches_provider = false

          for _, proc in ipairs(win.foreground_processes or {}) do
            local process_root = normalize_path(proc.cwd)
            if process_root and process_root == normalized_root then
              process_root_match = true
              if cmdline_matches_provider(proc.cmdline, provider_cmd) then
                process_matches_provider = true
                break
              end
            end
          end

          local window_root_match = normalize_path(win.cwd) == normalized_root
          if (process_root_match or window_root_match) and process_matches_provider then
            table.insert(candidates, {
              window_id = win.id,
              tab_id = tab.id,
              title_boost = title_boost,
              tab_active = tab.is_active and 1 or 0,
              created_at = tonumber(win.created_at) or 0,
              rank = 1,
            })
          end
        end
      end
    end
  end

  return candidates
end

local function choose_candidate(candidates)
  local best = nil
  for _, candidate in ipairs(candidates or {}) do
    if not best
      or candidate.rank > best.rank
      or (candidate.rank == best.rank and candidate.title_boost > best.title_boost)
      or (candidate.rank == best.rank and candidate.title_boost == best.title_boost and candidate.tab_active > best.tab_active)
      or (
        candidate.rank == best.rank
        and candidate.title_boost == best.title_boost
        and candidate.tab_active == best.tab_active
        and candidate.created_at > best.created_at
      )
    then
      best = candidate
    end
  end

  return best
end

local function recover_existing(cfg, opts)
  local data = list_data(cfg)
  if not data then
    return false
  end

  local candidate = choose_candidate(build_candidates(data, opts.root, opts.provider_cmd))
  if not candidate then
    return false
  end

  state.window_id = candidate.window_id
  state.tab_id = candidate.tab_id
  local focus_argv = command(cfg, "focus_tab", "id:" .. tostring(state.tab_id))
  if focus_argv then
    vim.fn.system(focus_argv)
  end
  return true
end

local function extract_window_id(output)
  if type(output) ~= "string" then
    return nil
  end

  local window_id = output:match("(%d+)")
  if not window_id then
    return nil
  end

  return tonumber(window_id)
end

function M.available(cfg)
  local argv = command(cfg, "check") or command(cfg, "list")
  if not argv then
    return false
  end

  vim.fn.system(argv)
  return vim.v.shell_error == 0
end

function M.ensure_open(cfg, opts)
  if not opts.force_new and refresh_state(cfg) then
    local focus_argv = command(cfg, "focus_tab", "id:" .. tostring(state.tab_id))
    if focus_argv then
      vim.fn.system(focus_argv)
    end
    return true
  end

  if not opts.force_new and recover_existing(cfg, opts) then
    return true
  end

  local launch_argv = command(cfg, "launch")
  if not launch_argv then
    return false, "ai-sidekick: external launch command is not configured"
  end

  if opts.root and opts.root ~= "" then
    vim.list_extend(launch_argv, { "--cwd", opts.root })
    vim.list_extend(launch_argv, { "--var", ROOT_USER_VAR .. "=" .. opts.root })
  end

  if cfg.title and cfg.title ~= "" then
    vim.list_extend(launch_argv, { "--title", cfg.title })
  end

  local shell = cfg.shell or { "sh", "-lc" }
  vim.list_extend(launch_argv, clone_argv(shell))
  table.insert(launch_argv, opts.shell_command)

  local output = vim.fn.system(launch_argv)
  if vim.v.shell_error ~= 0 then
    return false, "ai-sidekick: failed to open external terminal"
  end

  local window_id = extract_window_id(output)
  if not window_id then
    return false, "ai-sidekick: external launcher did not return a window id"
  end

  state.window_id = window_id
  refresh_state(cfg)
  return true
end

function M.send(cfg, text, send_enter)
  if not refresh_state(cfg) then
    return false, "ai-sidekick: external terminal tab was closed"
  end

  local send_argv = command(cfg, "send_text", "id:" .. tostring(state.window_id))
  if not send_argv then
    return false, "ai-sidekick: external send_text command is not configured"
  end

  local payload = text
  if send_enter then
    payload = payload .. "\n"
  end

  local result = vim.fn.system(send_argv, payload)
  if vim.v.shell_error ~= 0 then
    return false, "ai-sidekick: failed to send text to external terminal: " .. vim.trim(result)
  end

  return true
end

return M
