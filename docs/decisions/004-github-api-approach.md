# 004: GitHub API は GraphQL v4 のみを使用し REST v3 は除外する

> 日付: 2026-06-13
> ステータス: 採用

## 背景

GitHub には REST API v3 と GraphQL API v4 の 2 種類のインターフェースがある。
GitHub Projects v2 の操作をどちらで実装するかを決定する必要がある。

## 判断

**GraphQL API v4 のみを使用する。REST API v3 は使用しない。**

## 理由

GitHub Projects v2 は GraphQL 専用 API であり、REST では操作できない。

| 操作 | REST v3 | GraphQL v4 |
|------|---------|-----------|
| Projects v2 の一覧取得 | ❌ 未対応 | ✅ `projectsV2` |
| ボードのカード取得 | ❌ 未対応 | ✅ `items` |
| カードのステータス変更 | ❌ 未対応 | ✅ `updateProjectV2ItemFieldValue` |
| Draft Issue の作成 | ❌ 未対応 | ✅ `addProjectV2DraftIssue` |
| Issue 本文の更新 | ✅ `PATCH /repos/{owner}/{repo}/issues/{issue_number}` | ✅ `updateIssue` |

REST で操作できるのは Issue/PR 本文の更新のみ。Projects v2 のコア操作はすべて GraphQL が必要なため、API を統一して GraphQL のみで実装する。

### エンドポイント

```
POST https://api.github.com/graphql
Authorization: Bearer <token>
Content-Type: application/json

{ "query": "...", "variables": { ... } }
```

## 結果・トレードオフ

- **メリット**: API クライアントの実装が `client.lua` の 1 ファイルに統一できる。REST と GraphQL を混在させた場合の認証・エラーハンドリングの二重管理が不要
- **デメリット**: GraphQL の習熟が必要。ただしクエリはすべて `queries.lua` に定数として集約するため、実装時に GraphQL を意識するのは設計フェーズのみ
- **注意点**: `updateIssue` ミューテーションは Issue node ID（`I_xxx`）を要求する。`GetBoard` クエリで Issue の node ID を取得済みであるため問題なし
