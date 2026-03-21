local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local previewers = require("telescope.previewers")
local entry_display = require("telescope.pickers.entry_display")
local conf = require("telescope.config").values

local plugins_collector = require("huh.collectors.plugins")
local keymaps_collector = require("huh.collectors.keymaps")
local commands_collector = require("huh.collectors.commands")

local M = {}

local MODE_HL = {
	n = "DiagnosticInfo",
	v = "DiagnosticWarn",
	i = "DiagnosticOk",
	o = "DiagnosticError",
	s = "DiagnosticHint",
}
local INACTIVE_HL = "Comment"
local NS = vim.api.nvim_create_namespace("huh_preview")

--- Sort entries: plugins first, then commands, then keymaps, alphabetical within each
local function sort_entries(entries)
	table.sort(entries, function(a, b)
		if a.type ~= b.type then
			local order = { plugin = 1, command = 2, keymap = 3 }
			return (order[a.type] or 9) < (order[b.type] or 9)
		end
		return a.display < b.display
	end)
	return entries
end

--- Find the first help doc file for a plugin
local function find_help_doc(plugin_dir)
	if not plugin_dir then
		return nil
	end
	local doc_dir = plugin_dir .. "/doc"
	local ok, files = pcall(vim.fn.glob, doc_dir .. "/*.txt", false, true)
	if ok and files and #files > 0 then
		return files[1]
	end
	return nil
end

--- Build the previewer
local function make_previewer()
	return previewers.new_buffer_previewer({
		title = "Details",
		define_preview = function(self, entry)
			local e = entry.value
			local lines = {}
			local hls = {} -- { row, col_start, col_end, hl_group }

			local function add(text, hl)
				table.insert(lines, text)
				if hl then
					table.insert(hls, { #lines - 1, 0, #text, hl })
				end
			end

			if e.type == "plugin" then
				add(e.plugin or "unknown", "Title")
				if e.desc and e.desc ~= e.plugin then
					add("")
					add(e.desc, "Comment")
				end
			elseif e.type == "command" then
				add(":" .. (e.command_name or ""), "Title")
				add("")
				add("Args: " .. (e.nargs or "0"))
				if e.plugin then
					add("Source: " .. e.plugin)
				end
				if e.desc and e.desc ~= "" then
					add("")
					add(e.desc, "Comment")
				end
			else
				add(e.key or "", "Title")
				add("")
				add(e.desc or "")
				add("")
				add("Modes: [" .. (e.mode or "") .. "]")
				local source = e.plugin
					or (e.source_file and e.source_file:find(vim.fn.stdpath("config"), 1, true) and "User config")
					or "Neovim default"
				add("Source: " .. source, "Comment")
			end

			-- Append help docs if available
			local help_file = find_help_doc(e.plugin_dir)
			if help_file then
				add("")
				add(string.rep("─", 40), "FloatBorder")
				add("")
				local ok, doc_lines = pcall(vim.fn.readfile, help_file)
				if ok and doc_lines then
					vim.list_extend(lines, doc_lines)
				end
			end

			vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)

			-- Apply highlights
			vim.api.nvim_buf_clear_namespace(self.state.bufnr, NS, 0, -1)
			for _, hl in ipairs(hls) do
				vim.api.nvim_buf_add_highlight(self.state.bufnr, NS, hl[4], hl[1], hl[2], hl[3])
			end

			-- Apply vimdoc treesitter for help docs
			if help_file then
				pcall(vim.treesitter.start, self.state.bufnr, "vimdoc")
			end
		end,
	})
end

--- Build plugin lookup tables from plugin entries
local function build_plugin_lookups(plugin_entries)
	local plugin_dirs = {} -- plugin name -> install dir
	local source_to_plugin = {} -- spec source file -> { name, dir }
	for _, e in ipairs(plugin_entries) do
		if e.plugin then
			if e.plugin_dir then
				plugin_dirs[e.plugin] = e.plugin_dir
			end
			if e.source_file then
				source_to_plugin[e.source_file] = { name = e.plugin, dir = e.plugin_dir }
			end
		end
	end
	return plugin_dirs, source_to_plugin
end

--- Enrich keymaps with plugin attribution by cross-referencing source files
local function enrich_keymaps(keymap_entries, plugin_dirs, source_to_plugin)
	for _, e in ipairs(keymap_entries) do
		if not e.plugin and e.source_file then
			local info = source_to_plugin[e.source_file]
			if info then
				e.plugin = info.name
				e.plugin_dir = info.dir
			else
				for pname, pdir in pairs(plugin_dirs) do
					if e.source_file:find(pdir, 1, true) == 1 then
						e.plugin = pname
						e.plugin_dir = pdir
						break
					end
				end
			end
		end
		if e.plugin and not e.plugin_dir then
			e.plugin_dir = plugin_dirs[e.plugin]
		end
	end
end

--- Collect and merge all entries from all collectors
local function collect_all()
	local plugin_entries, declared_keymaps = plugins_collector.collect()
	local keymap_entries = keymaps_collector.collect(declared_keymaps)
	local plugin_dirs, source_to_plugin = build_plugin_lookups(plugin_entries)
	enrich_keymaps(keymap_entries, plugin_dirs, source_to_plugin)
	local command_entries = commands_collector.collect(plugin_dirs)

	local all = {}
	vim.list_extend(all, plugin_entries)
	vim.list_extend(all, keymap_entries)
	vim.list_extend(all, command_entries)
	return all
end

--- Open the huh picker
M.open = function()
	local all_entries = collect_all()
	sort_entries(all_entries)

	pickers
		.new({}, {
			prompt_title = "huh?",
			finder = finders.new_table({
				results = all_entries,
				entry_maker = (function()
					local plugin_displayer = entry_display.create({
						separator = " ",
						items = {
							{ width = 8 }, -- [plugin]
							{ remaining = true }, -- name + desc
						},
					})

					local cmd_displayer = entry_display.create({
						separator = " ",
						items = {
							{ width = 8 }, -- [cmd]
							{ width = 20 }, -- command name
							{ remaining = true }, -- description/plugin
						},
					})

					local keymap_displayer = entry_display.create({
						separator = "",
						items = {
							{ width = 9 }, -- "[keymap] "
							{ width = 1 }, -- "["
							{ width = 1 }, -- n
							{ width = 1 }, -- v
							{ width = 1 }, -- i
							{ width = 1 }, -- o
							{ width = 1 }, -- s
							{ width = 2 }, -- "] "
							{ width = 15 }, -- key combo
							{ remaining = true }, -- description
						},
					})

					return function(entry)
						if entry.type == "plugin" then
							return {
								value = entry,
								display = function()
									return plugin_displayer({
										{ "[plugin]", "TelescopeResultsIdentifier" },
										entry.plugin .. "  " .. (entry.desc or ""),
									})
								end,
								ordinal = entry.ordinal or entry.display,
							}
						elseif entry.type == "command" then
							local desc = entry.plugin and (entry.plugin .. "  " .. entry.desc) or entry.desc or ""
							return {
								value = entry,
								display = function()
									return cmd_displayer({
										{ "[cmd]", "DiagnosticWarn" },
										{ ":" .. (entry.command_name or ""), "TelescopeResultsSpecialComment" },
										desc,
									})
								end,
								ordinal = entry.ordinal or entry.display,
							}
						else
							local mode = entry.mode or "_____"
							local function char_hl(idx)
								local ch = mode:sub(idx, idx)
								return ch == "_" and INACTIVE_HL or (MODE_HL[ch] or INACTIVE_HL)
							end

							return {
								value = entry,
								display = function()
									return keymap_displayer({
										{ "[keymap]", "TelescopeResultsComment" },
										{ "[", "Comment" },
										{ mode:sub(1, 1), char_hl(1) },
										{ mode:sub(2, 2), char_hl(2) },
										{ mode:sub(3, 3), char_hl(3) },
										{ mode:sub(4, 4), char_hl(4) },
										{ mode:sub(5, 5), char_hl(5) },
										{ "]", "Comment" },
										{ entry.key or "", "TelescopeResultsSpecialComment" },
										entry.desc or "",
									})
								end,
								ordinal = entry.ordinal or entry.display,
							}
						end
					end
				end)(),
			}),
			sorter = conf.generic_sorter({}),
			previewer = make_previewer(),
			attach_mappings = function(prompt_bufnr, _)
				actions.select_default:replace(function()
					local selection = require("telescope.actions.state").get_selected_entry()
					actions.close(prompt_bufnr)
					if selection then
						local e = selection.value
						if e.type == "keymap" then
							local keys = vim.api.nvim_replace_termcodes(e.key, true, false, true)
							vim.api.nvim_feedkeys(keys, "m", false)
						elseif e.type == "command" and e.command_name then
							if e.nargs == "0" then -- nargs is a string from nvim_get_commands
								vim.cmd[e.command_name]()
							else
								-- Open command line with the command pre-filled so user can add args
								vim.api.nvim_feedkeys(":" .. e.command_name .. " ", "n", false)
							end
						end
					end
				end)
				return true
			end,
		})
		:find()
end

return M
