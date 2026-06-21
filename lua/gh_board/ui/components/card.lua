local M = {}

-- カード種別のアイコン
local KIND_ICON = {
  draft = "◇",
  issue = "○",
  pr = "⌥",
}

-- Issue/PR の状態アイコン
local STATE_ICON = {
  OPEN = "●",
  CLOSED = "✕",
  MERGED = "⎇",
}

-- カード 1 件を 1 行のテキストに変換する
---@param card GhCard
---@param width integer カラム幅（タイトルをトリムする基準）
---@return string line
---@return string hl_group  行全体に適用するハイライトグループ名
function M.render_line(card, width)
  local c = card.content
  local icon = KIND_ICON[c.kind] or "·"

  local state_mark = ""
  if c.state then
    state_mark = (STATE_ICON[c.state] or "") .. " "
  end

  local number_mark = ""
  if c.number then
    number_mark = string.format("#%d ", c.number)
  end

  -- "◇ タイトル" or "○ #42 タイトル" の形式
  local prefix = string.format("%s %s%s", icon, number_mark, state_mark)
  local max_title = math.max(width - vim.fn.strdisplaywidth(prefix) - 2, 8)
  local title = c.title
  if vim.fn.strdisplaywidth(title) > max_title then
    -- 表示幅基準でトリム（バイト切断を避ける）
    local nchars = vim.fn.strchars(title)
    repeat
      nchars = nchars - 1
    until nchars <= 0
      or vim.fn.strdisplaywidth(vim.fn.strcharpart(title, 0, nchars) .. "…") <= max_title
    title = vim.fn.strcharpart(title, 0, nchars) .. "…"
  end

  local line = prefix .. title

  local hl = "GhBoardCard"
  if c.kind == "draft" then
    hl = "GhBoardCardDraft"
  elseif c.state == "CLOSED" then
    hl = "GhBoardCardClosed"
  elseif c.state == "MERGED" then
    hl = "GhBoardCardMerged"
  end

  return line, hl
end

-- カードのカーソル行から card を逆引きするためのインデックスを返す
-- column_cards: そのカラムに属するカード配列
---@param column_cards GhCard[]
---@param header_lines integer カラムヘッダーの行数（通常 2）
---@param cursor_row integer カラム内での行番号（1 始まり）
---@return GhCard|nil
function M.card_at(column_cards, header_lines, cursor_row)
  local idx = cursor_row - header_lines
  if idx < 1 or idx > #column_cards then
    return nil
  end
  return column_cards[idx]
end

return M
