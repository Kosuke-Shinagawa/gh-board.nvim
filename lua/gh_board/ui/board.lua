local Popup = require("nui.popup")
local config = require("gh_board.config")
local store = require("gh_board.state.store")
local column_comp = require("gh_board.ui.components.column")
local card_comp = require("gh_board.ui.components.card")

local M = {}

-- カーソル位置: col_idx と card_idx（どちらも 1 始まり）
---@type { col: integer, card: integer }
local _cursor = { col = 1, card = 1 }

---@type any nui Popup インスタンス
local _popup = nil

---@type fun() store の購読解除関数
local _unsubscribe = nil

-- カラム幅を計算する
---@param win_width integer
---@param num_cols integer
---@return integer
local function calc_col_width(win_width, num_cols)
  if num_cols == 0 then
    return win_width
  end
  -- 縦区切り線の数: num_cols + 1
  return math.floor((win_width - num_cols - 1) / num_cols)
end

-- カーソルをカラム内の有効範囲にクランプする
---@param state BoardState
local function clamp_cursor(state)
  local num_cols = #state.columns
  _cursor.col = math.max(1, math.min(_cursor.col, num_cols))

  local col = state.columns[_cursor.col]
  local cards_in_col = vim.tbl_filter(function(c)
    return c.column_id == col.id
  end, state.cards)

  local max_card = math.max(1, #cards_in_col)
  _cursor.card = math.max(1, math.min(_cursor.card, max_card))
end

-- カーソル位置のカードを返す
---@param state BoardState
---@return GhCard|nil
local function current_card(state)
  if _cursor.col > #state.columns then
    return nil
  end
  local col = state.columns[_cursor.col]
  local cards_in_col = vim.tbl_filter(function(c)
    return c.column_id == col.id
  end, state.cards)

  return cards_in_col[_cursor.card]
end

-- ボードをバッファに描画する
local function render()
  if not _popup or not _popup.bufnr then
    return
  end

  local state = store.get_state()

  local bufnr = _popup.bufnr
  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)

  if not state then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { " Loading…" })
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    return
  end

  local win_width = vim.api.nvim_win_get_width(_popup.winid) - 2 -- border を引く
  local num_cols = #state.columns
  local col_width = calc_col_width(win_width, num_cols)

  -- 各カラムの行配列を生成
  ---@type string[][]
  local all_col_lines = {}
  ---@type { row: integer, col_idx: integer, hl: string }[]
  local all_highlights = {}

  for ci, col in ipairs(state.columns) do
    local cards_in_col = vim.tbl_filter(function(c)
      return c.column_id == col.id
    end, state.cards)

    local lines, hls = column_comp.render(col, cards_in_col, col_width)
    all_col_lines[ci] = lines

    for _, hl_info in ipairs(hls) do
      table.insert(all_highlights, {
        row = hl_info.row,
        col_idx = ci,
        hl = hl_info.hl,
      })
    end
  end

  -- 最大行数を求めてグリッドを構築
  local max_rows = 0
  for _, lines in ipairs(all_col_lines) do
    max_rows = math.max(max_rows, #lines)
  end

  local grid_lines = {}
  for row = 1, max_rows do
    local parts = { "│" }
    for ci = 1, num_cols do
      local col_lines = all_col_lines[ci] or {}
      local line = col_lines[row] or string.rep(" ", col_width)
      -- 幅を col_width に揃える
      local dw = vim.fn.strdisplaywidth(line)
      if dw < col_width then
        line = line .. string.rep(" ", col_width - dw)
      elseif dw > col_width then
        line = vim.fn.strcharpart(line, 0, col_width)
      end
      table.insert(parts, line)
      table.insert(parts, "│")
    end
    table.insert(grid_lines, table.concat(parts))
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, grid_lines)

  -- ハイライトを適用する
  vim.api.nvim_buf_clear_namespace(bufnr, -1, 0, -1)
  local ns = vim.api.nvim_create_namespace("gh_board")

  for _, hl_info in ipairs(all_highlights) do
    local buf_row = hl_info.row - 1 -- 0 始まり
    -- カラム内での文字開始オフセットを計算: "│" + (ci-1) * (col_width + 1) + 1
    local byte_start = 1 + (hl_info.col_idx - 1) * (col_width + 1)
    local byte_end = byte_start + col_width

    pcall(vim.api.nvim_buf_add_highlight, bufnr, ns, hl_info.hl, buf_row, byte_start, byte_end)
  end

  -- カーソル行のハイライト
  clamp_cursor(state)
  local cursor_buf_row = column_comp.HEADER_LINES + _cursor.card - 1 -- 0 始まり
  local cursor_byte_start = 1 + (_cursor.col - 1) * (col_width + 1)
  local cursor_byte_end = cursor_byte_start + col_width
  pcall(
    vim.api.nvim_buf_add_highlight,
    bufnr,
    ns,
    "GhBoardCursor",
    cursor_buf_row,
    cursor_byte_start,
    cursor_byte_end
  )

  -- nvim カーソルをカーソル行に移動
  local nvim_row = cursor_buf_row + 1
  local nvim_col = cursor_byte_start
  pcall(vim.api.nvim_win_set_cursor, _popup.winid, { nvim_row, nvim_col })

  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
end

-- キーマップを設定する
local function setup_keymaps()
  local km = config.options.keymaps
  local bufnr = _popup.bufnr

  local function map(key, fn)
    vim.keymap.set("n", key, fn, { buffer = bufnr, nowait = true, silent = true })
  end

  -- カーソル移動
  map("j", function()
    local state = store.get_state()
    if not state then
      return
    end
    local col = state.columns[_cursor.col]
    local cards_in_col = vim.tbl_filter(function(c)
      return c.column_id == col.id
    end, state.cards)
    _cursor.card = math.min(_cursor.card + 1, math.max(1, #cards_in_col))
    render()
  end)

  map("k", function()
    _cursor.card = math.max(_cursor.card - 1, 1)
    render()
  end)

  map("h", function()
    local state = store.get_state()
    if not state then
      return
    end
    _cursor.col = math.max(_cursor.col - 1, 1)
    clamp_cursor(state)
    render()
  end)

  map("l", function()
    local state = store.get_state()
    if not state then
      return
    end
    _cursor.col = math.min(_cursor.col + 1, #state.columns)
    clamp_cursor(state)
    render()
  end)

  -- カード操作
  map(km.open_detail, function()
    local state = store.get_state()
    if not state then
      return
    end
    local card = current_card(state)
    if card then
      require("gh_board.ui.card_detail").open(card, state)
    end
  end)

  map(km.new_card, function()
    local state = store.get_state()
    if not state then
      return
    end
    require("gh_board.ui.card_form").open_create(state, _cursor.col)
  end)

  map(km.move_card, function()
    local state = store.get_state()
    if not state then
      return
    end
    local card = current_card(state)
    if not card then
      return
    end

    local col_names = vim.tbl_map(function(c)
      return c.name
    end, state.columns)

    vim.ui.select(col_names, { prompt = "Move to column:" }, function(choice, idx)
      if not choice or not idx then
        return
      end
      local target_col = state.columns[idx]
      if target_col.id == card.column_id then
        return
      end

      store.optimistic_move(card.id, target_col.id, function(err)
        vim.notify("gh-board: " .. err.message, vim.log.levels.ERROR)
      end)
    end)
  end)

  map(km.delete_card, function()
    local state = store.get_state()
    if not state then
      return
    end
    local card = current_card(state)
    if not card then
      return
    end

    vim.ui.input({
      prompt = string.format('Delete "%s"? [y/N] ', card.content.title),
    }, function(input)
      if input ~= "y" and input ~= "Y" then
        return
      end
      local projects = require("gh_board.api.projects")
      projects.delete_card(state.project.id, card.id, function(err)
        if err then
          vim.notify("gh-board: " .. err.message, vim.log.levels.ERROR)
          return
        end
        store.apply_delete(card.id)
      end)
    end)
  end)

  map(km.refresh, function()
    local state = store.get_state()
    if not state then
      return
    end
    store.load(state.project.id, function(err)
      if err then
        vim.notify("gh-board: " .. err.message, vim.log.levels.ERROR)
      end
    end)
  end)

  map(km.close, function()
    M.close()
  end)

  map("<Esc>", function()
    M.close()
  end)
end

-- ボードを開く
---@param project_id string
function M.open(project_id)
  if _popup then
    M.close()
  end

  column_comp.define_highlights()

  local win_width = config.options.win_width
  local win_height = config.options.win_height

  _popup = Popup({
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = " gh-board ",
        top_align = "left",
      },
    },
    position = {
      row = math.floor((vim.o.lines - win_height) / 2),
      col = math.floor((vim.o.columns - win_width) / 2),
    },
    size = {
      width = win_width,
      height = win_height,
    },
    buf_options = {
      modifiable = false,
      readonly = true,
    },
    win_options = {
      wrap = false,
      cursorline = false,
      number = false,
      relativenumber = false,
    },
  })

  _popup:mount()
  setup_keymaps()

  -- ローディング表示
  vim.api.nvim_buf_set_option(_popup.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(_popup.bufnr, 0, -1, false, { " Loading…" })
  vim.api.nvim_buf_set_option(_popup.bufnr, "modifiable", false)

  -- store の変更を購読して再描画
  _unsubscribe = store.subscribe(render)

  -- データ取得
  store.load(project_id, function(err)
    if err then
      vim.notify("gh-board: " .. err.message, vim.log.levels.ERROR)
      M.close()
    end
  end)
end

-- ボードを閉じる
function M.close()
  if _unsubscribe then
    _unsubscribe()
    _unsubscribe = nil
  end
  if _popup then
    _popup:unmount()
    _popup = nil
  end
  _cursor = { col = 1, card = 1 }
end

-- ボードを再描画する（card_detail / card_form から呼ばれる）
function M.refresh_render()
  render()
end

return M
