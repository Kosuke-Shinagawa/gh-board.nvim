local client = require("gh_board.api.client")
local queries = require("gh_board.api.queries")
local config = require("gh_board.config")

local M = {}

-- GraphQL レスポンスから BoardState を構築する
---@param node table GetBoard クエリの node フィールド
---@return BoardState|nil, string|nil
local function parse_board(node)
  if not node or node.__typename == nil and node.id == nil then
    return nil, "Project not found"
  end

  -- Status フィールドを探す（SingleSelectField で名前が "Status" のもの）
  local status_field = nil
  for _, field in ipairs(node.fields and node.fields.nodes or {}) do
    if field.id and field.options then
      -- Status フィールドは複数の SingleSelectField があり得るため最初のものを使う
      -- GitHub Projects v2 のデフォルト "Status" フィールドを優先
      if status_field == nil or (field.name and field.name:lower() == "status") then
        status_field = field
      end
    end
  end

  if not status_field then
    return nil, "No Status (SingleSelectField) found in project"
  end

  ---@type GhColumn[]
  local columns = {}
  for _, opt in ipairs(status_field.options or {}) do
    table.insert(columns, {
      id = opt.id,
      field_id = status_field.id,
      name = opt.name,
      color = opt.color or "",
    })
  end

  ---@type GhCard[]
  local cards = {}
  for _, item in ipairs(node.items and node.items.nodes or {}) do
    -- この item の Status フィールドの optionId を探す
    local column_id = nil
    for _, fv in ipairs(item.fieldValues and item.fieldValues.nodes or {}) do
      if fv.optionId and fv.field and fv.field.id == status_field.id then
        column_id = fv.optionId
        break
      end
    end

    local content = item.content
    if not content then
      goto continue
    end

    ---@type GhCardContent
    local parsed_content
    if content.number then
      -- PullRequest は url に /pull/ が含まれる（__typename は fragment 展開で返らないため URL で判定）
      local kind
      if content.url and content.url:find("/pull/") then
        kind = "pr"
      else
        kind = "issue"
      end

      local assignees = {}
      for _, a in ipairs(content.assignees and content.assignees.nodes or {}) do
        table.insert(assignees, a.login)
      end

      local labels = {}
      for _, l in ipairs(content.labels and content.labels.nodes or {}) do
        table.insert(labels, { name = l.name, color = l.color })
      end

      parsed_content = {
        id = content.id,
        kind = kind,
        number = content.number,
        title = content.title or "",
        body = content.body or "",
        state = content.state,
        url = content.url,
        assignees = assignees,
        labels = labels,
        created_at = content.createdAt or "",
        updated_at = content.updatedAt or "",
      }
    else
      -- DraftIssue
      local assignees = {}
      for _, a in ipairs(content.assignees and content.assignees.nodes or {}) do
        table.insert(assignees, a.login)
      end

      parsed_content = {
        id = content.id,
        kind = "draft",
        number = nil,
        title = content.title or "",
        body = content.body or "",
        state = nil,
        url = nil,
        assignees = assignees,
        labels = {},
        created_at = content.createdAt or "",
        updated_at = content.updatedAt or "",
      }
    end

    table.insert(cards, {
      id = item.id,
      column_id = column_id,
      content = parsed_content,
    })

    ::continue::
  end

  ---@type GhProject
  local project = {
    id = node.id,
    number = 0,
    title = node.title or "",
    url = "",
    closed = false,
  }

  return {
    project = project,
    columns = columns,
    cards = cards,
    status_field_id = status_field.id,
  },
    nil
end

-- ユーザーのプロジェクト一覧を取得する
---@param owner string GitHub ユーザー名
---@param callback fun(err: ApiError|nil, projects: GhProject[]|nil)
function M.list_projects(owner, callback)
  client.request(queries.LIST_PROJECTS, {
    login = owner,
    first = 20,
  }, function(err, data)
    if err then
      callback(err, nil)
      return
    end

    local nodes = data and data.user and data.user.projectsV2 and data.user.projectsV2.nodes or {}

    ---@type GhProject[]
    local projects = {}
    for _, n in ipairs(nodes) do
      if not n.closed then
        table.insert(projects, {
          id = n.id,
          number = n.number,
          title = n.title,
          url = n.url,
          closed = n.closed or false,
        })
      end
    end

    callback(nil, projects)
  end)
end

-- プロジェクトのボード（カラム + カード）を取得する
---@param project_id string GraphQL node ID
---@param callback fun(err: ApiError|nil, state: BoardState|nil)
function M.get_board(project_id, callback)
  client.request(queries.GET_BOARD, {
    projectId = project_id,
    first = config.options.per_page,
  }, function(err, data)
    if err then
      callback(err, nil)
      return
    end

    local node = data and data.node
    local board, parse_err = parse_board(node)
    if parse_err then
      callback({ message = parse_err, type = "unknown" }, nil)
      return
    end

    callback(nil, board)
  end)
end

-- テスト用にパーサーを公開する
M._parse_board = parse_board

-- Draft Issue カードを新規作成する
---@param project_id string
---@param title string
---@param body string|nil
---@param callback fun(err: ApiError|nil, item_id: string|nil)
function M.create_card(project_id, title, body, callback)
  client.request(queries.CREATE_CARD, {
    projectId = project_id,
    title = title,
    body = body,
  }, function(err, data)
    if err then
      callback(err, nil)
      return
    end

    local item_id = data
      and data.addProjectV2DraftIssue
      and data.addProjectV2DraftIssue.projectItem
      and data.addProjectV2DraftIssue.projectItem.id

    callback(nil, item_id)
  end)
end

-- カードのタイトル・本文を更新する
-- Draft Issue は updateProjectV2DraftIssue、Issue/PR は updateIssue を使う
---@param card GhCard
---@param title string
---@param body string|nil
---@param callback fun(err: ApiError|nil)
function M.update_card(card, title, body, callback)
  local query, variables

  if card.content.kind == "draft" then
    query = queries.UPDATE_DRAFT_ISSUE
    variables = {
      draftIssueId = card.content.id,
      title = title,
      body = body,
    }
  else
    query = queries.UPDATE_ISSUE
    variables = {
      issueId = card.content.id,
      title = title,
      body = body,
    }
  end

  client.request(query, variables, function(err, _)
    callback(err)
  end)
end

-- カードのステータス（カラム）を変更する
---@param project_id string
---@param item_id string  ProjectItem node ID
---@param field_id string Status フィールドの node ID
---@param option_id string 移動先カラムの option ID
---@param callback fun(err: ApiError|nil)
function M.move_card(project_id, item_id, field_id, option_id, callback)
  client.request(queries.MOVE_CARD, {
    projectId = project_id,
    itemId = item_id,
    fieldId = field_id,
    optionId = option_id,
  }, function(err, _)
    callback(err)
  end)
end

-- カードをプロジェクトから削除する
---@param project_id string
---@param item_id string
---@param callback fun(err: ApiError|nil)
function M.delete_card(project_id, item_id, callback)
  client.request(queries.DELETE_CARD, {
    projectId = project_id,
    itemId = item_id,
  }, function(err, _)
    callback(err)
  end)
end

-- Issue を CLOSED 状態にする（Draft Issue と PR には使えない）
---@param issue_id string  Issue の node ID（content.id）
---@param callback fun(err: ApiError|nil)
function M.close_issue(issue_id, callback)
  client.request(queries.CLOSE_ISSUE, { issueId = issue_id }, function(err, _)
    callback(err)
  end)
end

-- Issue を OPEN 状態に戻す
---@param issue_id string
---@param callback fun(err: ApiError|nil)
function M.reopen_issue(issue_id, callback)
  client.request(queries.REOPEN_ISSUE, { issueId = issue_id }, function(err, _)
    callback(err)
  end)
end

-- オーナーのリポジトリ一覧を取得する（Draft → Issue 変換先の選択に使用）
---@param owner string
---@param callback fun(err: ApiError|nil, repos: {id: string, name: string, full_name: string}[]|nil)
function M.list_repos(owner, callback)
  client.request(queries.LIST_REPOS, {
    login = owner,
    first = 50,
  }, function(err, data)
    if err then
      callback(err, nil)
      return
    end
    local nodes = data and data.user and data.user.repositories and data.user.repositories.nodes
      or {}
    local repos = {}
    for _, n in ipairs(nodes) do
      table.insert(repos, { id = n.id, name = n.name, full_name = n.nameWithOwner })
    end
    callback(nil, repos)
  end)
end

-- Draft Issue を実 Issue に変換する
---@param item_id string  ProjectItem node ID
---@param repository_id string  変換先リポジトリの node ID
---@param callback fun(err: ApiError|nil)
function M.convert_draft_to_issue(item_id, repository_id, callback)
  client.request(queries.CONVERT_DRAFT_TO_ISSUE, {
    itemId = item_id,
    repositoryId = repository_id,
  }, function(err, _)
    callback(err)
  end)
end

return M
