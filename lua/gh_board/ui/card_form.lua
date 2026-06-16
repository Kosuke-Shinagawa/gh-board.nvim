local Popup = require("nui.popup")
local store = require("gh_board.state.store")
local projects = require("gh_board.api.projects")

local M = {}

-- GhBoardBorder hl を現在の colorscheme に合わせて定義する
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

-- フロートウィンドウでタイトルを 1 行入力させるフォーム
-- <CR> / <C-s> で送信、<Esc> / q でキャンセル
---@param title_label string フロートのタイトルバーに表示するラベル
---@param on_submit fun(title: string)
local function open_title_float(title_label, on_submit)
  define_border_hl()

  local popup = Popup({
    enter = true,
    focusable = true,
    border = { style = "rounded" },
    position = "50%",
    size = { width = 60, height = 1 },
    buf_options = { modifiable = true },
    win_options = {
      winhighlight = WHL,
      wrap = false,
      number = false,
    },
  })

  popup:mount()

  pcall(vim.api.nvim_win_set_config, popup.winid, {
    title = " " .. title_label .. " ",
    title_pos = "center",
    footer = " <Enter> 作成  <Esc> キャンセル ",
    footer_pos = "center",
  })

  vim.cmd("startinsert")

  local function submit()
    local lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, 1, false)
    local title = vim.trim(lines[1] or "")
    if title == "" then
      vim.notify("gh-board: Title is required.", vim.log.levels.WARN)
      return
    end
    vim.cmd("stopinsert")
    popup:unmount()
    on_submit(title)
  end

  local function cancel()
    vim.cmd("stopinsert")
    popup:unmount()
  end

  local map_opts = { buffer = popup.bufnr, nowait = true, silent = true }
  vim.keymap.set({ "i", "n" }, "<CR>", submit, map_opts)
  vim.keymap.set({ "i", "n" }, "<C-s>", submit, map_opts)
  vim.keymap.set({ "i", "n" }, "<Esc>", cancel, map_opts)
  vim.keymap.set("n", "q", cancel, map_opts)
end

-- 新しいタブで通常の markdown バッファを開くフォーム（編集用）
-- 1行目: "# タイトル"、2行目: 空行、3行目以降: 本文
-- :w / <C-s> で送信、q / <Esc> でキャンセル
---@param initial_title string
---@param initial_body string
---@param form_label string バッファ名に使うラベル
---@param on_submit fun(title: string, body: string)
local function open_buf_form(initial_title, initial_body, form_label, on_submit)
  local lines = { "# " .. initial_title, "" }
  if initial_body ~= "" then
    for _, line in ipairs(vim.split(initial_body, "\n", { plain = true })) do
      table.insert(lines, line)
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modified = false

  local buf_name = "gh-board://" .. form_label:lower():gsub("%s+", "-")
  pcall(vim.api.nvim_buf_set_name, buf, buf_name)

  local tabs_before = #vim.api.nvim_list_tabpages()
  vim.cmd("tabnew")
  vim.api.nvim_set_current_buf(buf)
  local new_tab = vim.api.nvim_get_current_tabpage()

  local function close_form()
    if vim.api.nvim_tabpage_is_valid(new_tab) and #vim.api.nvim_list_tabpages() > tabs_before then
      vim.cmd("tabclose")
    elseif vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  local function submit()
    local content = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local title = vim.trim((content[1] or ""):gsub("^#%s*", ""))
    if title == "" then
      vim.notify("gh-board: Title is required.", vim.log.levels.WARN)
      return
    end
    local body_lines = {}
    for i = 3, #content do
      table.insert(body_lines, content[i])
    end
    while #body_lines > 0 and vim.trim(body_lines[#body_lines]) == "" do
      table.remove(body_lines)
    end
    local body = table.concat(body_lines, "\n")
    on_submit(title, body)
  end

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      vim.bo[buf].modified = false
      submit()
    end,
  })

  local map_opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "q", close_form, map_opts)
  vim.keymap.set("n", "<Esc>", close_form, map_opts)
  vim.keymap.set({ "n", "i" }, "<C-s>", function()
    vim.cmd("write")
  end, map_opts)

  vim.notify(
    string.format("[gh-board] %s — :w or <C-s> to submit, q to close", form_label),
    vim.log.levels.INFO
  )
end

-- 新規カード作成フォームを開く（タイトルのみ入力するフロートウィンドウ）
---@param state BoardState
---@param col_idx integer デフォルトで選択するカラムのインデックス
function M.open_create(state, col_idx)
  local default_col = state.columns[col_idx] or state.columns[1]

  open_title_float("New Card — " .. default_col.name, function(title)
    projects.create_card(state.project.id, title, "", function(err, item_id)
      if err then
        vim.notify("gh-board: " .. err.message, vim.log.levels.ERROR)
        return
      end

      if not item_id then
        vim.notify("gh-board: Failed to get created item ID.", vim.log.levels.ERROR)
        return
      end

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

          -- 楽観的更新: GitHub API の反映を待たずに即座にボードへ追加
          store.apply_create({
            id = item_id,
            column_id = default_col.id,
            content = {
              id = "",
              kind = "draft",
              number = nil,
              title = title,
              body = "",
              state = nil,
              url = nil,
              assignees = {},
              labels = {},
              created_at = "",
              updated_at = "",
            },
          })

          -- GitHub 側の反映後にサーバーと同期して content.id などを正確にする
          vim.defer_fn(function()
            store.load(state.project.id, function(load_err)
              if load_err then
                vim.notify("gh-board: " .. load_err.message, vim.log.levels.ERROR)
              end
            end)
          end, 1500)
        end
      )
    end)
  end)
end

-- 既存カードの編集フォームを開く（タイトル + 本文を markdown バッファで編集）
---@param card GhCard
---@param state BoardState
function M.open_edit(card, _state)
  open_buf_form(card.content.title, card.content.body or "", "Edit Card", function(title, body)
    projects.update_card(card, title, body, function(err)
      if err then
        vim.notify("gh-board: " .. err.message, vim.log.levels.ERROR)
        return
      end

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
