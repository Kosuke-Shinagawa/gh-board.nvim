# 003: テストフレームワークに plenary.nvim busted を採用する

> 日付: 2026-06-13
> ステータス: 採用

## 背景

Lua コードのユニットテストを実行するフレームワークが必要。
テスト対象は主に `api/auth.lua`（トークン解決ロジック）・`api/projects.lua`（GraphQL レスポンスのパース）・`state/store.lua`（楽観的更新・ロールバック）の純粋なロジック部分。

## 判断

**plenary.nvim の busted ラッパーを採用する。**

## 理由

| 選択肢 | 評価 |
|--------|------|
| `plenary.nvim busted`（採用） | plenary はすでに必須依存であり、テストフレームワークとしても追加コストゼロ。`describe` / `it` / `before_each` の BDD スタイルで書ける。`nvim --headless` で CI 実行可能 |
| `vusted` | plenary busted の代替で CI フレンドリーだが、別途インストールが必要。plenary busted で十分な機能が揃っているため採用しない |
| `busted`（standalone） | Neovim の API（`vim.*`）にアクセスできないためプラグインテストには不向き |
| テストなし | ロールバックロジックや認証フォールバックは手動確認が困難であり、テストは必須 |

## 結果・トレードオフ

- **メリット**: plenary の依存で完結するため環境構築が簡単。`tests/minimal_init.lua` を用意することで CI でも安定動作
- **デメリット**: Neovim プロセスを起動してテストを実行するため、純粋な Lua テストより起動が遅い
- **テスト対象の絞り方**: UI 層（nui.nvim を使う部分）はテストが困難なため対象外とし、ロジック層（api / state）のみをテストする
