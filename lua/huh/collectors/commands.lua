local M = {}

--- Collect all user-defined and plugin commands
--- @param plugin_dirs table plugin name -> install dir
--- @return table[] command entries
M.collect = function(plugin_dirs)
	local seen = {}
	local entries = {}

	-- Build a lookup of command name prefixes from plugin names
	-- e.g., "diffview.nvim" -> "Diffview", "telescope.nvim" -> "Telescope"
	local prefix_to_plugin = {}
	for pname, _ in pairs(plugin_dirs or {}) do
		-- Strip .nvim/.lua suffix and capitalize
		local base = pname:gsub("%.nvim$", ""):gsub("%.lua$", "")
		-- Try common capitalizations
		local capitalized = base:sub(1, 1):upper() .. base:sub(2)
		prefix_to_plugin[capitalized] = pname
		prefix_to_plugin[base] = pname
		prefix_to_plugin[base:lower()] = pname
	end

	--- Try to match a command name to a plugin
	local function find_plugin(cmd_name)
		-- Try progressively shorter prefixes of the command name
		for len = #cmd_name, 3, -1 do
			local prefix = cmd_name:sub(1, len)
			if prefix_to_plugin[prefix] then
				return prefix_to_plugin[prefix]
			end
		end
		return nil
	end

	--- Try to attribute a command to a plugin via script_id or name prefix
	local function attribute_plugin(cmd_name, cmd)
		-- 1. Match via script_id (only available for global commands)
		if cmd.script_id and cmd.script_id > 0 then
			local ok2, script_info = pcall(vim.fn.getscriptinfo, { sid = cmd.script_id })
			if ok2 and script_info and #script_info > 0 then
				local script_path = script_info[1].name
				for pname, pdir in pairs(plugin_dirs or {}) do
					if script_path:find(pdir, 1, true) == 1 then
						return pname, pdir
					end
				end
			end
		end
		-- 2. Match via command name prefix
		local p = find_plugin(cmd_name)
		if p then
			return p, (plugin_dirs or {})[p]
		end
		return nil, nil
	end

	local function add_command(name, cmd)
		if seen[name] then
			return
		end
		seen[name] = true
		local plugin, plugin_dir = attribute_plugin(name, cmd)
		table.insert(entries, {
			type = "command",
			key = ":" .. name,
			mode = nil,
			desc = cmd.definition or "",
			plugin = plugin,
			plugin_dir = plugin_dir,
			command_name = name,
			nargs = cmd.nargs,
		})
	end

	-- Collect user/plugin commands (excludes builtins)
	local ok, cmds = pcall(vim.api.nvim_get_commands, {})
	if ok then
		for name, cmd in pairs(cmds) do
			add_command(name, cmd)
		end
	end

	-- Collect buffer-local commands
	local ok3, buf_cmds = pcall(vim.api.nvim_buf_get_commands, 0, {})
	if ok3 then
		for name, cmd in pairs(buf_cmds) do
			add_command(name, cmd)
		end
	end

	-- Build display and ordinal
	for _, entry in ipairs(entries) do
		entry.display = "[cmd] :" .. entry.command_name .. "  " .. entry.desc
		entry.ordinal = entry.display .. (entry.plugin and ("  " .. entry.plugin) or "")
	end

	return entries
end

return M
