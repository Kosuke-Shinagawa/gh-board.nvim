local Popup = require("nui.popup")
local config = require("gh_board.config")
local store = require("gh_board.state.store")
local column_comp = require("gh_board.ui.components.column")

local M = {}

---@type { col: integer, card: integer }
local _cursor = { col = 1, card = 1 }

---@type any nui Popup（ボード）
local _popup = nil
---@type any nui Popup（プレビュー）
local _preview = nil
---@type any nui Popup（ヘルプ）
local _help = nil
---@type any nui Popup（検索入力）
local _search_popup = nil
---@type string 現在の検索クエリ
local _search_query = ""
---@type fun() store 購読解除
local _unsubscribe = nil

local function calc_col_width(win_width, num_cols)
  if num_cols == 0 then
    return win_width
  end
  return math.floor((win_width - num_cols - 1) / num_cols)
end

local function col_byte_range(line, ci)
  local sep = "│"
  local sep_len = #sep
  local pos = 1
  for i = 1, ci do
    local found = line:find(sep, pos, true)
    if not found then
      return nil, nil
    end
    if i == ci then
      local s = found + sep_len - 1
      local next_sep = line:find(sep, found + sep_len, true)
      local e = next_sep and (next_sep - 1) or #line
      return s, e
    end
    pos = found + sep_len
  end
  return nil, nil
end

-- カーソルハイライト用: 左右の │ を含む範囲（0 始まり）
local function col_byte_range_with_sep(line, ci)
  local sep = "│"
  local sep_len = #sep
  local pos = 1
  for i = 1, ci do
    local found = line:find(sep, pos, true)
    if not found then
      return nil, nil
    end
    if i == ci then
      local s = found - 1
      local next_sep = line:find(sep, found + sep_len, true)
      local e = next_sep and (next_sep + sep_len - 1) or #line
      return s, e
    end
    pos = found + sep_len
  end
  return nil, nil
end

-- 検索クエリを適用してカラムのカードを返す
local function get_cards_for_col(state, col)
  local cards = vim.tbl_filter(function(c)
    return c.column_id == col.id
  end, state.cards)
  if _search_query == "" then
    return cards
  end
  local q = _search_query:lower()
  return vim.tbl_filter(function(c)
    local title = (c.content.title or ""):lower()
    local num = c.content.number and tostring(c.content.number) or ""
    return title:find(q, 1, true) ~= nil or num:find(q, 1, true) ~= nil
  end, cards)
end

local function clamp_cursor(state)
  local num_cols = #state.columns
  _cursor.col = math.max(1, math.min(_cursor.col, num_cols))
  local col = state.columns[_cursor.col]
  local cards_in_col = get_cards_for_col(state, col)
  local max_card = math.max(1, #cards_in_col)
  _cursor.card = math.max(1, math.min(_cursor.card, max_card))
end

local function current_card(state)
  if _cursor.col > #state.columns then
    return nil
  end
  local col = state.columns[_cursor.col]
  local cards_in_col = get_cards_for_col(state, col)
  return cards_in_col[_cursor.card]
end

local function render_preview()
  if not _preview or not _preview.bufnr then
    return
  end

  local state = store.get_state()
  local bufnr = _preview.bufnr

  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)

  if not state then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    return
  end

  local card = current_card(state)

  if not card then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    return
  end

  local c = card.content
  local lines = {}

  table.insert(lines, "  " .. c.title)
  table.insert(lines, "")

  local kind_label = ({ draft = "Draft Issue", issue = "Issue", pr = "Pull Request" })[c.kind]
    or c.kind
  table.insert(lines, string.format("  Type    : %s", kind_label))
  if c.number then
    table.insert(lines, string.format("  Number  : #%d", c.number))
  end
  if c.state then
    table.insert(lines, string.format("  State   : %s", c.state))
  end
  if #c.assignees > 0 then
    table.insert(lines, string.format("  Assignee: %s", table.concat(c.assignees, ", ")))
  end
  if c.labels and #c.labels > 0 then
    local label_names = vim.tbl_map(function(l)
      return l.name
    end, c.labels)
    table.insert(lines, string.format("  Labels  : %s", table.concat(label_names, ", ")))
  end
  if c.url then
    table.insert(lines, string.format("  URL     : %s", c.url))
  end

  if c.body and c.body ~= "" then
    table.insert(lines, "")
    table.insert(
      lines,
      "  ── Body ─────────────────────────────────────"
    )
    for _, body_line in ipairs(vim.split(c.body, "\n", { plain = true })) do
      table.insert(lines, "  " .. body_line)
    end
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  local ns = vim.api.nvim_create_namespace("gh_board_preview")
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, ns, "Title", 0, 0, -1)

  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
end

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

  local win_width = vim.api.nvim_win_get_width(_popup.winid) - 2
  local num_cols = #state.columns
  local col_width = calc_col_width(win_width, num_cols)

  ---@type string[][]
  local all_col_lines = {}
  ---@type { row: integer, col_idx: integer, hl: string }[]
  local all_highlights = {}

  for ci, col in ipairs(state.columns) do
    local cards_in_col = get_cards_for_col(state, col)
    local lines, hls = column_comp.render(col, cards_in_col, col_width)
    all_col_lines[ci] = lines
    for _, hl_info in ipairs(hls) do
      table.insert(all_highlights, { row = hl_info.row, col_idx = ci, hl = hl_info.hl })
    end
  end

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

  vim.api.nvim_buf_clear_namespace(bufnr, -1, 0, -1)
  local ns = vim.api.nvim_create_namespace("gh_board")

  for _, hl_info in ipairs(all_highlights) do
    local buf_row = hl_info.row - 1
    local hl_line = grid_lines[hl_info.row]
    if hl_line then
      local bs, be = col_byte_range(hl_line, hl_info.col_idx)
      if bs then
        pcall(vim.api.nvim_buf_add_highlight, bufnr, ns, hl_info.hl, buf_row, bs, be)
      end
    end
  end

  -- カーソル行のハイライト（左右の │ を含む）
  clamp_cursor(state)
  local cursor_buf_row = column_comp.HEADER_LINES + _cursor.card - 1
  local cursor_line = grid_lines[cursor_buf_row + 1]
  if cursor_line then
    local cbs_full, cbe_full = col_byte_range_with_sep(cursor_line, _cursor.col)
    if cbs_full then
      pcall(
        vim.api.nvim_buf_add_highlight,
        bufnr,
        ns,
        "GhBoardCursor",
        cursor_buf_row,
        cbs_full,
        cbe_full
      )
    end
    local cbs, _ = col_byte_range(cursor_line, _cursor.col)
    if cbs then
      pcall(vim.api.nvim_win_set_cursor, _popup.winid, { cursor_buf_row + 1, cbs })
    end
  end

  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  render_preview()
end

local function setup_keymaps()
  local km = config.options.keymaps
  local bufnr = _popup.bufnr

  local function map(key, fn)
    vim.keymap.set("n", key, fn, { buffer = bufnr, nowait = true, silent = true })
  end

  map("j", function()
    local state = store.get_state()
    if not state then
      return
    end
    local col = state.columns[_cursor.col]
    local cards_in_col = get_cards_for_col(state, col)
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

  -- "/" で検索ボックスにフォーカス
  map("/", function()
    if _search_popup then
      vim.api.nvim_set_current_win(_search_popup.winid)
      vim.cmd("startinsert!")
    end
  end)

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

  map(km.promote_card, function()
    local state = store.get_state()
    if not state then
      return
    end
    local card = current_card(state)
    if not card then
      return
    end
    if card.content.kind ~= "draft" then
      vim.notify("gh-board: Draft Issue のみ変換できます", vim.log.levels.WARN)
      return
    end

    local projects = require("gh_board.api.projects")
    local owner = config.options.default_owner
    if not owner then
      vim.notify("gh-board: default_owner が設定されていません", vim.log.levels.ERROR)
      return
    end

    projects.list_repos(owner, function(err, repos)
      if err then
        vim.notify("gh-board: " .. err.message, vim.log.levels.ERROR)
        return
      end
      if not repos or #repos == 0 then
        vim.notify("gh-board: リポジトリが見つかりません", vim.log.levels.WARN)
        return
      end

      local names = vim.tbl_map(function(r)
        return r.full_name
      end, repos)

      vim.ui.select(
        names,
        { prompt = "Issue を作成するリポジトリを選択:" },
        function(_, idx)
          if not idx then
            return
          end
          local repo = repos[idx]
          projects.convert_draft_to_issue(card.id, repo.id, function(conv_err)
            if conv_err then
              vim.notify("gh-board: " .. conv_err.message, vim.log.levels.ERROR)
              return
            end
            store.load(state.project.id, function(load_err)
              if load_err then
                vim.notify("gh-board: " .. load_err.message, vim.log.levels.ERROR)
              end
            end)
          end)
        end
      )
    end)
  end)

  map(km.close_issue, function()
    local state = store.get_state()
    if not state then
      return
    end
    local card = current_card(state)
    if not card then
      return
    end
    if card.content.kind ~= "issue" then
      vim.notify("gh-board: Issue のみステータス変更できます", vim.log.levels.WARN)
      return
    end

    local projects = require("gh_board.api.projects")
    local is_open = card.content.state == "OPEN"
    local new_state = is_open and "CLOSED" or "OPEN"

    local fn = is_open and projects.close_issue or projects.reopen_issue
    fn(card.content.id, function(err)
      if err then
        vim.notify("gh-board: " .. err.message, vim.log.levels.ERROR)
        return
      end
      local updated = vim.tbl_deep_extend("force", {}, card)
      updated.content = vim.tbl_extend("force", {}, card.content, { state = new_state })
      store.apply_update(updated)
      vim.notify(
        string.format("gh-board: Issue #%d を %s にしました", card.content.number, new_state),
        vim.log.levels.INFO
      )
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
    local detail = require("gh_board.ui.card_detail")
    if detail.is_open() then
      detail.close()
      return
    end
    -- card_detail が直前のフレームで閉じた場合（q のキー漏れ）は board を閉じない
    if detail.was_just_closed() then
      return
    end
    M.close()
  end)

  map("<Esc>", function()
    local detail = require("gh_board.ui.card_detail")
    if detail.is_open() then
      detail.close()
      return
    end
    if detail.was_just_closed() then
      return
    end
    M.close()
  end)
end

-- FloatBorder の fg（文字色）を維持しつつ bg を Normal に合わせたボーダー用 hl を定義する
-- colorscheme ごとに色が変わるため open() 直前に毎回生成する
local function define_border_hl()
  local fb = vim.api.nvim_get_hl(0, { name = "FloatBorder", link = false })
  local nb = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  vim.api.nvim_set_hl(0, "GhBoardBorder", {
    fg = fb.fg,
    bg = nb.bg,
    ctermfg = fb.ctermfg,
    ctermbg = nb.ctermbg,
  })
end

local WHL = "Normal:Normal,NormalFloat:Normal,FloatBorder:GhBoardBorder,EndOfBuffer:Normal"

function M.open(project_id)
  if _popup then
    M.close()
  end

  column_comp.define_highlights()
  define_border_hl()

  local win_width = config.options.win_width
  local win_height = config.options.win_height

  -- 検索(3行) + ボード + プレビュー + ヘルプ(3行) を win_height に収める
  local search_outer = 3 -- 1 content + 2 border
  local help_outer = 3 -- 1 content + 2 border
  local avail = win_height - search_outer - help_outer
  local board_height = math.max(8, math.floor(avail * 0.65))
  local preview_height = math.max(5, avail - board_height - 2)

  local total_outer = search_outer + (board_height + 2) + (preview_height + 2) + help_outer
  local start_row = math.floor((vim.o.lines - total_outer) / 2)
  local start_col = math.floor((vim.o.columns - win_width) / 2)

  -- 検索ポップアップ
  _search_popup = Popup({
    enter = false,
    focusable = true,
    border = { style = "rounded" },
    position = { row = start_row, col = start_col },
    size = { width = win_width, height = 1 },
    buf_options = { modifiable = true },
    win_options = { wrap = false, number = false, winhighlight = WHL },
  })

  -- ボードポップアップ
  _popup = Popup({
    enter = true,
    focusable = true,
    border = { style = "rounded" },
    position = { row = start_row + search_outer, col = start_col },
    size = { width = win_width, height = board_height },
    buf_options = { modifiable = false, readonly = true },
    win_options = {
      wrap = false,
      cursorline = false,
      number = false,
      relativenumber = false,
      winhighlight = WHL,
    },
  })

  -- プレビューポップアップ
  _preview = Popup({
    enter = false,
    focusable = false,
    border = { style = "rounded" },
    position = { row = start_row + search_outer + board_height + 2, col = start_col },
    size = { width = win_width, height = preview_height },
    buf_options = { modifiable = false, readonly = true, filetype = "markdown" },
    win_options = {
      wrap = true,
      cursorline = false,
      number = false,
      relativenumber = false,
      winhighlight = WHL,
    },
  })

  -- ヘルプポップアップ（キーバインド一覧）
  _help = Popup({
    enter = false,
    focusable = false,
    border = { style = "rounded" },
    position = {
      row = start_row + search_outer + (board_height + 2) + (preview_height + 2),
      col = start_col,
    },
    size = { width = win_width, height = 1 },
    buf_options = { modifiable = false, readonly = true },
    win_options = { wrap = false, number = false, winhighlight = WHL },
  })

  _search_popup:mount()
  _popup:mount()
  _preview:mount()
  _help:mount()

  -- native Neovim title でラベルを付ける（nui border.text を使わないため別 window 不要）
  pcall(vim.api.nvim_win_set_config, _search_popup.winid, {
    title = " / Search ",
    title_pos = "left",
  })
  pcall(vim.api.nvim_win_set_config, _popup.winid, {
    title = " gh-board ",
    title_pos = "left",
  })
  pcall(vim.api.nvim_win_set_config, _preview.winid, {
    title = " Preview ",
    title_pos = "left",
  })
  pcall(vim.api.nvim_win_set_config, _help.winid, {
    title = " Keys ",
    title_pos = "left",
  })

  -- ヘルプ内容を書き込む（config のキーマップから生成）
  do
    local km = config.options.keymaps
    local entries = {
      { "j/k", "↓↑" },
      { "h/l", "←→" },
      { km.open_detail, "detail" },
      { km.new_card, "new" },
      { km.edit_card, "edit" },
      { km.move_card, "move" },
      { km.delete_card, "delete" },
      { km.promote_card, "promote" },
      { km.refresh, "refresh" },
      { "/", "search" },
      { km.close, "close" },
    }
    local parts = {}
    for _, e in ipairs(entries) do
      table.insert(parts, e[1] .. ":" .. e[2])
    end
    local help_line = "  " .. table.concat(parts, "  │  ")
    vim.api.nvim_buf_set_option(_help.bufnr, "modifiable", true)
    vim.api.nvim_buf_set_lines(_help.bufnr, 0, -1, false, { help_line })
    local ns = vim.api.nvim_create_namespace("gh_board_help")
    vim.api.nvim_buf_add_highlight(_help.bufnr, ns, "Comment", 0, 0, -1)
    vim.api.nvim_buf_set_option(_help.bufnr, "modifiable", false)
  end

  setup_keymaps()

  -- 検索バッファの変更をリアルタイムでボードに反映
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = _search_popup.bufnr,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(_search_popup.bufnr, 0, 1, false)
      _search_query = lines[1] or ""
      _cursor.card = 1
      render()
    end,
  })

  local function smap(modes, key, fn)
    vim.keymap.set(modes, key, fn, { buffer = _search_popup.bufnr, nowait = true, silent = true })
  end

  -- <Esc>: クエリをクリアしてボードに戻る
  smap({ "n", "i" }, "<Esc>", function()
    _search_query = ""
    vim.api.nvim_buf_set_lines(_search_popup.bufnr, 0, -1, false, { "" })
    vim.cmd("stopinsert")
    vim.api.nvim_set_current_win(_popup.winid)
    render()
  end)

  -- <CR> / <Tab>: クエリを維持してボードに戻る
  smap({ "n", "i" }, "<CR>", function()
    vim.cmd("stopinsert")
    vim.api.nvim_set_current_win(_popup.winid)
  end)

  smap({ "n", "i" }, "<Tab>", function()
    vim.cmd("stopinsert")
    vim.api.nvim_set_current_win(_popup.winid)
  end)

  -- ローディング表示
  vim.api.nvim_buf_set_option(_popup.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(_popup.bufnr, 0, -1, false, { " Loading…" })
  vim.api.nvim_buf_set_option(_popup.bufnr, "modifiable", false)

  _unsubscribe = store.subscribe(render)

  store.load(project_id, function(err)
    if err then
      vim.notify("gh-board: " .. err.message, vim.log.levels.ERROR)
      M.close()
    end
  end)
end

function M.close()
  if _unsubscribe then
    _unsubscribe()
    _unsubscribe = nil
  end
  if _search_popup then
    _search_popup:unmount()
    _search_popup = nil
  end
  if _preview then
    _preview:unmount()
    _preview = nil
  end
  if _help then
    _help:unmount()
    _help = nil
  end
  if _popup then
    _popup:unmount()
    _popup = nil
  end
  _cursor = { col = 1, card = 1 }
  _search_query = ""
end

function M.refresh_render()
  render()
end

return M
