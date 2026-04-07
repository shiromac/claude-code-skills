---
name: "Team Review"
description: "Create a review team with multiple specialist reviewers who can consult each other. Covers architecture, security, spec conformance, doc consistency, and more."
category: Quality
tags: [review, quality, team, code-review, doc-review]
maxTurns: 50
context: fork
---

# Team Review

複数の専門レビュアーによるチームレビュー。各レビュアーが独立にレビューしつつ、互いに相談できる。

## Step 1: 対象の把握と説明文の作成

レビュー対象を特定し、内容を理解して説明文を作成する。

### 対象の特定

- 引数なし → `git diff HEAD` (未コミット変更)。差分がなければ `git diff HEAD~1` (直前のコミット)
- ファイル/ディレクトリ指定 → そのファイルを読む
- OpenSpec change 名 → `openspec/changes/<name>/` 配下のドキュメント一式を読む

### 説明文の構造

```
## レビュー対象
（ソースコード / ドキュメント / 両方）

## 変更の概要
（何を、なぜ変更したのか。対象ファイルの一覧と各ファイルの役割）

## 設計上の意図・判断
（あれば。なぜこのアプローチを選んだか、トレードオフなど）

## 気になる点（もしあれば）
（自分で気づいた懸念点やTODO）
```

## Step 2: レビュアーの選出

対象の内容を踏まえ、以下のプールからレビュアーを選出する。

### コアメンバー（常に参加）

| 名前 | 専門領域 |
|------|---------|
| **architect** | 責務分離、依存方向、レイヤー境界、SOLID原則、クラス/モジュール設計 |
| **security** | injection (SQL, command, XSS)、secrets管理、認証/認可、unsafe deserialization、path traversal |
| **spec-conformance** | ユースケースとの乖離、要件カバレッジ、仕様で定義された振る舞いとの不整合 |
| **doc-consistency** | 既存ドキュメント(設計書、仕様書、README)との矛盾、用語の不統一、ドキュメント間の整合性 |

### 追加メンバー（対象に応じて選出）

| 名前 | 専門領域 | 選出基準 |
|------|---------|---------|
| **concurrency** | スレッドセーフ、race condition、deadlock、async/await、lock戦略 | async, lock, thread, Task, ConcurrentXxx, Mutex, Semaphore 等が含まれる |
| **performance** | 計算量、アロケーション、ホットパス、キャッシュ、LINQ の過剰使用 | ループ処理、大量データ操作、頻繁に呼ばれるパスが含まれる |
| **test-quality** | テストカバレッジ、アサーション妥当性、エッジケース、テストの脆さ | テストコードが対象に含まれる、または対象コードのテストが存在する |
| **error-handling** | 境界値、例外伝播、リカバリ、障害モード、エラーメッセージの品質 | try/catch、Result型、エラー境界が含まれる |
| **readability** | 命名、複雑度(認知的/循環的)、パターン一貫性、コードの意図の明確さ | 大規模な変更、新規ファイル追加、リファクタリング |
| **ux** | ユーザー体験、エラーメッセージ、操作フロー、フィードバックの適切さ | UI コード、ユーザー向けメッセージ、UX関連仕様 |

### 選出ルール

1. **コア4人は常に参加**する
2. 対象のコードやドキュメントを読み、選出基準に該当する追加メンバーを選ぶ
3. 迷ったら**入れる**（網羅性が重要）
4. 全員入れても構わない（最大10人）

## Step 3: チーム作成とレビュー開始

### 3-1. TeamCreate でチームを作成する

```
team_name: "review-{timestamp}"
description: "Team review for: {対象の簡潔な説明}"
```

### 3-2. 全メンバーを Agent で spawn する

各メンバーを Agent (subagent_type: "general-purpose") で spawn する。**必ず `team_name` と `name` パラメータを指定**し、チームに所属させる。

- `team_name`: Step 3-1 で作成したチーム名
- `name`: Step 2 のメンバー名 (例: "architect", "security", ...)

各メンバーに以下のプロンプトを渡す。`{role_name}`, `{expertise}`, `{review_description}`, `{target_info}`, `{teammate_names}` を埋め込む。

```
You are a reviewer on a team review. Your role is **{role_name}** — your expertise is {expertise}.

## Your review target

{review_description}

{target_info}

## Your process

1. **Read the actual code/documents yourself.** Do not trust the description above blindly — verify by reading the source files.
2. **Focus on your area of expertise.** You are {role_name}. Review deeply from your perspective. Do not try to cover everything — your teammates cover other perspectives.
3. **Consult teammates when needed.** If you find something that crosses into another reviewer's domain, or want a second opinion, send them a message using SendMessage with their name. Your teammates are: {teammate_names}.
4. **Write your review report** when done.

## Output format

### {role_name} Review

#### Findings

For each issue found:
- **File:Line** (or document section) — description of the problem
- **Severity**: critical / warning / nit
- **Suggestion**: concrete fix or alternative

If no issues found, say "No issues found from {role_name} perspective."

#### Observations (optional)
Anything noteworthy — good patterns, potential improvements, or context for other reviewers.

Send your completed review report to the team lead when done.
```

### 3-3. タスクを作成して割り当てる

各メンバーに TaskCreate でレビュータスクを作成し、TaskUpdate で owner を割り当てる。

タスク件名: `"{role_name} review: {対象の要約}"`

## Step 4: 放置して待つ

メンバーが独立にレビューし、必要に応じて互いに相談する。親は介入しない。

各メンバーは完了時に SendMessage でレビュー報告を送信する。全メンバーからの報告を受信したら Step 5 へ進む。

## Step 5: 統合レビューレポートの作成

全メンバーの報告が揃ったら:

### 5-1. 各メンバーの報告をそのまま表示する

各レビュアーの報告を省略・フィルタせずそのまま表示する。

### 5-2. 妥当性検証

self-review と同じプロセスで、指摘された各 Issue を親エージェント自身が検証する。

指摘された各 Issue について:

1. **該当コードを再読する** — 指摘されたファイル・行を実際に読み、指摘が正しいか確認する
2. **文脈を考慮する** — 呼び出し元、既存パターン、フレームワークの保証などを踏まえ、指摘が実際の問題かどうか判断する
3. **判定を下す**:
   - 妥当 — 実際の問題。対処すべき
   - 誤検出 — コード・文脈を正しく読めば問題ではない。理由を1文で説明する
   - 部分的に妥当 — 指摘の方向性は正しいが、深刻度や内容に修正が必要

### 5-3. 統合テーブル

重複を排除し、全指摘を1つのテーブルにまとめる。

```
## 統合レビュー結果

| # | レビュアー | 重要度 | 指摘箇所 | 指摘内容 | 妥当性 | 理由 |
|---|----------|--------|----------|----------|--------|------|
| 1 | security | critical | `file.cs:42` | SQL injection | 妥当 | — |
| 2 | architect | warning | `foo.cs:10` | 循環依存 | 妥当 | — |
| 3 | concurrency | warning | `bar.cs:99` | lock不足 | 誤検出 | 呼び出し元で同期済み |

**対処すべき指摘**: N件 (妥当 + 部分的に妥当)
```

- **critical な妥当指摘**がある場合は最優先で修正を提案する
- 対処すべき指摘が残っていれば修正を手伝うか聞く
- すべて誤検出だった場合は「指摘はすべて誤検出でした — LGTM」と報告する

## Step 6: レビュー合格マーカーの書き込み

Step 5 の結果、**対処すべき指摘(妥当 または 部分的に妥当)が 0 件**の場合のみ、以下の手順でマーカーを書き込む。1 件でも残っていれば書き込まない。

1. 現在の tree hash を取得する:
   ```bash
   git add -A && git write-tree
   ```

2. マーカーファイルを `.claude/state/` に書き込む。ファイル名は `review-<task_id>.json`。
   - `task_id` は現在の task の ID。task がない場合は `"default"` を使う。
   - `task_subject` は task の subject。task がない場合は `$ARGUMENTS` または `"manual review"` を使う。

   マーカー JSON の形式:
   ```json
   {
     "task_id": "<task_id>",
     "task_subject": "<task_subject>",
     "tree_hash": "<git write-tree の出力>",
     "reviewed_at": "<ISO 8601 タイムスタンプ>",
     "ok": true
   }
   ```

3. Bash tool で書き込む:
   ```bash
   python -c "
   import json, datetime
   marker = {
       'task_id': '<task_id>',
       'task_subject': '<task_subject>',
       'tree_hash': '<tree_hash>',
       'reviewed_at': datetime.datetime.now().isoformat(),
       'ok': True
   }
   with open('.claude/state/review-<task_id>.json', 'w') as f:
       json.dump(marker, f, indent=2)
   print('Review marker written: .claude/state/review-<task_id>.json')
   "
   ```

4. ユーザーに「レビュー合格マーカーを保存しました」と報告する。

## Step 7: チームの解散

全レビューが完了したら、全メンバーに `shutdown_request` を送信してチームを解散する。
