local auth = require("gh_board.api.auth")

local M = {}

local GITHUB_GRAPHQL_URL = "https://api.github.com/graphql"

---@class ApiError
---@field message string
---@field type "auth"|"network"|"graphql"|"unknown"

-- GraphQL レスポンスのエラーを正規化する
---@param body string
---@return string|nil
local function extract_graphql_error(body)
  local ok, decoded = pcall(vim.fn.json_decode, body)
  if not ok or type(decoded) ~= "table" then
    return "Invalid JSON response"
  end

  if decoded.errors and #decoded.errors > 0 then
    local messages = {}
    for _, err in ipairs(decoded.errors) do
      table.insert(messages, err.message or "Unknown GraphQL error")
    end
    return table.concat(messages, "; ")
  end

  return nil
end

-- GraphQL リクエストを非同期で実行する
---@param query string GraphQL クエリ文字列
---@param variables table GraphQL 変数
---@param callback fun(err: ApiError|nil, data: table|nil)
function M.request(query, variables, callback)
  local token, auth_err = auth.resolve()
  if not token then
    callback({ message = auth_err, type = "auth" }, nil)
    return
  end

  local curl = require("plenary.curl")

  local body = vim.fn.json_encode({
    query = query,
    variables = variables,
  })

  curl.post(GITHUB_GRAPHQL_URL, {
    headers = {
      ["Authorization"] = "Bearer " .. token,
      ["Content-Type"] = "application/json",
    },
    body = body,
    callback = vim.schedule_wrap(function(response)
      if response.status ~= 200 then
        callback({
          message = string.format("HTTP %d: %s", response.status, response.body or ""),
          type = "network",
        }, nil)
        return
      end

      local graphql_err = extract_graphql_error(response.body)
      if graphql_err then
        callback({ message = graphql_err, type = "graphql" }, nil)
        return
      end

      local ok, decoded = pcall(vim.fn.json_decode, response.body)
      if not ok or type(decoded) ~= "table" then
        callback({ message = "Failed to parse response", type = "unknown" }, nil)
        return
      end

      callback(nil, decoded.data)
    end),
  })
end

return M
