local M = {}

M.setup = function(opts)
	M.opts = opts or {}
end

M.pick = function()
	require("huh.picker").open()
end

return M
