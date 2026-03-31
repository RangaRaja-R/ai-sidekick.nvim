local config_module = require("ai-sidekick.config")
local core = require("ai-sidekick.core")
local providers = require("ai-sidekick.providers")

local M = {}

local state = {
  config = nil,
  commands_registered = false,
  shortcut_keymaps = {},
}

local function config()
  if not state.config then
    state.config = config_module.setup()
  end

  return state.config
end

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO)
end

local function shortcut_keys()
  return vim.tbl_keys(config().shortcuts or {})
end

local function shortcut_config(key)
  return (config().shortcuts or {})[key]
end

local function open_with_reference(opts)
  local cfg = config()
  local reference = opts.reference
  local root = opts.root or vim.loop.cwd()

  core.open(cfg, {
    mode = opts.mode,
    provider = opts.provider,
    root = root,
    prompt = reference,
  })
end

local function ask_input(prompt, callback)
  vim.ui.input({ prompt = prompt }, function(input)
    if input and input ~= "" then
      callback(input)
    end
  end)
end

local function register_commands()
  if state.commands_registered then
    return
  end

  vim.api.nvim_create_user_command("AISidekickToggleMode", function()
    M.toggle_mode()
  end, {})

  vim.api.nvim_create_user_command("AISidekickSelectProvider", function()
    M.select_provider()
  end, {})

  vim.api.nvim_create_user_command("AISidekickAsk", function()
    M.ask()
  end, {})

  vim.api.nvim_create_user_command("AISidekickResume", function()
    M.resume()
  end, {})

  vim.api.nvim_create_user_command("AI", function(command_opts)
    M.run_shortcut(command_opts.args)
  end, {
    nargs = 1,
    complete = function()
      return shortcut_keys()
    end,
  })

  state.commands_registered = true
end

local function clear_shortcut_keymaps()
  for _, lhs in ipairs(state.shortcut_keymaps) do
    pcall(vim.keymap.del, "n", lhs)
  end

  state.shortcut_keymaps = {}
end

local function register_shortcut_keymaps()
  local cfg = config()
  clear_shortcut_keymaps()

  for key, shortcut in pairs(cfg.shortcuts or {}) do
    local lhs = "<leader>a" .. key

    vim.keymap.set("n", lhs, function()
      M.run_shortcut(key)
    end, {
      silent = true,
      desc = shortcut.desc or ("Run AI shortcut " .. key),
    })

    table.insert(state.shortcut_keymaps, lhs)
  end
end

local function register_keymaps()
  local cfg = config()

  vim.keymap.set("n", cfg.keymaps.open, function()
    M.open()
  end, { silent = true, desc = "Open AI helper" })

  vim.keymap.set("x", cfg.keymaps.open, function()
    M.open_visual()
  end, { silent = true, desc = "Open AI helper with selected range reference" })

  vim.keymap.set("n", cfg.keymaps.open_internal, function()
    M.open_internal()
  end, { silent = true, desc = "Open AI helper in internal split" })

  vim.keymap.set("n", cfg.keymaps.open_with_file, function()
    M.open_with_file()
  end, { silent = true, desc = "Open AI helper with current file reference" })

  vim.keymap.set("n", cfg.keymaps.resume, function()
    M.resume()
  end, { silent = true, desc = "Resume AI helper session" })

  vim.keymap.set("n", cfg.keymaps.toggle_mode, function()
    M.toggle_mode()
  end, { silent = true, desc = "Toggle AI helper mode" })

  vim.keymap.set("n", cfg.keymaps.select_provider, function()
    M.select_provider()
  end, { silent = true, desc = "Select AI provider" })

  register_shortcut_keymaps()
end

function M.setup(user_config)
  state.config = config_module.setup(user_config)
  register_commands()
  register_keymaps()
end

function M.open(opts)
  opts = opts or {}
  core.open(config(), {
    mode = opts.mode,
    provider = opts.provider,
    root = vim.loop.cwd(),
    prompt = opts.prompt,
  })
end

function M.open_internal()
  M.open({ mode = "internal" })
end

function M.open_with_file(opts)
  opts = opts or {}
  local reference, root = core.current_file_context()

  if not reference then
    notify("ai-sidekick: current buffer has no file path", vim.log.levels.WARN)
    return
  end

  open_with_reference({
    mode = opts.mode,
    provider = opts.provider,
    reference = reference,
    root = root,
  })
end

function M.open_visual(opts)
  opts = opts or {}
  local reference, root = core.visual_context()

  if not reference then
    notify("ai-sidekick: visual context requires a file-backed buffer", vim.log.levels.WARN)
    return
  end

  open_with_reference({
    mode = opts.mode,
    provider = opts.provider,
    reference = reference,
    root = root,
  })
end

function M.ask(opts)
  opts = opts or {}

  ask_input("AI prompt: ", function(input)
    core.open(config(), {
      mode = opts.mode or "internal",
      provider = opts.provider,
      root = vim.loop.cwd(),
      prompt = input,
    })
  end)
end

function M.resume(opts)
  opts = opts or {}

  core.open(config(), {
    action = "resume",
    mode = opts.mode,
    provider = opts.provider,
    root = vim.loop.cwd(),
  })
end

function M.run_shortcut(key, opts)
  opts = opts or {}
  local shortcut = shortcut_config(key)

  if not shortcut then
    notify("ai-sidekick: unknown shortcut '" .. key .. "'", vim.log.levels.ERROR)
    return
  end

  core.open(config(), {
    mode = opts.mode or shortcut.mode or "internal",
    provider = opts.provider or shortcut.provider,
    root = vim.loop.cwd(),
    prompt = shortcut.prompt,
  })
end

function M.toggle_mode()
  local cfg = config()
  cfg.mode = cfg.mode == "internal" and "external" or "internal"
  notify("ai-sidekick mode: " .. cfg.mode)
end

function M.set_mode(mode)
  if mode ~= "internal" and mode ~= "external" then
    notify("ai-sidekick: mode must be 'internal' or 'external'", vim.log.levels.ERROR)
    return
  end

  config().mode = mode
  notify("ai-sidekick mode: " .. mode)
end

function M.select_provider()
  local cfg = config()
  local names = providers.names(cfg)

  vim.ui.select(names, {
    prompt = "AI provider",
    format_item = function(item)
      if item == (cfg.current_provider or cfg.default_provider) then
        return item .. " (current)"
      end

      return item
    end,
  }, function(choice)
    if not choice then
      return
    end

    cfg.current_provider = choice
    notify("ai-sidekick provider: " .. choice)
  end)
end

function M.set_provider(name)
  local cfg = config()
  local names = providers.names(cfg)

  if not vim.tbl_contains(names, name) then
    notify("ai-sidekick: unknown provider '" .. name .. "'", vim.log.levels.ERROR)
    return
  end

  cfg.current_provider = name
end

return M
