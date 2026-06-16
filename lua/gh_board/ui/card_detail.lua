local Popup = require("nui.popup")
local config = require("gh_board.config")
local store = require("gh_board.state.store")
local projects = require("gh_board.api.projects")

local M = {}

---@type any nui Popup インスタンス
local _popup = nil

-- close() 直後に同フレームで board の q が発火しても無視できるよう
-- 「直前に閉じた」ことを 1 tick 間記録する
local _just_closed = false

local function close()
  if _popup then
    _popup:unmount()
    _popup = nil
    _just_closed = true
    vim.schedule(function()
      _just_closed = false
    end)
  end
end

function M.is_open()
  return _popup ~= nil
end

function M.was_just_closed()
  return _just_closed
end

function M.close()
  close()
end

-- カードの詳細テキスト行を生成する
---@param card GhCard
---@return string[]
local function build_lines(card)
  local c = card.content
  local lines = {}

  -- タイトル
  table.insert(lines, "  " .. c.title)
  table.insert(lines, "")

  -- メタ情報
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

  if c.created_at ~= "" then
    table.insert(lines, string.format("  Created : %s", c.created_at:sub(1, 10)))
  end

  if c.updated_at ~= "" then
    table.insert(lines, string.format("  Updated : %s", c.updated_at:sub(1, 10)))
  end

  -- 本文
  if c.body and c.body ~= "" then
    table.insert(lines, "")
    table.insert(
      lines,
      "  ── Description ──────────────────────────────"
    )
    for _, body_line in ipairs(vim.split(c.body, "\n", { plain = true })) do
      table.insert(lines, "  " .. body_line)
    end
  end

  -- キーマップヒント
  table.insert(lines, "")
  table.insert(lines, "  [e] edit  [d] delete  [C] open/close  [q] close")

  return lines
end

-- カード詳細ポップアップを開く
---@param card GhCard
---@param state BoardState
function M.open(card, state)
  if _popup then
    close()
  end

  -- FloatBorder fg を維持しつつ bg を Normal に合わせる
  do
    local fb = vim.api.nvim_get_hl(0, { name = "FloatBorder", link = false })
    local nb = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
    vim.api.nvim_set_hl(0, "GhBoardBorder", {
      fg = fb.fg,
      bg = nb.bg,
      ctermfg = fb.ctermfg,
      ctermbg = nb.ctermbg,
    })
  end

  local km = config.options.keymaps
  local lines = build_lines(card)

  local popup_width = math.min(80, config.options.win_width - 4)
  local popup_height = math.min(#lines + 2, config.options.win_height - 4)

  _popup = Popup({
    enter = true,
    focusable = true,
    zindex = 200,
    border = { style = "rounded" },
    position = "50%",
    size = {
      width = popup_width,
      height = popup_height,
    },
    buf_options = {
      modifiable = false,
      readonly = true,
    },
    win_options = {
      wrap = true,
      cursorline = false,
      number = false,
      winhighlight = "Normal:Normal,NormalFloat:Normal,FloatBorder:GhBoardBorder,EndOfBuffer:Normal",
    },
  })

  _popup:mount()
  pcall(vim.api.nvim_win_set_config, _popup.winid, {
    title = " Card Detail ",
    title_pos = "left",
  })

  -- 内容を描画
  vim.api.nvim_buf_set_option(_popup.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(_popup.bufnr, 0, -1, false, lines)
  -- タイトル行をボールドに
  local ns = vim.api.nvim_create_namespace("gh_board_detail")
  vim.api.nvim_buf_add_highlight(_popup.bufnr, ns, "Title", 0, 0, -1)
  vim.api.nvim_buf_set_option(_popup.bufnr, "modifiable", false)

  -- キーマップ
  local function map(key, fn)
    vim.keymap.set("n", key, fn, { buffer = _popup.bufnr, nowait = true, silent = true })
  end

  map(km.edit_card, function()
    close()
    require("gh_board.ui.card_form").open_edit(card, state)
  end)

  map(km.delete_card, function()
    vim.ui.input({
      prompt = string.format('Delete "%s"? [y/N] ', card.content.title),
    }, function(input)
      if input ~= "y" and input ~= "Y" then
        return
      end
      projects.delete_card(state.project.id, card.id, function(err)
        if err then
          vim.notify("gh-board: " .. err.message, vim.log.levels.ERROR)
          return
        end
        store.apply_delete(card.id)
        close()
      end)
    end)
  end)

  map(km.promote_card, function()
    if card.content.kind ~= "draft" then
      vim.notify("gh-board: Draft Issue のみ変換できます", vim.log.levels.WARN)
      return
    end
    local owner = config.options.default_owner
    if not owner then
      vim.notify("gh-board: default_owner が設定されていません", vim.log.levels.ERROR)
      return
    end
    close()
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
      vim.ui.select(names, { prompt = "Issue を作成するリポジトリを選択:" }, function(_, idx)
        if not idx then
          return
        end
        projects.convert_draft_to_issue(card.id, repos[idx].id, function(conv_err)
          if conv_err then
            vim.notify("gh-board: " .. conv_err.message, vim.log.levels.ERROR)
            return
          end
          store.apply_delete(card.id)
          store.load(state.project.id, function(load_err)
            if load_err then
              vim.notify("gh-board: " .. load_err.message, vim.log.levels.ERROR)
            end
          end)
        end)
      end)
    end)
  end)

  map(km.close_issue, function()
    if card.content.kind ~= "issue" then
      vim.notify("gh-board: Issue のみステータス変更できます", vim.log.levels.WARN)
      return
    end
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
      close()
    end)
  end)

  map(km.close, close)
  map("<Esc>", close)
end

return M
