local providers = require("ai-sidekick.providers")
local terminal_providers = require("ai-sidekick.providers.terminal")

local M = {}

local state = {
	terminal = {
		buf = nil,
		win = nil,
		job_id = nil,
	},
}

local INTERNAL_SEND_DELAY_MS = 1000

local function buf_is_valid(buf)
	return buf and vim.api.nvim_buf_is_valid(buf)
end

local function win_is_valid(win)
	return win and vim.api.nvim_win_is_valid(win)
end

local function normalize_slashes(path)
	return path:gsub("\\", "/")
end

local function job_is_running(job_id)
	if not job_id or job_id <= 0 then
		return false
	end

	return vim.fn.jobwait({ job_id }, 0)[1] == -1
end

local function shell_join(argv)
	local parts = {}

	for _, arg in ipairs(argv) do
		table.insert(parts, vim.fn.shellescape(arg))
	end

	return table.concat(parts, " ")
end

local function workspace_root(file_path)
	local start = file_path ~= "" and vim.fs.dirname(file_path) or vim.loop.cwd()
	local git_dir = vim.fs.find(".git", {
		upward = true,
		path = start,
		stop = vim.loop.os_homedir(),
		limit = 1,
	})[1]

	if git_dir then
		return vim.fs.dirname(git_dir)
	end

	return vim.loop.cwd()
end

local function relative_to_root(root, file_path)
	local rel = vim.fn.fnamemodify(file_path, ":.")

	if root and root ~= "" then
		local normalized_root = normalize_slashes(root):gsub("/+$", "")
		local normalized_path = normalize_slashes(file_path)
		local prefix = normalized_root .. "/"

		if normalized_path == normalized_root then
			rel = "."
		elseif normalized_path:sub(1, #prefix) == prefix then
			rel = normalized_path:sub(#prefix + 1)
		end
	end

	return normalize_slashes(rel)
end

local function current_file_reference()
	local buf = vim.api.nvim_get_current_buf()
	local file_path = vim.api.nvim_buf_get_name(buf)

	if file_path == "" then
		return nil
	end

	local root = workspace_root(file_path)
	return relative_to_root(root, file_path), root
end

local function visual_range()
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	local start_line = start_pos[2]
	local end_line = end_pos[2]

	if start_line == 0 or end_line == 0 then
		return nil
	end

	if start_line > end_line then
		start_line, end_line = end_line, start_line
	end

	return start_line, end_line
end

local function split_command(config)
	local position = config.window.position

	if position == "top" then
		return "topleft split"
	end

	if position == "left" then
		return "topleft vsplit"
	end

	if position == "right" then
		return "botright vsplit"
	end

	return "botright split"
end

local function split_size(config)
	local position = config.window.position
	local size = config.window.size

	if size > 0 and size < 1 then
		if position == "left" or position == "right" then
			return math.max(1, math.floor(vim.o.columns * size))
		end

		return math.max(1, math.floor(vim.o.lines * size))
	end

	return math.max(1, math.floor(size))
end

local function apply_split_size(win, config)
	local position = config.window.position
	local size = split_size(config)

	if position == "left" or position == "right" then
		vim.api.nvim_win_set_width(win, size)
		return
	end

	vim.api.nvim_win_set_height(win, size)
end

local function float_config(config)
	local float = config.window.float or {}
	local width = float.width or 0.8
	local height = float.height or 0.8

	if width > 0 and width <= 1 then
		width = math.floor(vim.o.columns * width)
	end

	if height > 0 and height <= 1 then
		height = math.floor(vim.o.lines * height)
	end

	width = math.min(vim.o.columns, math.max(1, math.floor(width)))
	height = math.min(vim.o.lines - 2, math.max(1, math.floor(height)))

	return {
		relative = "editor",
		style = "minimal",
		border = float.border or "rounded",
		width = width,
		height = height,
		row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
		col = math.max(0, math.floor((vim.o.columns - width) / 2)),
	}
end

local function ensure_internal_window(config)
	if win_is_valid(state.terminal.win) then
		vim.api.nvim_set_current_win(state.terminal.win)
		return state.terminal.win
	end

	if config.window.type == "float" then
		state.terminal.win = vim.api.nvim_open_win(
			buf_is_valid(state.terminal.buf) and state.terminal.buf or vim.api.nvim_create_buf(false, true),
			true,
			float_config(config)
		)
		return state.terminal.win
	end

	vim.cmd(split_command(config))
	state.terminal.win = vim.api.nvim_get_current_win()
	apply_split_size(state.terminal.win, config)
	return state.terminal.win
end

local function reset_internal_buffer()
	if win_is_valid(state.terminal.win) and buf_is_valid(state.terminal.buf) then
		pcall(vim.api.nvim_win_set_buf, state.terminal.win, vim.api.nvim_create_buf(false, true))
	end

	if buf_is_valid(state.terminal.buf) then
		pcall(vim.api.nvim_buf_delete, state.terminal.buf, { force = true })
	end

	state.terminal.buf = nil
	state.terminal.job_id = nil
end

local function open_internal_terminal(config, root, argv, prefill)
	local win = ensure_internal_window(config)

	-- Quick tasks should start a fresh CLI session instead of reusing a shell.
	reset_internal_buffer()
	state.terminal.buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(win, state.terminal.buf)
	vim.bo[state.terminal.buf].bufhidden = "hide"
	vim.bo[state.terminal.buf].filetype = "ai-sidekick"

	state.terminal.job_id = vim.fn.termopen(argv, {
		cwd = root,
		on_exit = function()
			state.terminal.job_id = nil
		end,
	})

	vim.keymap.set("t", "<Esc><Esc>", [[<C-\><C-n>:hide<CR>]], {
		buffer = state.terminal.buf,
		silent = true,
		desc = "Hide AI terminal",
	})

	vim.keymap.set("n", "q", "<cmd>hide<CR>", {
		buffer = state.terminal.buf,
		silent = true,
		desc = "Hide AI terminal",
	})

	vim.api.nvim_set_current_win(win)
	vim.cmd("startinsert")

	if prefill and prefill ~= "" then
		-- Seed the prompt text without submitting it. The user decides when to press Enter.
		vim.defer_fn(function()
			if job_is_running(state.terminal.job_id) then
				vim.fn.chansend(state.terminal.job_id, prefill)
			end
		end, INTERNAL_SEND_DELAY_MS)
	end
end

local function build_base_argv(config, opts)
	local _, provider = providers.resolve(config, opts.provider)
	local argv

	if opts.action == "temporary" then
		if not provider.temporary_args or vim.tbl_isempty(provider.temporary_args) then
			error("ai-sidekick: provider does not define temporary_args")
		end

		argv = { provider.cmd }
		vim.list_extend(argv, provider.temporary_args)
		return argv
	end

	if opts.action == "list" then
		if not provider.list_args or vim.tbl_isempty(provider.list_args) then
			error("ai-sidekick: provider does not define list_args")
		end

		argv = { provider.cmd }
		vim.list_extend(argv, provider.list_args)
		return argv
	end

	if opts.action == "resume" then
		if not provider.resume_args or vim.tbl_isempty(provider.resume_args) then
			error("ai-sidekick: provider does not define resume_args")
		end

		argv = { provider.cmd }
		vim.list_extend(argv, provider.resume_args)
		return argv
	end

	argv = { provider.cmd }
	vim.list_extend(argv, provider.args or {})

	return argv
end

local function build_external_argv(config, opts)
	local _, provider = providers.resolve(config, opts.provider)
	local argv = build_base_argv(config, opts)

	if opts.action == "resume" then
		return argv
	end

	if opts.prompt and opts.prompt ~= "" then
		if provider.prompt_arg then
			table.insert(argv, provider.prompt_arg)
		end

		table.insert(argv, opts.prompt)
	end

	return argv
end

local function can_send_external_text(config, opts)
	return opts.prompt and opts.prompt ~= "" and opts.action ~= "temporary"
end

function M.current_file_context()
	local reference, root = current_file_reference()

	if not reference then
		return nil, root
	end

	return reference, root
end

function M.visual_context()
	local reference, root = current_file_reference()

	if not reference then
		return nil, root
	end

	local start_line, end_line = visual_range()

	if not start_line then
		return reference, root
	end

	return string.format("%s:%d-%d", reference, start_line, end_line), root
end

function M.open_internal(config, opts)
	local root = opts.root or vim.loop.cwd()
	local win = ensure_internal_window(config)

	if
		not opts.new_chat
		and not opts.prompt
		and buf_is_valid(state.terminal.buf)
		and job_is_running(state.terminal.job_id)
	then
		vim.api.nvim_win_set_buf(win, state.terminal.buf)
		vim.api.nvim_set_current_win(win)
		vim.cmd("startinsert")
		return
	end

	if opts.action == "temporary" then
		open_internal_terminal(config, root, build_external_argv(config, opts), nil)
		return
	end

	open_internal_terminal(config, root, build_base_argv(config, opts), opts.prompt)
end

function M.open_external(config, opts)
	local root = opts.root or vim.loop.cwd()
	local ok_resolve, resolved_or_error, terminal_provider, terminal_config = pcall(terminal_providers.resolve, config)

	if not ok_resolve then
		vim.notify(resolved_or_error, vim.log.levels.ERROR)
		return
	end

	local force_new_external = opts.force_new_external or opts.new_chat or opts.action == "list"
	local use_external_send = can_send_external_text(config, opts)
	local argv_builder = use_external_send and build_base_argv or build_external_argv
	local ok, argv = pcall(argv_builder, config, opts)

	if not ok then
		vim.notify(argv, vim.log.levels.ERROR)
		return
	end

	if not terminal_provider.available(terminal_config) then
		vim.notify(
			"ai-sidekick: external terminal control is not available. Check external config and terminal remote control.",
			vim.log.levels.ERROR
		)
		return
	end

	local shell_command = string.format("cd %s && exec %s", vim.fn.shellescape(root), shell_join(argv))
	local ok_open, open_err = terminal_provider.ensure_open(terminal_config, {
		root = root,
		shell_command = shell_command,
		force_new = force_new_external,
	})

	if not ok_open then
		vim.notify(open_err, vim.log.levels.ERROR)
		return
	end

	if use_external_send then
		vim.defer_fn(function()
			local ok_send, send_err = terminal_provider.send(terminal_config, opts.prompt, config.external.send_enter)
			if not ok_send then
				vim.notify(send_err, vim.log.levels.WARN)
			end
		end, config.external.send_delay_ms or INTERNAL_SEND_DELAY_MS)
	end
end

function M.open(config, opts)
	opts = opts or {}

	local mode = opts.mode or config.mode

	if mode == "temporary" then
		opts.action = opts.action or "temporary"
		opts.new_chat = true
		return M.open_internal(config, opts)
	end

	if mode == "external" then
		return M.open_external(config, opts)
	end

	return M.open_internal(config, opts)
end

return M
