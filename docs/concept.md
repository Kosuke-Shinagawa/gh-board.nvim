# コンセプト: gh-board.nvim

> 作成日: 2026-06-13

## 目的

Neovim のフロートウィンドウで GitHub Projects v2 の Kanban ボードを表示・操作できる Lua プラグインを提供する。

エンジニアがコーディング中に「GitHub Projects を確認・更新したい」と思ったとき、ブラウザを開かずに nvim 内で完結させることで、コンテキストスイッチを排除する。

## 解決する課題

GitHub Projects でタスク管理をしながら nvim でコーディングしている場合、以下の往復が繰り返し発生する。

```
nvim でコーディング中
  → ブラウザで GitHub Projects を開く
  → カードのステータスを変更・内容を確認
  → nvim に戻る
  → ...（繰り返し）
```

このブラウザ切り替えコストが集中の断絶を生む。gh-board.nvim は Kanban の閲覧・編集操作をすべて nvim 内で完結させる。

## ターゲットユーザー

- Neovim をメインエディタとして日常的に使用しているエンジニア
- GitHub Projects v2 でタスク・issue 管理を行っているエンジニア
- ターミナル完結のワークフローを好む人

## 機能スコープ

### v0.1.0（必須）

| 機能 | 概要 |
|------|------|
| Kanban ボード表示 | `:GhBoard` でフロートウィンドウに Kanban を表示 |
| カード詳細表示 | カード選択でタイトル・本文・担当者・ラベル等を表示 |
| カードのステータス変更 | カードを別カラムへ移動し GitHub に同期 |
| カードの新規作成 | タイトル・本文を入力して Draft Issue として追加 |
| カードの編集 | 既存カードのタイトル・本文を編集して同期 |
| カードの削除 | カードをプロジェクトから削除 |
| 認証 | gh CLI / GITHUB_TOKEN / setup option のフォールバック |

### スコープ外（v0.1.0）

- GitHub Projects v1（クラシック）のサポート
- Issue / PR 自体の作成・マージ
- リアルタイムポーリング（手動リフレッシュ `r` で対応）
- luarocks への公開

### Nice to Have（v0.2.0 以降）

- コメントの投稿・編集
- Issue / PR リンク表示
- 複数プロジェクト切り替え
- Telescope 統合（fuzzy 検索）
- ローカルキャッシュ（起動高速化）
- Org プロジェクトサポート

## 成功指標

1. ブラウザを一度も開かずに Kanban の読み書き操作が nvim 内で完結できる
2. API 呼び出し中も nvim の UI がブロックされない（非同期）
3. Kanban 初期表示が API レスポンス受信後 200ms 以内に描画完了する
4. lazy.nvim で 5 行以内の設定で動作する

## 依存関係

| 依存 | 種別 | 理由 |
|------|------|------|
| [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) | 必須 | 非同期 HTTP（curl ラッパー）・テストフレームワーク |
| [nui.nvim](https://github.com/MunifTanjim/nui.nvim) | 必須 | フロートウィンドウ・ポップアップ・入力フォーム |
| [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) | 任意 | fuzzy 検索拡張（Nice to Have） |
| gh CLI | 任意 | トークン取得（GITHUB_TOKEN 環境変数でも代替可） |
