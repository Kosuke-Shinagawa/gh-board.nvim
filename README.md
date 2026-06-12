# gh-board.nvim

GitHub Projects v2 Kanban board inside Neovim.

Browse, create, edit, and move cards — no browser required.

## Features

- Kanban board rendered in a floating window
- Card detail view (body, assignees, labels, linked Issue / PR)
- Create / edit / delete cards
- Move cards between columns (status change) with optimistic UI
- Bidirectional sync with GitHub Projects v2 via GraphQL API
- Auth via `gh` CLI, `$GITHUB_TOKEN`, or config option

## Requirements

| Dependency | Notes |
|-----------|-------|
| Neovim >= 0.9.0 | |
| [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) | HTTP + test runner |
| [nui.nvim](https://github.com/MunifTanjim/nui.nvim) | Float windows + forms |
| gh CLI *(optional)* | Easiest auth method |

## Installation

**lazy.nvim**

```lua
{
  "Kosuke-Shinagawa/gh-board.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
  },
  config = function()
    require("gh_board").setup({
      default_owner = "your-github-username",
    })
  end,
}
```

**packer.nvim**

```lua
use {
  "Kosuke-Shinagawa/gh-board.nvim",
  requires = { "nvim-lua/plenary.nvim", "MunifTanjim/nui.nvim" },
  config = function()
    require("gh_board").setup({})
  end,
}
```

## Authentication

The plugin resolves a token in this order:

1. `setup({ token = "ghp_..." })` — explicit config
2. `gh auth token` — reads from the `gh` CLI session *(recommended)*
3. `$GITHUB_TOKEN` environment variable

To authenticate with the gh CLI:

```bash
gh auth login --scopes project
```

## Usage

```
:GhBoard                    " auto-detect owner, prompt if multiple projects
:GhBoard myusername         " list projects for user
:GhBoard myusername 3       " open project #3 directly
```

## Keymaps

### Kanban board

| Key | Action |
|-----|--------|
| `j` / `k` | Move cursor down / up |
| `h` / `l` | Move to previous / next column |
| `<Enter>` | Open card detail |
| `n` | New card |
| `m` | Move card (change status) |
| `d` | Delete card |
| `r` | Refresh from GitHub |
| `q` / `<Esc>` | Close |

### Card detail

| Key | Action |
|-----|--------|
| `e` | Edit card |
| `d` | Delete card |
| `q` / `<Esc>` | Close |

### Card form

| Key | Action |
|-----|--------|
| `<Tab>` | Switch between Title and Body fields |
| `<Enter>` | Confirm and submit |
| `<Esc>` | Cancel |

## Configuration

```lua
require("gh_board").setup({
  token          = nil,          -- GitHub token (optional)
  default_owner  = nil,          -- default GitHub user / org
  default_project = nil,         -- default project number
  per_page       = 50,           -- cards to fetch per load (max 100)
  win_width      = nil,          -- float window width (default: 90% of screen)
  win_height     = nil,          -- float window height (default: 80% of screen)
  keymaps = {
    open_detail = "<CR>",
    new_card    = "n",
    move_card   = "m",
    delete_card = "d",
    edit_card   = "e",
    refresh     = "r",
    close       = "q",
  },
})
```

See `:help gh-board` for the full reference.

## Development

```bash
# Install git hooks (runs stylua on staged Lua files)
sh scripts/setup-hooks.sh

# Run tests
nvim --headless \
  -c "PlenaryBustedDirectory tests/spec/ { minimal_init = 'tests/minimal_init.lua', sequential = true }" \
  -c "qa"

# Format
stylua lua/ tests/

# Lint
luacheck lua/ tests/
```

## License

MIT
