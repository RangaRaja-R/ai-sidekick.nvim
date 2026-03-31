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
  split = {
    position = "bottom",
    size = 15,
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
  return vim.tbl_deep_extend("force", defaults, user_config or {})
end

return M
