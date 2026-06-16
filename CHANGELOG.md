# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-06-14

### Added

- Search panel: filter cards by title or issue number in real time (`/` key)
- Preview panel: show card detail alongside the board without opening a popup
- Help panel: keybinding hints displayed below the preview panel
- Draft Issue → real Issue conversion with repository selection (`p` key)
- GitHub Issue open/close toggle (`C` key) — supported in both board and card detail views
- New card creation via a single-line float window (title only, okuban.nvim style)
- Card detail popup: `C` keymap also available for quick status change

### Changed

- New card creation no longer opens a two-pane form; a minimal float window is shown instead
- Popup windows no longer use nui `border.text` — native Neovim title/footer is used, eliminating a separate border window and fixing transparent background rendering

### Fixed

- Floating window background transparency: `winhighlight` now correctly overrides `FloatBorder` background via a synthesised `GhBoardBorder` highlight group
- `q` key on the board no longer closes the board when a card detail popup was just dismissed (key-bleed prevention via `_just_closed` flag)
- Returning to normal mode after card creation — `startinsert` is now balanced with `stopinsert` before unmounting the float
- Board not refreshing after card creation — optimistic update via `store.apply_create` is applied immediately; server sync follows after 1.5 s
- Multibyte card title trim: `string.sub` (byte-based) replaced with `vim.fn.strcharpart` + `vim.fn.strdisplaywidth` (display-width-aware); fixes `<e3>` / `<e6>` garbage at end of Japanese titles
- Column header trim: same byte-cutting bug fixed with display-width-aware loop

## [0.1.2] - 2026-06-13

### Fixed

- Edit form now correctly pre-fills title and body with the card's existing content — nui `Input`'s `default_value` (feedkeys-based) was replaced with `nvim_buf_set_lines` via `vim.schedule` to avoid race conditions and non-ASCII encoding issues

## [0.1.1] - 2026-06-13

### Fixed

- Cursor highlight byte offset miscalculation when moving left/right between columns — `│` (U+2502) is 3 bytes in UTF-8, causing visible drift for columns 2 and beyond

## [0.1.0] - 2026-06-13

### Added

- Kanban board view in a Neovim floating window (`:GhBoard`)
- Card detail popup with title, body, assignees, labels, linked Issue/PR info
- Card status change (move between columns) with optimistic UI update
- Card creation as GitHub Projects v2 Draft Issue
- Card editing (title and body) for both Draft Issues and linked Issues/PRs
- Card deletion with confirmation dialog
- Manual board refresh (`r` key)
- Authentication via gh CLI → `$GITHUB_TOKEN` → `setup({ token })` fallback chain
- Project selection prompt when multiple projects exist for an owner
- Configurable keymaps via `setup()` options
- Configurable window dimensions
- 16 semantic highlight groups for columns and cards
- Vimdoc help (`:help gh-board`)
- GitHub Actions CI (stylua + luacheck + plenary busted)
- GitHub Actions release workflow (auto GitHub Release on `v*` tag push)
- Unit tests for auth resolution, GraphQL response parsing, and store logic

[Unreleased]: https://github.com/Kosuke-Shinagawa/gh-board.nvim/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/Kosuke-Shinagawa/gh-board.nvim/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/Kosuke-Shinagawa/gh-board.nvim/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Kosuke-Shinagawa/gh-board.nvim/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Kosuke-Shinagawa/gh-board.nvim/releases/tag/v0.1.0
