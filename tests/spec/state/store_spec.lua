local store = require("gh_board.state.store")
local projects = require("gh_board.api.projects")

-- テスト用 BoardState フィクスチャ
local function make_state()
  return {
    project = { id = "PVT_001", number = 1, title = "Test Project", url = "", closed = false },
    columns = {
      { id = "opt_todo", field_id = "field1", name = "Todo", color = "GRAY" },
      { id = "opt_done", field_id = "field1", name = "Done", color = "GREEN" },
    },
    cards = {
      {
        id = "PVTI_c1",
        column_id = "opt_todo",
        content = {
          id = "DI_1",
          kind = "draft",
          title = "Card One",
          body = "",
          assignees = {},
          labels = {},
          created_at = "",
          updated_at = "",
        },
      },
      {
        id = "PVTI_c2",
        column_id = "opt_todo",
        content = {
          id = "DI_2",
          kind = "draft",
          title = "Card Two",
          body = "",
          assignees = {},
          labels = {},
          created_at = "",
          updated_at = "",
        },
      },
    },
    status_field_id = "field1",
  }
end

describe("state/store", function()
  before_each(function()
    store.reset()
  end)

  describe("subscribe / notify", function()
    it("calls listener when apply_create is called", function()
      -- load をモックして状態をセット
      local orig_get_board = projects.get_board
      projects.get_board = function(_, cb)
        cb(nil, make_state())
      end
      store.load("PVT_001", function() end)

      -- load 後に購読してその後の通知だけを検知する
      local called = false
      local unsub = store.subscribe(function()
        called = true
      end)

      store.apply_create({
        id = "PVTI_new",
        column_id = "opt_todo",
        content = {
          id = "DI_new",
          kind = "draft",
          title = "New Card",
          body = "",
          assignees = {},
          labels = {},
          created_at = "",
          updated_at = "",
        },
      })

      projects.get_board = orig_get_board
      unsub()

      assert.is_true(called)
    end)

    it("unsubscribe stops future notifications", function()
      local count = 0
      local unsub = store.subscribe(function()
        count = count + 1
      end)

      -- 一度通知
      local orig_get_board = projects.get_board
      projects.get_board = function(_, cb)
        cb(nil, make_state())
      end
      store.load("PVT_001", function() end)
      local after_load = count

      unsub()

      -- 購読解除後に通知
      store.apply_create({
        id = "PVTI_x",
        column_id = "opt_todo",
        content = { id = "x", kind = "draft", title = "X", body = "", assignees = {}, labels = {}, created_at = "", updated_at = "" },
      })

      projects.get_board = orig_get_board

      assert.equals(after_load, count)
    end)
  end)

  describe("apply_create", function()
    it("adds card to state", function()
      local orig = projects.get_board
      projects.get_board = function(_, cb)
        cb(nil, make_state())
      end
      store.load("PVT_001", function() end)
      projects.get_board = orig

      local new_card = {
        id = "PVTI_new",
        column_id = "opt_done",
        content = { id = "DI_new", kind = "draft", title = "New", body = "", assignees = {}, labels = {}, created_at = "", updated_at = "" },
      }
      store.apply_create(new_card)

      local state = store.get_state()
      assert.equals(3, #state.cards)
      assert.equals("PVTI_new", state.cards[3].id)
    end)
  end)

  describe("apply_delete", function()
    it("removes card from state", function()
      local orig = projects.get_board
      projects.get_board = function(_, cb)
        cb(nil, make_state())
      end
      store.load("PVT_001", function() end)
      projects.get_board = orig

      store.apply_delete("PVTI_c1")

      local state = store.get_state()
      assert.equals(1, #state.cards)
      assert.equals("PVTI_c2", state.cards[1].id)
    end)
  end)

  describe("apply_update", function()
    it("replaces card content in state", function()
      local orig = projects.get_board
      projects.get_board = function(_, cb)
        cb(nil, make_state())
      end
      store.load("PVT_001", function() end)
      projects.get_board = orig

      local updated = {
        id = "PVTI_c1",
        column_id = "opt_todo",
        content = { id = "DI_1", kind = "draft", title = "Updated Title", body = "new body", assignees = {}, labels = {}, created_at = "", updated_at = "" },
      }
      store.apply_update(updated)

      local state = store.get_state()
      assert.equals("Updated Title", state.cards[1].content.title)
      assert.equals("new body", state.cards[1].content.body)
    end)
  end)

  describe("optimistic_move", function()
    it("updates column_id immediately", function()
      local orig_get_board = projects.get_board
      local orig_move_card = projects.move_card

      projects.get_board = function(_, cb)
        cb(nil, make_state())
      end
      projects.move_card = function(_, _, _, _, cb)
        -- 非同期成功をシミュレート（同期的に呼ぶ）
        cb(nil)
      end

      store.load("PVT_001", function() end)

      -- 移動前
      assert.equals("opt_todo", store.get_state().cards[1].column_id)

      store.optimistic_move("PVTI_c1", "opt_done", function() end)

      -- 即座に反映されている
      assert.equals("opt_done", store.get_state().cards[1].column_id)

      projects.get_board = orig_get_board
      projects.move_card = orig_move_card
    end)

    it("rolls back column_id when API fails", function()
      local orig_get_board = projects.get_board
      local orig_move_card = projects.move_card

      projects.get_board = function(_, cb)
        cb(nil, make_state())
      end

      local revert_called = false
      projects.move_card = function(_, _, _, _, cb)
        cb({ message = "API error", type = "network" })
      end

      store.load("PVT_001", function() end)
      store.optimistic_move("PVTI_c1", "opt_done", function(_)
        revert_called = true
      end)

      -- ロールバック後は元のカラムに戻っている
      assert.equals("opt_todo", store.get_state().cards[1].column_id)
      assert.is_true(revert_called)

      projects.get_board = orig_get_board
      projects.move_card = orig_move_card
    end)
  end)
end)
