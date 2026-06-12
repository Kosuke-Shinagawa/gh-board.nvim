local Popup = require("nui.popup")
local config = require("gh_board.config")
local store = require("gh_board.state.store")
local projects = require("gh_board.api.projects")

local M = {}

---@type any nui Popup インスタンス
local _popup = nil

local function close()
  if _popup then
    _popup:unmount()
    _popup = nil
  end
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
  local kind_label = ({ draft = "Draft Issue", issue = "Issue", pr = "Pull Request" })[c.kind] or c.kind
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
    table.insert(lines, "  ── Description ──────────────────────────────")
    for _, body_line in ipairs(vim.split(c.body, "\n", { plain = true })) do
      table.insert(lines, "  " .. body_line)
    end
  end

  -- キーマップヒント
  table.insert(lines, "")
  table.insert(lines, "  [e] edit  [d] delete  [q] close")

  return lines
end

-- カード詳細ポップアップを開く
---@param card GhCard
---@param state BoardState
function M.open(card, state)
  if _popup then
    close()
  end

  local km = config.options.keymaps
  local lines = build_lines(card)

  local popup_width = math.min(80, config.options.win_width - 4)
  local popup_height = math.min(#lines + 2, config.options.win_height - 4)

  _popup = Popup({
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = " Card Detail ",
        top_align = "left",
      },
    },
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
    },
  })

  _popup:mount()

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

  map(km.close, close)
  map("<Esc>", close)
end

return M
