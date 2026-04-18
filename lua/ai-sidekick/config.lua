local M = {}

M.defaults = {
	default_provider = "codex",
	current_provider = nil,
	mode = "internal",
	keymaps = {
		open = "<leader>ai",
		open_internal = "<leader>a/",
		open_with_file = "<leader>ao",
		copy_reference = "<leader>ay",
		new_chat = "<leader>an",
		list_chats = "<leader>al",
		toggle_mode = "<leader>ax",
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
		provider = "kitty",
		send_delay_ms = 500,
		send_enter = false,
	},
	providers = {
		codex = {},
	},
	shortcuts = {},
}

function M.setup(user_config)
	local defaults = vim.deepcopy(M.defaults)
	local merged = vim.tbl_deep_extend("force", defaults, user_config or {})

	return merged
end

return M
