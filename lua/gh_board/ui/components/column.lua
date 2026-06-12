local card_comp = require("gh_board.ui.components.card")

local M = {}

-- カラムのカラーラベル → ハイライトグループ名
local COLOR_HL = {
  GREEN = "GhBoardColumnGreen",
  YELLOW = "GhBoardColumnYellow",
  RED = "GhBoardColumnRed",
  BLUE = "GhBoardColumnBlue",
  ORANGE = "GhBoardColumnOrange",
  PINK = "GhBoardColumnPink",
  PURPLE = "GhBoardColumnPurple",
  GRAY = "GhBoardColumnGray",
}

-- カラムのヘッダー行数（タイトル行 + 区切り線）
M.HEADER_LINES = 2

-- カラム 1 列分のテキスト行と各行のハイライトを返す
---@param column GhColumn
---@param column_cards GhCard[]  このカラムに属するカード
---@param col_width integer      カラムの表示幅
---@return string[] lines
---@return { row: integer, hl: string }[] highlights  行番号（1 始まり）と適用 HL グループ
function M.render(column, column_cards, col_width)
  local lines = {}
  local highlights = {}

  -- ヘッダー行: " Status Name (N) "
  local count_str = string.format("(%d)", #column_cards)
  local name = column.name or ""
  local padding = col_width - vim.fn.strdisplaywidth(name) - vim.fn.strdisplaywidth(count_str) - 3
  local header = string.format(" %s%s%s ", name, string.rep(" ", math.max(padding, 1)), count_str)
  -- 長すぎる場合はトリム
  if vim.fn.strdisplaywidth(header) > col_width then
    header = string.format(" %s ", name):sub(1, col_width - 1)
  end
  table.insert(lines, header)
  table.insert(highlights, {
    row = 1,
    hl = COLOR_HL[column.color] or "GhBoardColumnHeader",
  })

  -- 区切り線
  table.insert(lines, string.rep("─", col_width))
  table.insert(highlights, { row = 2, hl = "GhBoardColumnSeparator" })

  -- カード行
  for _, card in ipairs(column_cards) do
    local line, hl = card_comp.render_line(card, col_width)
    -- 行を col_width に揃える（短い場合はパディング）
    local display_w = vim.fn.strdisplaywidth(line)
    if display_w < col_width then
      line = line .. string.rep(" ", col_width - display_w)
    end
    table.insert(lines, line)
    table.insert(highlights, { row = #lines, hl = hl })
  end

  -- カラムが空のとき空行を 1 つ入れて視認性を確保
  if #column_cards == 0 then
    table.insert(lines, string.rep(" ", col_width))
    table.insert(highlights, { row = #lines, hl = "GhBoardEmpty" })
  end

  return lines, highlights
end

-- カラムのハイライト定義を登録する（init 時に一度だけ呼ぶ）
function M.define_highlights()
  local defs = {
    GhBoardColumnHeader = { link = "CursorLine" },
    GhBoardColumnSeparator = { link = "Comment" },
    GhBoardColumnGreen = { fg = "#56d364", bold = true },
    GhBoardColumnYellow = { fg = "#e3b341", bold = true },
    GhBoardColumnRed = { fg = "#f85149", bold = true },
    GhBoardColumnBlue = { fg = "#58a6ff", bold = true },
    GhBoardColumnOrange = { fg = "#f0883e", bold = true },
    GhBoardColumnPink = { fg = "#ff7eb6", bold = true },
    GhBoardColumnPurple = { fg = "#bc8cff", bold = true },
    GhBoardColumnGray = { fg = "#8b949e", bold = true },
    GhBoardCard = { link = "Normal" },
    GhBoardCardDraft = { link = "Comment" },
    GhBoardCardClosed = { link = "Comment", strikethrough = true },
    GhBoardCardMerged = { fg = "#bc8cff" },
    GhBoardEmpty = { link = "Comment" },
    GhBoardCursor = { link = "Visual" },
  }

  for name, opts in pairs(defs) do
    if opts.link then
      vim.api.nvim_set_hl(0, name, { link = opts.link, default = true })
    else
      vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", opts, { default = true }))
    end
  end
end

return M
