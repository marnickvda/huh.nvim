local M = {}

--- Collect all plugins from lazy.nvim and return unified entries + declared keys
--- @return table[] plugin_entries, table[] declared_keymaps
M.collect = function()
	local ok, lazy = pcall(require, "lazy")
	if not ok then
		return {}, {}
	end
	local plugins = lazy.plugins()
	local plugin_entries = {}
	local declared_keymaps = {}

	for _, plugin in ipairs(plugins) do
		local name = plugin.name
		local desc = plugin.url or name

		-- Find the spec file by scanning config for a file matching the plugin name
		-- This is more reliable than lazy.nvim internals for directory-based imports
		local source_file = nil
		local config_lua = vim.fn.stdpath("config") .. "/lua"
		local short_name = name:gsub("%.nvim$", ""):gsub("%.lua$", ""):gsub("%.", "-"):lower()
		local candidates = vim.fn.glob(config_lua .. "/**/" .. short_name .. ".lua", false, true)
		if #candidates > 0 then
			source_file = candidates[1]
		else
			-- Try exact plugin name
			candidates = vim.fn.glob(config_lua .. "/**/" .. name:lower() .. ".lua", false, true)
			if #candidates > 0 then
				source_file = candidates[1]
			end
		end

		table.insert(plugin_entries, {
			type = "plugin",
			display = "[plugin] " .. name .. "  " .. desc,
			key = nil,
			mode = nil,
			desc = desc,
			plugin = name,
			source_file = source_file,
			plugin_dir = plugin.dir,
		})

		-- Extract declared keys from lazy spec for keymap merging
		if plugin.keys then
			for _, key_spec in ipairs(plugin.keys) do
				-- lazy.nvim key specs can be strings or tables
				local lhs, key_desc, mode
				if type(key_spec) == "string" then
					lhs = key_spec
				elseif type(key_spec) == "table" then
					lhs = key_spec[1] or key_spec.lhs
					key_desc = key_spec.desc
					mode = key_spec.mode
				end

				if lhs and key_desc then
					-- Normalize mode: can be string or table, default to "n"
					-- Expand "v" to "x" and "s" to match runtime API modes
					local modes = type(mode) == "table" and mode or { mode or "n" }
					local expanded = {}
					for _, m in ipairs(modes) do
						if m == "v" then
							table.insert(expanded, "x")
							table.insert(expanded, "s")
						else
							table.insert(expanded, m)
						end
					end

					for _, m in ipairs(expanded) do
						table.insert(declared_keymaps, {
							lhs = lhs,
							mode = m,
							desc = key_desc,
							plugin = name,
							source_file = source_file,
						})
					end
				end
			end
		end
	end

	return plugin_entries, declared_keymaps
end

return M
