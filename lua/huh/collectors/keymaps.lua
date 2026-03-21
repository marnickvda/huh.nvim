local M = {}

local MODES = { "n", "i", "x", "o", "s" }

--- Try to extract source file from a keymap's callback
local function get_source_file(keymap)
	if keymap.callback then
		local ok, info = pcall(debug.getinfo, keymap.callback, "S")
		if ok and info and info.source then
			return info.source:gsub("^@", "")
		end
	end
	return nil
end

--- Replace resolved leader key back to <leader> for display
--- Normalize lhs to a canonical form for both display and dedup
local function normalize_lhs(lhs)
	local leader = vim.g.mapleader or "\\"
	if leader == " " then
		lhs = lhs:gsub("^<Space>", "<leader>")
		lhs = lhs:gsub("^ ", "<leader>")
	end
	return lhs
end

--- Resolve <leader> back to the actual key for ordinal matching
--- e.g., "<leader>ff" with space leader -> " ff"
local function resolve_leader(key)
	if not key:find("<leader>") then
		return nil
	end
	local leader = vim.g.mapleader or "\\"
	return key:gsub("<leader>", leader)
end

--- Convert lhs to a canonical byte form for dedup comparison
--- This handles all encoding differences (literal space, <Space>, <leader>, etc.)
local function canonical_lhs(lhs)
	return vim.api.nvim_replace_termcodes(lhs, true, true, true)
end

--- Build a keymap entry from a runtime keymap table
local function make_runtime_entry(km, mode)
	local source_file = get_source_file(km)
	return {
		type = "keymap",
		key = normalize_lhs(km.lhs),
		mode = mode,
		desc = km.desc,
		source_file = source_file,
		plugin = nil,
	}
end

--- Collect all keymaps from runtime + merge with lazy-declared keys
--- @param declared_keymaps table[] keymaps extracted from lazy.nvim plugin specs
--- @return table[] unified keymap entries
M.collect = function(declared_keymaps)
	-- Key: "mode|canonical_lhs" -> entry (for deduplication)
	local seen = {}

	-- 1. Collect buffer-local keymaps (highest priority)
	for _, mode in ipairs(MODES) do
		local ok, buf_maps = pcall(vim.api.nvim_buf_get_keymap, 0, mode)
		if ok then
			for _, km in ipairs(buf_maps) do
				if km.desc and km.desc ~= "" and not km.lhs:find("<Plug>") then
					seen[mode .. "|" .. canonical_lhs(km.lhs)] = make_runtime_entry(km, mode)
				end
			end
		end
	end

	-- 2. Collect global keymaps (lower priority, skip if buffer-local exists)
	for _, mode in ipairs(MODES) do
		local ok2, maps = pcall(vim.api.nvim_get_keymap, mode)
		if not ok2 then
			maps = {}
		end
		for _, km in ipairs(maps) do
			if km.desc and km.desc ~= "" and not km.lhs:find("<Plug>") then
				local dedup_key = mode .. "|" .. canonical_lhs(km.lhs)
				if not seen[dedup_key] then
					seen[dedup_key] = make_runtime_entry(km, mode)
				end
			end
		end
	end

	-- 3. Merge lazy-declared keymaps (lowest priority, skip if runtime exists)
	for _, dk in ipairs(declared_keymaps or {}) do
		local dedup_key = dk.mode .. "|" .. canonical_lhs(dk.lhs)
		if not seen[dedup_key] then
			seen[dedup_key] = {
				type = "keymap",
				key = normalize_lhs(dk.lhs),
				mode = dk.mode,
				desc = dk.desc,
				source_file = dk.source_file,
				plugin = dk.plugin,
			}
		else
			-- Enrich existing entry with plugin info if missing
			local existing = seen[dedup_key]
			if not existing.plugin and dk.plugin then
				existing.plugin = dk.plugin
			end
		end
	end

	-- Group entries by canonical key to merge modes
	local by_key = {}
	for _, entry in pairs(seen) do
		local canon = canonical_lhs(entry.key)
		if by_key[canon] then
			-- Add mode to existing entry
			by_key[canon].modes[entry.mode] = true
			-- Prefer enriched data (plugin info)
			if not by_key[canon].plugin and entry.plugin then
				by_key[canon].plugin = entry.plugin
				by_key[canon].plugin_dir = entry.plugin_dir
			end
		else
			entry.modes = { [entry.mode] = true }
			by_key[canon] = entry
		end
	end

	-- Build display strings and collect
	local results = {}
	for _, entry in pairs(by_key) do
		-- Build fixed-width mode indicator: [nvios] with _ for inactive
		local has = entry.modes
		local n = has["n"] and "n" or "_"
		local v = (has["x"] or has["v"]) and "v" or "_"
		local i = has["i"] and "i" or "_"
		local o = has["o"] and "o" or "_"
		local s = has["s"] and "s" or "_"
		entry.mode = n .. v .. i .. o .. s
		entry.display = "[keymap] " .. entry.key .. "  " .. entry.mode .. "  " .. entry.desc
		-- Include plugin name and resolved leader key in ordinal for fuzzy search
		-- so typing " ff" matches <leader>ff when leader is space
		local resolved = resolve_leader(entry.key)
		entry.ordinal = entry.display
			.. (entry.plugin and ("  " .. entry.plugin) or "")
			.. (resolved and ("  " .. resolved) or "")
		table.insert(results, entry)
	end

	return results
end

return M
