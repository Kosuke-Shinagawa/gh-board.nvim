local projects = require("gh_board.api.projects")

local M = {}

---@type BoardState|nil
local _state = nil

---@type BoardState|nil  楽観的更新前のスナップショット
local _snapshot = nil

-- 状態変更を通知するコールバック一覧
---@type fun()[]
local _listeners = {}

local function notify()
  for _, cb in ipairs(_listeners) do
    cb()
  end
end

-- テーブルの浅いコピー（cards 配列の各要素は shallow copy）
---@param state BoardState
---@return BoardState
local function shallow_copy_state(state)
  local cards = {}
  for i, card in ipairs(state.cards) do
    cards[i] = vim.tbl_extend("force", {}, card)
  end

  return {
    project = vim.tbl_extend("force", {}, state.project),
    columns = vim.deepcopy(state.columns),
    cards = cards,
    status_field_id = state.status_field_id,
  }
end

-- 状態変更リスナーを登録する。戻り値は登録解除関数。
---@param cb fun()
---@return fun()
function M.subscribe(cb)
  table.insert(_listeners, cb)
  return function()
    for i, listener in ipairs(_listeners) do
      if listener == cb then
        table.remove(_listeners, i)
        break
      end
    end
  end
end

-- 現在の状態を返す
---@return BoardState|nil
function M.get_state()
  return _state
end

-- API からボードを取得して状態を更新する
---@param project_id string
---@param callback fun(err: ApiError|nil)
function M.load(project_id, callback)
  projects.get_board(project_id, function(err, board)
    if err then
      callback(err)
      return
    end

    _state = board
    _snapshot = nil
    notify()
    callback(nil)
  end)
end

-- カードのカラムを楽観的に更新し、バックグラウンドで API を呼ぶ
-- API 失敗時はスナップショットに戻して on_revert を呼ぶ
---@param item_id string
---@param column_id string
---@param on_revert fun(err: ApiError)
function M.optimistic_move(item_id, column_id, on_revert)
  if not _state then
    return
  end

  _snapshot = shallow_copy_state(_state)

  -- 状態を即座に更新
  for _, card in ipairs(_state.cards) do
    if card.id == item_id then
      card.column_id = column_id
      break
    end
  end

  notify()

  -- バックグラウンドで API 呼び出し
  projects.move_card(_state.project.id, item_id, _state.status_field_id, column_id, function(err)
    if err then
      -- ロールバック
      _state = _snapshot
      _snapshot = nil
      notify()
      on_revert(err)
    else
      _snapshot = nil
    end
  end)
end

-- 作成成功後にカードを追加する
---@param card GhCard
function M.apply_create(card)
  if not _state then
    return
  end
  table.insert(_state.cards, card)
  notify()
end

-- 更新成功後にカードを差し替える
---@param updated GhCard
function M.apply_update(updated)
  if not _state then
    return
  end
  for i, card in ipairs(_state.cards) do
    if card.id == updated.id then
      _state.cards[i] = updated
      break
    end
  end
  notify()
end

-- 削除成功後にカードを除去する
---@param item_id string
function M.apply_delete(item_id)
  if not _state then
    return
  end
  for i, card in ipairs(_state.cards) do
    if card.id == item_id then
      table.remove(_state.cards, i)
      break
    end
  end
  notify()
end

-- 状態をリセットする（プロジェクト切り替え時など）
function M.reset()
  _state = nil
  _snapshot = nil
  _listeners = {}
end

return M
