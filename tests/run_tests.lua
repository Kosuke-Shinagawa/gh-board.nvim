-- nvim --headless -l tests/run_tests.lua で実行する
local lazy_root = vim.fn.stdpath("data") .. "/lazy"
vim.opt.rtp:prepend(lazy_root .. "/plenary.nvim")
vim.opt.rtp:prepend(lazy_root .. "/nui.nvim")
vim.opt.rtp:append(vim.fn.getcwd())
vim.cmd("runtime plugin/plenary.vim")

require("plenary.test_harness").test_directory("tests/spec/", {
  minimal_init = "tests/minimal_init.lua",
  sequential = true,
})
