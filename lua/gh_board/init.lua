local M = {}

---@param opts GhBoardConfig|nil
function M.setup(opts)
  local config = require("gh_board.config")
  config.setup(opts)

  require("gh_board.ui.components.column").define_highlights()

  -- :GhBoard [owner [project_number]]
  vim.api.nvim_create_user_command("GhBoard", function(cmd_opts)
    M.open(cmd_opts.fargs)
  end, {
    nargs = "*",
    desc = "Open GitHub Projects v2 Kanban board",
  })
end

-- owner と project_number を解決してボードを開く
-- fargs: {} | { owner } | { owner, number }
---@param fargs string[]
function M.open(fargs)
  local config = require("gh_board.config")
  local auth = require("gh_board.api.auth")

  -- 認証チェック
  local token, auth_err = auth.resolve()
  if not token then
    vim.notify(auth_err, vim.log.levels.ERROR)
    return
  end

  local owner = fargs[1] or config.options.default_owner
  local project_number = tonumber(fargs[2] or config.options.default_project)

  if not owner then
    -- オーナー未指定なら GitHub ログインユーザーを使う
    local gh = vim.fn.exepath("gh")
    if gh ~= "" then
      local login = vim.trim(vim.fn.system(gh .. " api user --jq .login 2>/dev/null"))
      if vim.v.shell_error == 0 and login ~= "" then
        owner = login
      end
    end
  end

  if not owner then
    vim.notify(
      "gh-board: owner not specified.\n"
        .. "Usage: :GhBoard [owner] [project_number]\n"
        .. "Or set default_owner in setup()",
      vim.log.levels.ERROR
    )
    return
  end

  if not project_number then
    -- プロジェクト番号未指定ならプロジェクト一覧から選択
    local projects_api = require("gh_board.api.projects")
    projects_api.list_projects(owner, function(err, project_list)
      if err then
        vim.notify("gh-board: " .. err.message, vim.log.levels.ERROR)
        return
      end

      if not project_list or #project_list == 0 then
        vim.notify("gh-board: No projects found for " .. owner, vim.log.levels.WARN)
        return
      end

      if #project_list == 1 then
        require("gh_board.ui.board").open(project_list[1].id)
        return
      end

      local choices = vim.tbl_map(function(p)
        return string.format("#%d %s", p.number, p.title)
      end, project_list)

      vim.ui.select(choices, { prompt = "Select project:" }, function(_, idx)
        if idx then
          require("gh_board.ui.board").open(project_list[idx].id)
        end
      end)
    end)
  else
    -- プロジェクト番号指定あり → 一覧から該当 ID を探す
    local projects_api = require("gh_board.api.projects")
    projects_api.list_projects(owner, function(err, project_list)
      if err then
        vim.notify("gh-board: " .. err.message, vim.log.levels.ERROR)
        return
      end

      for _, p in ipairs(project_list or {}) do
        if p.number == project_number then
          require("gh_board.ui.board").open(p.id)
          return
        end
      end

      vim.notify(
        string.format("gh-board: Project #%d not found for %s", project_number, owner),
        vim.log.levels.ERROR
      )
    end)
  end
end

return M
