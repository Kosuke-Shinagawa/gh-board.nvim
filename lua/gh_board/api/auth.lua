local config = require("gh_board.config")

local M = {}

-- gh CLI から同期的にトークンを取得する
---@return string|nil
local function token_from_gh_cli()
  local gh = vim.fn.exepath("gh")
  if gh == "" then
    return nil
  end

  local ok, result = pcall(vim.system, { gh, "auth", "token" }, { text = true })
  if not ok then
    return nil
  end

  local out = result:wait()
  if out.code ~= 0 or vim.trim(out.stdout) == "" then
    return nil
  end

  return vim.trim(out.stdout)
end

-- 優先順位: config.token → gh CLI → $GITHUB_TOKEN
---@return string|nil token
---@return string|nil error_message
function M.resolve()
  if config.options.token and config.options.token ~= "" then
    return config.options.token, nil
  end

  local cli_token = token_from_gh_cli()
  if cli_token then
    return cli_token, nil
  end

  local env_token = os.getenv("GITHUB_TOKEN")
  if env_token and env_token ~= "" then
    return env_token, nil
  end

  local msg = table.concat({
    "gh-board.nvim: GitHub token not found.",
    "Provide one of:",
    "  1. Run `gh auth login`",
    "  2. Set $GITHUB_TOKEN environment variable",
    "  3. Pass token in setup(): require('gh_board').setup({ token = '...' })",
  }, "\n")

  return nil, msg
end

return M
