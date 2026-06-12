# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/Kosuke-Shinagawa/gh-board.nvim/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Kosuke-Shinagawa/gh-board.nvim/releases/tag/v0.1.0
