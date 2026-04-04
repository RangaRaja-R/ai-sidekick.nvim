local M = {}

local builtin = {
  codex = require("ai-sidekick.providers.AI.codex"),
  cursor = require("ai-sidekick.providers.AI.cursor"),
}

function M.resolve(config, name)
  local provider_name = name or config.current_provider or config.default_provider
  local merged = vim.tbl_deep_extend(
    "force",
    builtin[provider_name] or {},
    (config.providers and config.providers[provider_name]) or {}
  )

  if not merged.cmd or merged.cmd == "" then
    error(string.format("ai-sidekick: provider '%s' is missing a cmd", provider_name))
  end

  return provider_name, merged
end

function M.names(config)
  local seen = {}
  local names = {}

  for name, _ in pairs(builtin) do
    seen[name] = true
    table.insert(names, name)
  end

  for name, _ in pairs(config.providers or {}) do
    if not seen[name] then
      table.insert(names, name)
    end
  end

  table.sort(names)
  return names
end

return M
