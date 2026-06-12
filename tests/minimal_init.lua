-- Minimal Neovim init for running tests with plenary busted
local lazy_root = vim.fn.stdpath("data") .. "/lazy"

vim.opt.rtp:prepend(lazy_root .. "/plenary.nvim")
vim.opt.rtp:prepend(lazy_root .. "/nui.nvim")
vim.opt.rtp:append(vim.fn.getcwd())

vim.cmd("runtime plugin/plenary.vim")
