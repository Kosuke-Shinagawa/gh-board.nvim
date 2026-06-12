local config = require("gh_board.config")
local auth = require("gh_board.api.auth")

describe("api/auth", function()
  before_each(function()
    -- 各テスト前に config をリセット
    config.setup({})
  end)

  describe("resolve()", function()
    it("returns config.token when set", function()
      config.setup({ token = "config_token_abc" })

      local token, err = auth.resolve()

      assert.is_nil(err)
      assert.equals("config_token_abc", token)
    end)

    it("returns token from gh CLI when config.token is nil", function()
      local original_exepath = vim.fn.exepath
      local original_system = vim.system

      vim.fn.exepath = function(cmd)
        if cmd == "gh" then
          return "/usr/bin/gh"
        end
        return original_exepath(cmd)
      end

      -- vim.system は { wait = fn } を返すオブジェクトをモックする
      vim.system = function(cmd, _)
        if type(cmd) == "table" and cmd[2] == "auth" then
          return {
            wait = function()
              return { code = 0, stdout = "gh_cli_token_xyz\n", stderr = "" }
            end,
          }
        end
        return original_system(cmd)
      end

      local token, err = auth.resolve()

      vim.fn.exepath = original_exepath
      vim.system = original_system

      assert.is_nil(err)
      assert.equals("gh_cli_token_xyz", token)
    end)

    it("falls back to GITHUB_TOKEN env var when gh CLI fails", function()
      local original_exepath = vim.fn.exepath
      local original_env_token = vim.env.GITHUB_TOKEN

      vim.fn.exepath = function(cmd)
        if cmd == "gh" then
          return ""
        end
        return original_exepath(cmd)
      end

      vim.env.GITHUB_TOKEN = "env_token_env123"

      local token, err = auth.resolve()

      vim.fn.exepath = original_exepath
      vim.env.GITHUB_TOKEN = original_env_token

      assert.is_nil(err)
      assert.equals("env_token_env123", token)
    end)

    it("returns error message when no token source is available", function()
      local original_exepath = vim.fn.exepath
      local original_env_token = vim.env.GITHUB_TOKEN

      vim.fn.exepath = function(_)
        return ""
      end

      vim.env.GITHUB_TOKEN = nil

      local token, err = auth.resolve()

      vim.fn.exepath = original_exepath
      vim.env.GITHUB_TOKEN = original_env_token

      assert.is_nil(token)
      assert.is_not_nil(err)
      assert.truthy(err:find("gh%-board.nvim"))
    end)
  end)
end)
