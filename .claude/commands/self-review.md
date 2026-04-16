---
name: "Self Review"
description: "Spawn a sub-agent to review code changes or design documents (proposals, specs, tasks) and provide feedback"
category: Quality
tags: [review, quality, code-review]
maxTurns: 50
context: fork
---

# Self Review

親エージェントが変更内容を把握・説明し、その説明付きでサブエージェントにレビューを依頼する。サブエージェントは説明を鵜呑みにせず、自らコードを読んで検証する。

## Step 1: 親エージェントが説明文を作成する

この会話のコンテキスト（直前に行った実装作業、読んだファイル、設計判断など）をもとに、変更内容の説明文を**自分の言葉で**書く。git コマンドで差分を取得する必要はない — 自分がやったことを自分で説明する。

以下の構造で書く:

```
## 変更の概要
（何を、なぜ変更したのか。1-3文で）

## 変更ファイル一覧
- `path/to/file.cs` — 何をした（例: メソッド追加、条件分岐修正、etc.）
- `path/to/other.cs` — 何をした

## 設計上の意図・判断
（あれば。なぜこのアプローチを選んだか、トレードオフなど）

## 気になる点（もしあれば）
（自分で気づいた懸念点やTODO）
```

## Step 2: サブエージェントにレビューを依頼する

Agent tool (subagent_type: "general-purpose") を起動し、以下のプロンプトを渡す。
`{親エージェントの説明文}` には Step 1 で作成した説明を埋め込み、`$ARGUMENTS` はユーザーの引数に置換する。

```
You are a code reviewer. You have received a description of the changes from the author (below). Your job is to **verify the author's claims by reading the actual code yourself**, then provide an independent review.

Do NOT trust the description blindly — it may be incomplete, inaccurate, or miss important issues.

## Author's description of the changes

{親エージェントの説明文}

## Your review process

1. **Verify the description**: Run `git diff` / `git diff --cached` (or `git diff HEAD~1` if no uncommitted changes) to see the actual diff. Compare it against the author's description. Note any discrepancies.
2. **Read the source files**: For each changed file, read the relevant sections and surrounding context. Look at imports, callers, tests, and related files as needed.
3. **Form your own understanding**: Based on your reading, independently assess what the change does and whether it's correct.
4. **Review against checklist**:
   - **Bugs & Logic errors** — Off-by-one, null/undefined access, race conditions, missing error handling at system boundaries
   - **Security** — Injection (SQL, command, XSS), hardcoded secrets, unsafe deserialization, path traversal
   - **Performance** — Unnecessary allocations in hot paths, O(n^2) where O(n) is possible, missing indexes for new queries
   - **Naming & Clarity** — Do variable/function names accurately describe their purpose? Would a new reader understand the intent?
   - **Edge cases** — Empty collections, negative numbers, Unicode, concurrent access, boundary values
   - **API & Contract** — Breaking changes to public interfaces, missing validation at entry points, inconsistent error shapes
   - **Test coverage** — Are new code paths tested? Are edge cases covered? Are tests actually asserting the right thing?
   - **Consistency** — Does the change follow existing patterns in the codebase, or introduce a new pattern without justification?

## Output format

### Summary
One-paragraph overall assessment: is this change safe to ship?

### Description accuracy
Did the author's description accurately reflect the changes? Note any gaps or inaccuracies.

### Issues found
For each issue:
- **File:Line** — description of the problem
- **Severity**: critical / warning / nit
- **Suggestion**: concrete fix or alternative

If no issues are found, say "No issues found — LGTM."

### Positive observations (optional)
Briefly note anything particularly well done.

ADDITIONAL FOCUS: $ARGUMENTS
```

## Step 3: 結果の表示

サブエージェントの出力をそのままユーザーに表示する（要約・フィルタしない）。

## Step 4: 指摘内容の妥当性検証

サブエージェントの指摘を**親エージェント自身が検証**する。レビューアも間違えることがある — 誤検出(false positive)を除外し、本当に対処すべき指摘だけを残す。

### 検証プロセス

指摘された各 Issue について、以下を確認する:

1. **該当コードを再読する** — 指摘されたファイル・行を実際に読み、指摘が正しいか確認する
2. **文脈を考慮する** — 呼び出し元、既存パターン、フレームワークの保証などを踏まえ、指摘が実際の問題かどうか判断する
3. **判定を下す** — 各指摘に対して以下のいずれかを付与する:
   - ✅ **妥当** — 実際の問題。対処すべき
   - ❌ **誤検出** — コード・文脈を正しく読めば問題ではない。理由を1文で説明する
   - ⚠️ **部分的に妥当** — 指摘の方向性は正しいが、深刻度や内容に修正が必要

### 出力

重要度・指摘内容・妥当性を1つのテーブルにまとめて表示する。

```
## 妥当性検証結果

| # | 重要度 | 指摘箇所 | 指摘内容 | 妥当性 | 理由 |
|---|--------|----------|----------|--------|------|
| 1 | critical | `file.cs:42` | null参照の可能性 | ✅ 妥当 | — |
| 2 | warning | `foo.cs:10` | 未使用変数 | ❌ 誤検出 | 後続の処理で参照されている |
| 3 | nit | `bar.cs:99` | 命名が不明瞭 | ⚠️ 部分的に妥当 | 名前は改善余地あるが既存パターンに合わせている |

**対処すべき指摘**: N件 (✅ + ⚠️)
```

- **critical な ✅ 妥当** がある場合は最優先で修正を提案する
- 対処すべき指摘(✅ または ⚠️)が残っていれば修正を手伝うか聞く
- すべて誤検出だった場合は「指摘はすべて誤検出でした — LGTM」と報告する

## Step 5: レビュー合格マーカーの書き込み

Step 4 の結果、**対処すべき指摘(✅ 妥当 または ⚠️ 部分的に妥当)が 0 件**の場合のみ、以下の手順でマーカーを書き込む。1 件でも残っていれば書き込まない。

### 書き込み先の判定

レビュー対象に応じて書き込み先を決定する:

- **OpenSpec ドキュメントのレビュー**: 対象ドキュメント自体のフロントマターに書き込む
- **OpenSpec タスク実装のコードレビュー**: `openspec/changes/<change_name>/tasks.md` のフロントマターに書き込む
- **上記以外（ad-hoc コードレビュー）**: マーカー書き込みをスキップする

### OpenSpec ドキュメントのレビューの場合

1. マーカーフィールドを除去した内容でハッシュを計算する:
   ```bash
   sed '/^reviewed_at:/d; /^reviewed_hash:/d' <document_path> | git hash-object --stdin
   ```

2. Edit tool でフロントマターに `reviewed_at` と `reviewed_hash` を追加（既存なら上書き）:
   ```yaml
   reviewed_at: "<ISO 8601 タイムスタンプ>"
   reviewed_hash: "<上で計算したハッシュ>"
   ```

### OpenSpec タスク実装のコードレビューの場合

1. tree hash を取得する:
   ```bash
   git add -A && git write-tree
   ```

2. Edit tool で `tasks.md` のフロントマターに `reviewed_tasks` エントリを追加:
   ```yaml
   reviewed_tasks:
     "<task_id>": { hash: "<tree_hash>", at: "<ISO 8601>" }
   ```

3. ユーザーに「レビュー合格マーカーを保存しました」と報告する。
