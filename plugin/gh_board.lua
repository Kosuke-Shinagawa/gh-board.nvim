-- Neovim 起動時に自動ロードされるエントリポイント。
-- setup() が呼ばれていない場合でも :GhBoard が動作するようにデフォルト設定で初期化する。
if vim.g.gh_board_loaded then
  return
end
vim.g.gh_board_loaded = true

-- lazy.nvim 等で setup() が明示的に呼ばれる場合はそちらに任せる。
-- このファイルは setup() を呼ばないユーザー向けのフォールバック。
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    if not vim.g.gh_board_setup_called then
      require("gh_board").setup({})
    end
  end,
})
