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
  local max_title = math.max(width - #prefix - 2, 8)
  local title = c.title
  if vim.fn.strdisplaywidth(title) > max_title then
    -- マルチバイト対応のトリム
    -- and/or チェーンは多値関数の第 1 戻り値しか伝播しないため、
    -- chars テーブルを先に構築してから ipairs で回す
    local trimmed = ""
    local w = 0
    local chars = {}
    if utf8 and utf8.codes then
      for _, ch in utf8.codes(title) do
        table.insert(chars, utf8.char(ch))
      end
    end
    for _, byte_str in ipairs(chars) do
      local cw = vim.fn.strdisplaywidth(byte_str)
      if w + cw > max_title - 1 then
        break
      end
      trimmed = trimmed .. byte_str
      w = w + cw
    end
    -- フォールバック: utf8 が使えない場合は単純にバイトで切る
    if trimmed == "" then
      title = string.sub(title, 1, max_title - 1) .. "…"
    else
      title = trimmed .. "…"
    end
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
