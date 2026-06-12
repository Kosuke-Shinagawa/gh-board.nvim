local projects = require("gh_board.api.projects")

-- GetBoard GraphQL レスポンスの node フィールドのフィクスチャ
local function make_node(overrides)
  local base = {
    id = "PVT_kwDO001",
    title = "My Project",
    fields = {
      nodes = {
        {
          id = "PVTSSF_field1",
          name = "Status",
          options = {
            { id = "opt_todo", name = "Todo", color = "GRAY" },
            { id = "opt_inprogress", name = "In Progress", color = "YELLOW" },
            { id = "opt_done", name = "Done", color = "GREEN" },
          },
        },
      },
    },
    items = {
      nodes = {
        {
          id = "PVTI_item1",
          fieldValues = {
            nodes = {
              {
                optionId = "opt_todo",
                field = { id = "PVTSSF_field1", name = "Status" },
              },
            },
          },
          content = {
            id = "DI_draft1",
            title = "Fix login bug",
            body = "Something is broken",
            assignees = { nodes = { { login = "alice" } } },
            createdAt = "2026-06-01T00:00:00Z",
            updatedAt = "2026-06-10T00:00:00Z",
          },
        },
        {
          id = "PVTI_item2",
          fieldValues = {
            nodes = {
              {
                optionId = "opt_inprogress",
                field = { id = "PVTSSF_field1", name = "Status" },
              },
            },
          },
          content = {
            id = "I_issue1",
            number = 42,
            title = "Add OAuth support",
            body = "We need OAuth",
            state = "OPEN",
            url = "https://github.com/owner/repo/issues/42",
            assignees = { nodes = {} },
            labels = { nodes = { { name = "enhancement", color = "84b6eb" } } },
            createdAt = "2026-06-05T00:00:00Z",
            updatedAt = "2026-06-12T00:00:00Z",
          },
        },
      },
    },
  }
  return vim.tbl_deep_extend("force", base, overrides or {})
end

describe("api/projects._parse_board()", function()
  it("extracts columns from Status SingleSelectField", function()
    local board, err = projects._parse_board(make_node())

    assert.is_nil(err)
    assert.is_not_nil(board)
    assert.equals(3, #board.columns)
    assert.equals("Todo", board.columns[1].name)
    assert.equals("opt_todo", board.columns[1].id)
    assert.equals("PVTSSF_field1", board.columns[1].field_id)
    assert.equals("GRAY", board.columns[1].color)
  end)

  it("parses Draft Issue card correctly", function()
    local board, err = projects._parse_board(make_node())

    assert.is_nil(err)
    local card = board.cards[1]
    assert.equals("PVTI_item1", card.id)
    assert.equals("opt_todo", card.column_id)
    assert.equals("draft", card.content.kind)
    assert.equals("Fix login bug", card.content.title)
    assert.equals("Something is broken", card.content.body)
    assert.equals("alice", card.content.assignees[1])
    assert.is_nil(card.content.number)
    assert.is_nil(card.content.url)
  end)

  it("parses Issue card correctly", function()
    local board, err = projects._parse_board(make_node())

    assert.is_nil(err)
    local card = board.cards[2]
    assert.equals("PVTI_item2", card.id)
    assert.equals("opt_inprogress", card.column_id)
    assert.equals("issue", card.content.kind)
    assert.equals(42, card.content.number)
    assert.equals("OPEN", card.content.state)
    assert.equals("enhancement", card.content.labels[1].name)
  end)

  it("detects PR by url containing /pull/", function()
    local node = make_node({
      items = {
        nodes = {
          {
            id = "PVTI_pr1",
            fieldValues = { nodes = {} },
            content = {
              id = "PR_pr1",
              number = 99,
              title = "Add feature",
              body = "",
              state = "OPEN",
              url = "https://github.com/owner/repo/pull/99",
              assignees = { nodes = {} },
              labels = { nodes = {} },
              createdAt = "2026-06-01T00:00:00Z",
              updatedAt = "2026-06-01T00:00:00Z",
            },
          },
        },
      },
    })

    local board, err = projects._parse_board(node)

    assert.is_nil(err)
    assert.equals("pr", board.cards[1].content.kind)
  end)

  it("returns error when no Status field exists", function()
    local node = make_node({ fields = { nodes = {} } })

    local board, err = projects._parse_board(node)

    assert.is_nil(board)
    assert.is_not_nil(err)
    assert.truthy(err:find("Status"))
  end)

  it("sets status_field_id on board state", function()
    local board, err = projects._parse_board(make_node())

    assert.is_nil(err)
    assert.equals("PVTSSF_field1", board.status_field_id)
  end)

  it("card with no matching fieldValue has nil column_id", function()
    local node = make_node()
    -- fieldValues を空にする
    node.items.nodes[1].fieldValues = { nodes = {} }

    local board, _ = projects._parse_board(node)

    assert.is_nil(board.cards[1].column_id)
  end)
end)
