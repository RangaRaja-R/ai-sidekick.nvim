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

local function clone_argv(argv)
  return vim.deepcopy(argv)
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

  local launch_argv = command(cfg, "launch")
  if not launch_argv then
    return false, "ai-sidekick: external launch command is not configured"
  end

  if opts.root and opts.root ~= "" then
    vim.list_extend(launch_argv, { "--cwd", opts.root })
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
