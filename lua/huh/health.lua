local M = {}

M.check = function()
	vim.health.start("huh.nvim")

	-- Neovim version
	if vim.fn.has("nvim-0.10") == 1 then
		vim.health.ok("Neovim >= 0.10")
	else
		vim.health.error("Neovim >= 0.10 is required")
	end

	-- telescope.nvim
	local has_telescope, _ = pcall(require, "telescope")
	if has_telescope then
		vim.health.ok("telescope.nvim found")
	else
		vim.health.error("telescope.nvim is required", { "Install: https://github.com/nvim-telescope/telescope.nvim" })
	end

	-- lazy.nvim
	local has_lazy, _ = pcall(require, "lazy")
	if has_lazy then
		vim.health.ok("lazy.nvim found")
	else
		vim.health.warn("lazy.nvim not found — plugin discovery will be unavailable", {
			"Install: https://github.com/folke/lazy.nvim",
		})
	end
end

return M
