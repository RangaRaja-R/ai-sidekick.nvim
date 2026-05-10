local M = {
	cmd = "opencode",
	args = {},
	temporary_args = { "run" },
	resume_args = { "--continue" },
}

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO)
end

local function session_title(session)
	if type(session.title) == "string" and session.title ~= "" then
		return session.title
	end

	return session.id
end

local function load_sessions()
	if vim.fn.executable("jq") ~= 1 then
		notify("ai-sidekick: opencode session picker requires jq", vim.log.levels.ERROR)
		return nil
	end

	local raw = vim.fn.system({ M.cmd, "session", "list", "--format", "json" })
	if vim.v.shell_error ~= 0 then
		notify("ai-sidekick: failed to list opencode sessions: " .. vim.trim(raw), vim.log.levels.ERROR)
		return nil
	end

	local lines = vim.fn.systemlist({ "jq", "-c", ".[] | {id, title}" }, raw)
	if vim.v.shell_error ~= 0 then
		notify("ai-sidekick: failed to parse opencode sessions with jq", vim.log.levels.ERROR)
		return nil
	end

	local sessions = {}
	for _, line in ipairs(lines) do
		local ok, session = pcall(vim.fn.json_decode, line)
		if ok and type(session) == "table" and type(session.id) == "string" and session.id ~= "" then
			session.title = session_title(session)
			table.insert(sessions, session)
		end
	end

	return sessions
end

function M.select_chat(callback)
	local sessions = load_sessions()
	if not sessions then
		return
	end

	if vim.tbl_isempty(sessions) then
		notify("ai-sidekick: no opencode sessions found", vim.log.levels.WARN)
		return
	end

	vim.ui.select(sessions, {
		prompt = "opencode session",
		format_item = function(session)
			return session.title
		end,
	}, function(choice)
		if not choice then
			return
		end

		callback({
			args = { "-s", choice.id },
			title = choice.title,
		})
	end)
end

return M
