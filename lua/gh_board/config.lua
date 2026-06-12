local M = {}

---@class GhBoardConfig
---@field token string|nil           GitHub personal access token（省略時は gh CLI / 環境変数で解決）
---@field default_owner string|nil   デフォルトの GitHub ユーザー / Org 名
---@field default_project integer|nil デフォルトのプロジェクト番号
---@field per_page integer           一度に取得するカード数（デフォルト: 50）
---@field win_width integer          ボードウィンドウ幅（デフォルト: 画面幅の 90%）
---@field win_height integer         ボードウィンドウ高さ（デフォルト: 画面高さの 80%）
---@field keymaps GhBoardKeymaps

---@class GhBoardKeymaps
---@field open_detail string
---@field new_card string
---@field move_card string
---@field delete_card string
---@field edit_card string
---@field refresh string
---@field close string

---@type GhBoardConfig
local defaults = {
  token = nil,
  default_owner = nil,
  default_project = nil,
  per_page = 50,
  win_width = math.floor(vim.o.columns * 0.9),
  win_height = math.floor(vim.o.lines * 0.8),
  keymaps = {
    open_detail = "<CR>",
    new_card = "n",
    move_card = "m",
    delete_card = "d",
    edit_card = "e",
    refresh = "r",
    close = "q",
  },
}

---@type GhBoardConfig
M.options = {}

---@param opts GhBoardConfig|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", defaults, opts or {})
  vim.g.gh_board_setup_called = true
end

return M
