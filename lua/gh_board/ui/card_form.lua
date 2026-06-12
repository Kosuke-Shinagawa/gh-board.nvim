local Popup = require("nui.popup")
local Input = require("nui.input")
local store = require("gh_board.state.store")
local projects = require("gh_board.api.projects")

local M = {}

---@type any[] 開いているウィンドウ一覧（title input + body popup）
local _windows = {}

local function close_all()
  for _, w in ipairs(_windows) do
    pcall(function()
      w:unmount()
    end)
  end
  _windows = {}
end

-- タイトル入力 Input と本文入力 Popup を積み上げるフォームを開く
-- on_submit(title, body) が確定時に呼ばれる
---@param initial_title string
---@param initial_body string
---@param form_label string ウィンドウタイトル
---@param on_submit fun(title: string, body: string)
local function open_form(initial_title, initial_body, form_label, on_submit)
  close_all()

  local form_width = 70
  local body_height = 10

  -- 本文エディタ（上部）
  local body_popup = Popup({
    enter = false,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = " Body (optional) ",
        top_align = "left",
        bottom = " <CR> confirm  <Esc> cancel ",
        bottom_align = "center",
      },
    },
    position = {
      row = math.floor((vim.o.lines - body_height - 6) / 2),
      col = math.floor((vim.o.columns - form_width) / 2),
    },
    size = { width = form_width, height = body_height },
    buf_options = { modifiable = true, filetype = "markdown" },
    win_options = { wrap = true, number = false },
  })

  -- タイトル入力（下部、本文の直下）
  local title_input = Input({
    border = {
      style = "rounded",
      text = {
        top = string.format(" %s ", form_label),
        top_align = "left",
      },
    },
    position = {
      row = math.floor((vim.o.lines - body_height - 6) / 2) + body_height + 2,
      col = math.floor((vim.o.columns - form_width) / 2),
    },
    size = { width = form_width },
  }, {
    prompt = "Title: ",
    default_value = initial_title,
    on_submit = function(title_value)
      if vim.trim(title_value) == "" then
        vim.notify("gh-board: Title is required.", vim.log.levels.WARN)
        return
      end
      local body_lines = vim.api.nvim_buf_get_lines(body_popup.bufnr, 0, -1, false)
      local body_value = table.concat(body_lines, "\n")
      -- 末尾の空行を除去
      body_value = body_value:gsub("%s+$", "")
      close_all()
      on_submit(vim.trim(title_value), body_value)
    end,
    on_close = function()
      close_all()
    end,
  })

  body_popup:mount()
  title_input:mount()

  table.insert(_windows, body_popup)
  table.insert(_windows, title_input)

  -- 初期値を本文バッファにセット
  if initial_body ~= "" then
    local body_lines = vim.split(initial_body, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(body_popup.bufnr, 0, -1, false, body_lines)
  end

  -- <Tab> で title_input ↔ body_popup を切り替える
  vim.keymap.set("n", "<Tab>", function()
    if vim.api.nvim_get_current_win() == title_input.winid then
      vim.api.nvim_set_current_win(body_popup.winid)
      vim.cmd("startinsert")
    else
      vim.api.nvim_set_current_win(title_input.winid)
      vim.cmd("startinsert!")
    end
  end, { buffer = title_input.bufnr, nowait = true, silent = true })

  vim.keymap.set({ "n", "i" }, "<Tab>", function()
    vim.api.nvim_set_current_win(title_input.winid)
    vim.cmd("startinsert!")
  end, { buffer = body_popup.bufnr, nowait = true, silent = true })

  vim.keymap.set({ "n", "i" }, "<Esc>", function()
    close_all()
  end, { buffer = body_popup.bufnr, nowait = true, silent = true })

  -- タイトル入力にフォーカスして Insert モードで開始
  vim.api.nvim_set_current_win(title_input.winid)
  vim.cmd("startinsert!")
end

-- 新規カード作成フォームを開く
---@param state BoardState
---@param col_idx integer デフォルトで選択するカラムのインデックス
function M.open_create(state, col_idx)
  local default_col = state.columns[col_idx] or state.columns[1]

  open_form("", "", "New Card", function(title, body)
    projects.create_card(state.project.id, title, body, function(err, item_id)
      if err then
        vim.notify("gh-board: " .. err.message, vim.log.levels.ERROR)
        return
      end

      if not item_id then
        vim.notify("gh-board: Failed to get created item ID.", vim.log.levels.ERROR)
        return
      end

      -- 作成直後は Status が未設定のため move_card でカラムを設定する
      projects.move_card(
        state.project.id,
        item_id,
        state.status_field_id,
        default_col.id,
        function(move_err)
          if move_err then
            vim.notify(
              "gh-board: Card created but failed to set status: " .. move_err.message,
              vim.log.levels.WARN
            )
          end

          -- ボードをリフレッシュして新カードを表示
          store.load(state.project.id, function(load_err)
            if load_err then
              vim.notify("gh-board: " .. load_err.message, vim.log.levels.ERROR)
            end
          end)
        end
      )
    end)
  end)
end

-- 既存カードの編集フォームを開く
---@param card GhCard
---@param state BoardState
function M.open_edit(card, state)
  open_form(card.content.title, card.content.body or "", "Edit Card", function(title, body)
    projects.update_card(card, title, body, function(err)
      if err then
        vim.notify("gh-board: " .. err.message, vim.log.levels.ERROR)
        return
      end

      -- 更新済みカードをストアに反映（再描画は store 経由で行う）
      local updated_card = vim.tbl_deep_extend("force", {}, card)
      updated_card.content = vim.tbl_extend("force", {}, card.content, {
        title = title,
        body = body,
      })
      store.apply_update(updated_card)
    end)
  end)
end

return M
