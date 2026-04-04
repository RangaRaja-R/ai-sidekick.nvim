local M = {}

local builtin = {
  kitty = require("ai-sidekick.providers.terminal.kitty"),
}

local REQUIRED_KEYS = {
  "check",
  "list",
  "launch",
  "send_text",
}

local function has_command(config, key)
  local value = config[key]
  return type(value) == "function" or (type(value) == "table" and not vim.tbl_isempty(value))
end

local function validate_config(provider_name, config)
  local missing = {}

  for _, key in ipairs(REQUIRED_KEYS) do
    if not has_command(config, key) then
      table.insert(missing, key)
    end
  end

  if #missing > 0 then
    error(
      string.format(
        "ai-sidekick: external provider '%s' missing required keys: %s",
        provider_name,
        table.concat(missing, ", ")
      )
    )
  end
end

function M.resolve(config, name)
  local spec = name or config.external.provider

  if type(spec) == "table" then
    local provider = builtin.kitty
    local merged = vim.deepcopy(spec)
    validate_config("custom", merged)
    return "custom", provider, merged
  end

  local provider_name = spec
  local provider = builtin[provider_name]

  if not provider then
    error(string.format("ai-sidekick: unknown external provider '%s'", tostring(provider_name)))
  end

  local merged = vim.tbl_deep_extend(
    "force",
    provider.defaults or {},
    ((config.external.providers or {})[provider_name]) or {}
  )

  validate_config(provider_name, merged)

  return provider_name, provider, merged
end

return M
