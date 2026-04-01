local M = {}

M.defaults = {
  default_provider = "codex",
  current_provider = nil,
  mode = "internal",
  keymaps = {
    open = "<leader>ao",
    open_internal = "<leader>ai",
    open_with_file = "<leader>aO",
    resume = "<leader>ax",
    toggle_mode = "<leader>am",
    select_provider = "<leader>ap",
  },
  window = {
    type = "split",
    position = "bottom",
    size = 0.33,
    float = {
      width = 0.8,
      height = 0.8,
      border = "rounded",
    },
  },
  external = {
    launcher = { "kitty", "@", "launch", "--type=tab", "sh", "-lc" },
  },
  providers = {
    codex = {},
  },
  shortcuts = {
    r = {
      prompt = "Review the staged changes for bugs, mistakes, and irrelevant changes.",
      mode = "internal",
      desc = "Review staged changes",
    },
    c = {
      prompt = "Generate a concise commit message for the staged changes.",
      mode = "internal",
      desc = "Generate commit message",
    },
  },
}

function M.setup(user_config)
  local defaults = vim.deepcopy(M.defaults)
  local merged = vim.tbl_deep_extend("force", defaults, user_config or {})

  if user_config and user_config.split and not user_config.window then
    merged.window = vim.tbl_deep_extend("force", defaults.window, user_config.split)
  end

  return merged
end

return M
