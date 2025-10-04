-- lua/notes/init.lua
local M = {}

local config = {
	dir = vim.fn.expand("~") .. "/notes",
	sync_interval = 300, -- seconds (5 minutes)
	pull_interval = 600, -- seconds (10 minutes)
	remote = nil, -- e.g., 'git@github.com:user/notes.git' for SSH
	note_ext = ".md",
}

local timer = nil
local last_pull_time = 0
local last_pull_file = nil
local state_dir = nil

-- Get state dir
local function get_state_dir()
	if not state_dir then
		state_dir = vim.fn.stdpath("data") .. "/notes_state"
	end
	if vim.fn.isdirectory(state_dir) == 0 then
		vim.fn.mkdir(state_dir, "p")
	end
	return state_dir
end

-- Get last pull file path
local function get_last_pull_file()
	if not last_pull_file then
		last_pull_file = get_state_dir() .. "/last_pull"
	end
	return last_pull_file
end

-- Get setup done file path
local function get_setup_done_file()
	return get_state_dir() .. "/setup_done"
end

-- Read last pull time from file
local function read_last_pull_time()
	local file = get_last_pull_file()
	local f = io.open(file, "r")
	if f then
		local content = f:read("*a")
		f:close()
		last_pull_time = tonumber(content) or 0
	end
end

-- Write last pull time to file
local function write_last_pull_time()
	local file = get_last_pull_file()
	local f = io.open(file, "w")
	if f then
		f:write(tostring(os.time()))
		f:close()
	end
end

-- Check if setup has been done before
local function is_setup_done()
	local file = get_setup_done_file()
	return vim.fn.filereadable(file) == 1
end

-- Mark setup as done
local function mark_setup_done()
	local file = get_setup_done_file()
	local f = io.open(file, "w")
	if f then
		f:close()
	end
end

-- Check if we should pull (first time or interval elapsed)
function M.should_pull()
	local now = os.time()
	if last_pull_time == 0 or now - last_pull_time >= config.pull_interval then
		return true
	end
	return false
end

-- Initialize the notes directory and git repo if needed
local function init_repo()
	local dir_esc = vim.fn.fnameescape(config.dir)

	-- If remote is set and directory doesn't exist, try to clone it
	if config.remote and vim.fn.isdirectory(config.dir) == 0 then
		local clone_result = vim.fn.system("git clone " .. vim.fn.shellescape(config.remote) .. " " .. dir_esc)
		if vim.v.shell_error ~= 0 then
			vim.notify(
				"Failed to clone from "
					.. config.remote
					.. " (likely empty repo). Initializing local repo instead.\nError: "
					.. clone_result,
				vim.log.levels.WARN
			)
			vim.fn.mkdir(config.dir, "p")
			local init_result = vim.fn.system("cd " .. dir_esc .. " && git init -b main")
			if vim.v.shell_error ~= 0 then
				vim.notify(
					"Failed to initialize git repo in " .. config.dir .. "\nError: " .. init_result,
					vim.log.levels.ERROR
				)
				return false
			end
			-- Add remote after init
			local remote_result =
				vim.fn.system("cd " .. dir_esc .. " && git remote add origin " .. vim.fn.shellescape(config.remote))
			if vim.v.shell_error ~= 0 then
				vim.notify(
					"Failed to add remote: " .. config.remote .. "\nError: " .. remote_result,
					vim.log.levels.WARN
				)
			end
			vim.notify("Initialized local repo in " .. config.dir .. " with remote " .. config.remote)
		else
			vim.notify("Cloned repo from " .. config.remote .. " to " .. config.dir)
		end
		return true
	end

	-- Otherwise, ensure directory exists
	if vim.fn.isdirectory(config.dir) == 0 then
		vim.fn.mkdir(config.dir, "p")
	end

	-- Check if it's already a git repo
	local init_output = vim.fn.system("cd " .. dir_esc .. " && git rev-parse --git-dir 2>/dev/null")
	if vim.v.shell_error ~= 0 then
		local init_result = vim.fn.system("cd " .. dir_esc .. " && git init -b main")
		if vim.v.shell_error ~= 0 then
			vim.notify(
				"Failed to initialize git repo in " .. config.dir .. "\nError: " .. init_result,
				vim.log.levels.ERROR
			)
			return false
		end
		vim.notify("Initialized git repo in " .. config.dir)
	end

	-- If remote is set, ensure origin points to it
	if config.remote then
		local current_remote = vim.fn.system("cd " .. dir_esc .. " && git remote get-url origin 2>/dev/null")
		if vim.v.shell_error ~= 0 or current_remote:match(config.remote) == nil then
			local remote_result = vim.fn.system(
				"cd "
					.. dir_esc
					.. " && git remote add origin "
					.. vim.fn.shellescape(config.remote)
					.. " 2>/dev/null || git remote set-url origin "
					.. vim.fn.shellescape(config.remote)
			)
			if vim.v.shell_error ~= 0 then
				vim.notify(
					"Failed to set remote: " .. config.remote .. "\nError: " .. remote_result,
					vim.log.levels.WARN
				)
			else
				vim.notify("Set remote to " .. config.remote)
			end
		end
	end

	-- Read last pull time after init
	read_last_pull_time()

	return true
end

-- Pull from remote (updates last_pull_time)
function M.pull()
	local dir_esc = vim.fn.fnameescape(config.dir)
	if config.remote then
		local pull_result = vim.fn.system("cd " .. dir_esc .. " && git pull origin main")
		if vim.v.shell_error ~= 0 then
			vim.notify("Git pull failed\nError: " .. pull_result, vim.log.levels.WARN)
		else
			vim.notify("Pulled from remote")
			last_pull_time = os.time()
			write_last_pull_time()
		end
	else
		vim.notify("No remote configured for pull", vim.log.levels.WARN)
	end
end

-- Commit and push only (no pull)
function M.commit_push()
	local dir_esc = vim.fn.fnameescape(config.dir)
	local add_result = vim.fn.system("cd " .. dir_esc .. " && git add .")
	if vim.v.shell_error ~= 0 then
		vim.notify("Git add failed\nError: " .. add_result, vim.log.levels.WARN)
		return
	end

	local commit_msg = "Auto-sync: " .. os.date("%Y-%m-%d %H:%M:%S")
	local commit_result = vim.fn.system("cd " .. dir_esc .. " && git commit -m " .. vim.fn.shellescape(commit_msg))
	if vim.v.shell_error ~= 0 then
		-- No changes to commit, that's fine
		return
	end

	vim.notify("Committed changes: " .. commit_msg)

	if config.remote then
		local push_cmd = "cd " .. dir_esc .. " && git push -u origin main"
		local push_result = vim.fn.system(push_cmd)
		if vim.v.shell_error ~= 0 then
			vim.notify(
				"Git push failed. Check SSH setup if using SSH remote.\nError: " .. push_result,
				vim.log.levels.WARN
			)
		else
			vim.notify("Pushed to remote")
		end
	end
end

-- Full sync: pull if needed, then commit_push
function M.sync()
	if M.should_pull() then
		M.pull()
	end
	M.commit_push()
end

-- Follow link under cursor: parse [link] and open/create the file
function M.follow_link()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2] + 1 -- 1-based
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local links = {}
	for link in line:gmatch("%[(.-)%]") do
		local start_col = line:find("%[", line:find(link, 1, true) - 1) or 0
		local end_col = start_col + #link + 1
		if col >= start_col and col <= end_col then
			table.insert(links, link)
		end
	end
	if #links == 0 then
		vim.notify("No [link] under cursor", vim.log.levels.WARN)
		return
	end
	local link = links[1] -- Take first match
	local parts = vim.split(link, "/")
	local current_dir = config.dir
	for i = 1, #parts - 1 do
		local subdir = parts[i]
		local subpath = current_dir .. "/" .. subdir
		if vim.fn.isdirectory(subpath) == 0 then
			vim.fn.mkdir(subpath, "p")
		end
		current_dir = subpath
	end
	local filename = parts[#parts]
	local filepath = current_dir .. "/" .. filename .. config.note_ext
	if vim.fn.filereadable(filepath) == 0 then
		local file = io.open(filepath, "w")
		if file then
			file:write("# " .. filename .. "\n\n")
			file:close()
			vim.notify("Created and opened linked note: " .. link)
			M.commit_push()
		else
			vim.notify("Failed to create linked note: " .. link, vim.log.levels.ERROR)
			return
		end
	end
	vim.cmd("edit " .. vim.fn.fnameescape(filepath))
end

-- Resolve [links] in current buffer: create files/dirs if needed
function M.resolve_links()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local new_files = {}
	for _, line in ipairs(lines) do
		for link in line:gmatch("%[(.-)%]") do
			local parts = vim.split(link, "/")
			local current_dir = config.dir
			for i = 1, #parts - 1 do
				local subdir = parts[i]
				local subpath = current_dir .. "/" .. subdir
				if vim.fn.isdirectory(subpath) == 0 then
					vim.fn.mkdir(subpath, "p")
				end
				current_dir = subpath
			end
			local filename = parts[#parts]
			local filepath = current_dir .. "/" .. filename .. config.note_ext
			if vim.fn.filereadable(filepath) == 0 then
				local file = io.open(filepath, "w")
				if file then
					file:write("# " .. filename .. "\n\n")
					file:close()
					vim.notify("Created linked note: " .. link)
					table.insert(new_files, filepath)
				else
					vim.notify("Failed to create linked note: " .. link, vim.log.levels.ERROR)
				end
			end
		end
	end
	if #new_files > 0 then
		M.commit_push()
		if #new_files == 1 then
			vim.cmd("edit " .. vim.fn.fnameescape(new_files[1]))
		else
			vim.notify(#new_files .. " new notes created. Use :NotesList to open.")
		end
	else
		vim.notify("No new links to resolve.")
	end
end

-- Delete current open note
function M.delete_note()
	local filepath = vim.api.nvim_buf_get_name(0)
	if filepath == "" then
		vim.notify("No file open in current buffer", vim.log.levels.WARN)
		return
	end

	if not filepath:match(config.dir) or not filepath:match(config.note_ext .. "$") then
		vim.notify("Current buffer is not a notes file", vim.log.levels.WARN)
		return
	end

	local title = vim.fn.fnamemodify(filepath, ":t:r")
	local confirm = vim.fn.confirm('Delete note "' .. title .. '"?', "&Yes\n&No", 2)
	if confirm == 1 then
		vim.cmd("bdelete!") -- Close the buffer without saving
		os.remove(filepath)
		vim.notify("Deleted note: " .. title)
		M.commit_push() -- Sync the deletion
	end
end

-- Create a new note
function M.new_note(title)
	if not title or title == "" then
		title = os.date("%Y-%m-%d")
	end
	local parts = vim.split(title, "/")
	local current_dir = config.dir
	for i = 1, #parts - 1 do
		local subdir = parts[i]
		local subpath = current_dir .. "/" .. subdir
		if vim.fn.isdirectory(subpath) == 0 then
			vim.fn.mkdir(subpath, "p")
		end
		current_dir = subpath
	end
	local filename = parts[#parts]
	local filepath = current_dir .. "/" .. filename .. config.note_ext
	local file = io.open(filepath, "w")
	if file then
		file:write("# " .. filename .. "\n\n")
		file:close()
		vim.cmd("edit " .. vim.fn.fnameescape(filepath))
		vim.notify("Created new note: " .. title)
	else
		vim.notify("Failed to create note: " .. title, vim.log.levels.ERROR)
	end
end

-- List notes
function M.list_notes()
	local notes = {}
	local glob_pattern = config.dir .. "/**/*" .. config.note_ext
	local files = vim.fn.glob(glob_pattern, false, true)
	for _, fullpath in ipairs(files) do
		local rel = fullpath:gsub("^" .. config.dir .. "/", "")
		local title = rel:sub(1, -4) -- remove .md
		table.insert(notes, title)
	end
	table.sort(notes)
	if #notes == 0 then
		vim.notify("No notes found")
		return
	end

	vim.ui.select(notes, {
		prompt = "Select note:",
		format_item = function(item)
			return item
		end,
	}, function(choice)
		if choice then
			local filepath = config.dir .. "/" .. choice .. config.note_ext
			vim.cmd("edit " .. vim.fn.fnameescape(filepath))
		end
	end)
end

-- Setup the plugin
function M.setup(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})
	init_repo()

	-- Autocommand for full sync on first read of notes file
	vim.api.nvim_create_autocmd("BufReadPost", {
		pattern = config.dir .. "/**/*" .. config.note_ext,
		callback = function()
			M.sync()
		end,
		once = false, -- Allow multiple, but since per buffer, fine
	})

	-- Autocommand for commit_push only on save in notes dir
	vim.api.nvim_create_autocmd("BufWritePost", {
		pattern = config.dir .. "/**/*" .. config.note_ext,
		callback = function()
			vim.defer_fn(M.commit_push, 1000) -- Delay 1s to batch saves
		end,
	})

	-- Start background timer for commit_push only if interval set (initial delay = interval to avoid startup run)
	if config.sync_interval > 0 then
		if timer then
			timer:stop()
			timer:close()
		end
		timer = vim.loop.new_timer()
		timer:start(
			config.sync_interval * 1000,
			config.sync_interval * 1000,
			vim.schedule_wrap(function()
				M.commit_push()
			end)
		)
	end

	-- Commands
	vim.api.nvim_create_user_command("NotesNew", function(opts)
		M.new_note(opts.args)
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("NotesList", function()
		M.list_notes()
	end, {})

	vim.api.nvim_create_user_command("NotesDelete", M.delete_note, {})

	vim.api.nvim_create_user_command("NotesFollowLink", M.follow_link, { desc = "Follow [link] under cursor" })

	vim.api.nvim_create_user_command(
		"NotesResolveLinks",
		M.resolve_links,
		{ desc = "Resolve [links] in current buffer" }
	)

	vim.api.nvim_create_user_command("NotesSync", M.sync, {})

	vim.api.nvim_create_user_command("NotesPull", M.pull, {})

	vim.api.nvim_create_user_command("NotesInit", init_repo, {})

	-- Notify only on first setup
	if not is_setup_done() then
		vim.notify("Notes plugin setup complete. Notes dir: " .. config.dir)
		mark_setup_done()
	end
end

return M
