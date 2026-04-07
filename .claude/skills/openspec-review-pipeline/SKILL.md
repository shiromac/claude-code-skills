---
name: openspec-review-pipeline
description: "OpenSpec の proposal から tasks まで全ドキュメントを段階的にチームレビューし、critical 指摘がなくなるまで繰り返す。レビュー済みドキュメント一式を品質保証する。"
maxTurns: 500
---

# OpenSpec Review Pipeline

proposal → design → specs → tasks の各ドキュメントを順に **作成→チームレビュー** し、critical 指摘が解消されるまで繰り返すパイプライン。存在しないドキュメントはスキップせず、先行ドキュメントの合格後に `openspec instructions` を使って作成してからレビューする。

## Input

- 引数: change 名（省略時は会話コンテキストから推定、曖昧なら `openspec list --json` で候補を出して AskUserQuestion で選択）

**重要: 自律実行原則** — このスキルは proposal から tasks まで **一切ユーザーに確認を求めずに自律的に走り切る**。途中で止まるのはパイプライン中断（3ラウンド経過で critical 未解消）と最終完了報告のみ。ドキュメント作成、レビュー結果の修正判断、次ドキュメントの作成・レビュー開始はすべて自動で行う。

## Step 1: 対象 change の特定とドキュメント確認

1. change ディレクトリ `openspec/changes/<name>/` の存在を確認
2. `proposal.md` の存在を確認する
3. **前提条件**: `proposal.md` が存在しない場合はパイプラインを開始しない

**処理順序**: `proposal.md` → `design.md` → `specs/` → `tasks.md`

各ドキュメントについて: 存在すればレビュー、存在しなければ **作成してからレビュー**（Step 1-A 参照）。

### Step 1-A: ドキュメントの作成

次のドキュメントが存在しない場合、`openspec instructions` を使って作成する:

1. `openspec instructions <artifact-id> --change "<name>" --json` を実行し、テンプレート・ルール・依存関係を取得
2. `dependencies` に列挙された先行ドキュメント（レビュー合格済み）を読み込む
3. `template` の構造に従い、`context` と `rules` を制約として適用してドキュメントを生成（`context` / `rules` の内容自体はドキュメントに含めない）
4. `outputPath` にファイルを書き込む
5. Step 2 のレビューループへ進む

## Step 2: ドキュメントごとのレビューループ

各ドキュメントについて以下のプロセスを実行する。

### 2-1. レビュー済みかチェック

change ディレクトリ直下のマーカーファイル `openspec/changes/<change_name>/.review-<artifact_name>.json` を確認する。

マーカー JSON の形式:
```json
{
  "change": "<change_name>",
  "artifact": "<artifact_name>",
  "file_hash": "<git hash-object の出力>",
  "reviewed_at": "<ISO 8601>",
  "ok": true
}
```

**スキップ条件**: マーカーが存在し、かつマーカー内の `file_hash` が現在のファイルの `git hash-object <file>` と一致する場合のみスキップする。ハッシュが異なればドキュメントが変更されているので再レビューする。

> specs/ ディレクトリの場合は、配下の全ファイルのハッシュを連結してハッシュ化する: `cat specs/*.md | git hash-object --stdin`

### 2-2. チームレビュー (ラウンド 1)

team-review の手順（レビュアー選出、チーム作成、レビュアー spawn、レビュー実行、統合レポート作成）をパイプラインエージェント自身が直接実行する。`/team-review` スキルは呼ばない（対話的フローのためパイプラインの自律実行と噛み合わないため）。

具体的には team-review (``.claude/commands/team-review.md``) の Step 1〜5 の手順に従い:
1. 対象ドキュメントを読んで説明文を作成
2. レビュアーを選出（コア4人 + 対象に応じた追加メンバー）
3. TeamCreate でチーム作成、Agent で各レビュアーを spawn
4. 全レビュアーの報告を待つ
5. 統合レビューレポートを作成（妥当性検証 + 統合テーブル）

**ラウンド 2 以降の追加コンテキスト**: Step 2-4 参照。レビュアー spawn 時のプロンプトに含める。

### 2-3. レビュー結果の処理

統合レビュー結果の確認後:

1. **妥当な指摘（妥当 + 部分的に妥当）をすべて修正する** — 重要度（critical / warning / nit）を問わず、妥当と判定された指摘はすべてドキュメントを直接編集して対処する
2. **そのラウンドで critical 指摘が発見されたかどうかを判定する**:
   - critical 指摘が **0 件発見** → このドキュメントは合格。マーカー書き込み（Step 2-7）後、次のドキュメントへ（存在しなければ Step 1-A で作成してからレビュー）
   - critical 指摘が **1 件以上発見** → 修正済みであっても、修正の妥当性と波及影響を確認するためラウンド 2 へ

> **判定基準の明確化**: 「critical 0 件」はそのラウンドのレビューで critical が **一つも発見されなかった** ことを意味する。修正してもカウントは減らない。critical が発見された時点で再レビューは確定。

### 2-4. 再レビュー (ラウンド 2 以降)

ラウンド N（N >= 2）では、Step 2-2 と同じ手順でレビュアーチームを再構成する。ただし、レビュアー spawn 時のプロンプトに以下の追加コンテキストを含める:

```
## Previous review context (Round {N})

This is review round {N} for this document. In the previous round, the following critical issues were found and addressed:

{前回の critical 指摘の一覧とその修正内容}

### Diff of fixes applied
{前回の修正で変更された箇所の diff}

### Focus areas for this round:
1. **Verify fix quality** — read the diff above. Are the fixes adequate? Do they address the root cause or just the surface symptom? Have they introduced new problems?
2. **Trace implications of previous critical issues** — the previous round found the critical issues listed above. Ask yourself: "If THIS was a problem, what OTHER parts of the document are likely affected by the same flawed assumption or oversight?" Follow the logical chain — e.g., if a critical was "the concurrency model assumes single-writer", check whether the caching strategy, error recovery, and state management sections also rely on that same broken assumption
3. **Expand review scope** — focus on areas NOT covered in the previous round's review, especially:
   - Sections of the document that were not mentioned in any previous finding
   - Interactions between the fixed areas and other parts of the document
   - Edge cases and implications that the previous fixes may have introduced
```

### 2-5. 繰り返し条件

- critical 指摘が **0 件発見** → 合格。次のドキュメントへ（存在しなければ Step 1-A で作成）
- critical 指摘が **発見された** かつ **ラウンド < 3** → 修正して再レビュー (Step 2-4)
- critical 指摘が **発見された** かつ **ラウンド = 3** → **パイプライン中断**

### 2-6. パイプライン中断時

3 ラウンド経過しても critical 指摘が解消されない場合:

1. これまでの全ラウンドの critical 指摘を時系列でまとめて表示する
2. 以下のメッセージをユーザーに提示する:

```
## Review Pipeline Suspended

**Document**: <document path>
**Rounds completed**: 3
**Remaining critical issues**: N

3回のレビューラウンドを経ても critical 指摘が解消されませんでした。
ドキュメントの前提や方向性自体に根本的な問題がある可能性があります。

### Critical 指摘の履歴
{全ラウンドの critical 指摘サマリー}

### 考えられる原因
- 要件の前提に矛盾がある
- 設計方針が根本的に合っていない
- スコープが大きすぎて1つのドキュメントで扱いきれない
- 修正が表面的で根本原因に届いていない（修正の振動）

ユーザーの判断をお待ちしています。
```

3. スキルを終了する（後続ドキュメントのレビューも中断）

### 2-7. 合格マーカーの書き込み

ドキュメントが合格（critical 0 件のラウンドで終了）したら、change ディレクトリ直下にマーカーファイルを書き込む。

書き込み先: `openspec/changes/<change_name>/.review-<artifact_name>.json`

```bash
# ハッシュ取得とマーカー書き込みを1コマンドで実行
bash -c 'hash=$(git hash-object <document_path>) && cat > openspec/changes/<change_name>/.review-<artifact_name>.json << EOF
{
  "change": "<change_name>",
  "artifact": "<artifact_name>",
  "file_hash": "'$hash'",
  "reviewed_at": "<ISO 8601>",
  "ok": true
}
EOF'
```

## Step 3: 全ドキュメント合格時の完了報告

すべてのドキュメントが合格したら:

```
## Review Pipeline Complete

**Change**: <name>
**Documents reviewed**:
- proposal.md — Round {N} で合格
- design.md — Round {N} で合格
- specs/ — Round {N} で合格
- tasks.md — Round {N} で合格

**Created by pipeline**: {パイプライン内で新規作成したドキュメントの一覧。なければ「なし」}
**Skipped (already reviewed)**: {マーカーによりスキップしたドキュメントの一覧。なければ「なし」}

### レビュー過程で発見された critical 指摘（修正済み）

{各ドキュメントで発見された critical 指摘の一覧と、どのように修正したかのサマリー。
 critical 指摘がなかったドキュメントは「critical 指摘なし」と記載}

### 主な修正箇所
{warning/nit を含む主要な修正の概要}

全ドキュメントのチームレビューが完了し、指摘事項は修正済みです。
ドキュメントの内容を確認していただき、問題がなければ実装に進めます。
```

完了報告後、**実装には進まずユーザーの最終確認を待つ**。ユーザーが承認するまでスキルを終了する。

## Guardrails

- **途中でユーザーに確認を求めない** — ドキュメント作成→レビュー→修正→再レビュー→次ドキュメント作成の流れはすべて自律的に判断して進める。止まるのは「3ラウンド中断」と「最終完了報告」の2箇所のみ
- **team-review スキルは呼ばない** — team-review の手順書を参照してパイプラインエージェント自身がレビュアーチームを構成・実行する（対話的フローの回避）
- 統合レビューレポートの妥当性検証は team-review の Step 5-2 の手順に従う
- ドキュメント修正は指摘内容に忠実に行い、スコープ外の変更を加えない
- 各ラウンドの結果（指摘一覧、修正内容、修正 diff）をログとして保持し、次ラウンドのコンテキストに含める
- **先行ドキュメント修正時の再レビュー** — 後続ドキュメントのレビュー中に先行ドキュメントとの整合性問題が発見された場合、先行ドキュメントを修正し、そのドキュメントの合格マーカー（`openspec/changes/<name>/.review-<artifact>.json`）を削除して Step 2 のレビューループを再実行してから後続ドキュメントのレビューに戻る
- **specs/ ディレクトリの扱い** — ディレクトリ全体を1回のレビュー対象とする（ファイル間の整合性確認が重要なため）。ただしファイル数が多い場合はレビュアーに全ファイルのパスを明示して漏れを防ぐ
