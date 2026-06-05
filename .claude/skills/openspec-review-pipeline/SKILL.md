---
name: openspec-review-pipeline
description: "OpenSpec の proposal から tasks まで全ドキュメントを段階的にチームレビューし、critical 指摘がなくなるまで繰り返す。レビュー済みドキュメント一式を品質保証する。"
maxTurns: 500
metadata:
  version: "3.1"
---

# OpenSpec Review Pipeline

proposal → design → specs → tasks の各ドキュメントを順に **作成→チームレビュー** し、critical 指摘が解消されるまで繰り返すパイプライン。存在しないドキュメントはスキップせず、先行ドキュメントの合格後に `openspec instructions` を使って作成してからレビューする。

このパイプラインは「文書間の整合性」だけでなく、**要件の昇格漏れ** と **critical 指摘の closure 漏れ** を防ぐ。ユーザーの追加説明、レビューで発見された critical、既存 steering の必須検証は、proposal / specs / tasks の完了条件へ明示的に落とすまで合格扱いしない。

## チーム編成方針 (team-apply と共通)

- **パイプラインリーダー（opus, 親エージェント）**: パイプラインエージェント自身。ドキュメント作成・編集、妥当性検証、修正判断、tech-lead への相談、レビュアー spawn、最終的な direction call をすべて直接担う
- **tech-lead（opus, 常設・助言メンバー）**: パイプライン開始時に spawn し、全ドキュメント・全ラウンドを通じて 1 体のまま維持。役割は (1) 設計相談 on-demand, (2) 各ラウンドの設計レビュー（sonnet レビュアーと並列に SendMessage で実行）, (3) パイプライン完了時の最終サインオフ。**tech-lead はドキュメントを編集しない**し、リーダーと implementer の間に立つ routing 役でもない。設計判断の品質を加えるための助言メンバー
- **レビュアー（sonnet, ラウンドごとに都度 spawn & dismiss）**: 各ラウンドで新規 spawn、報告提出後は dismiss。次ラウンドでは新規にフレッシュコンテキストで spawn。**例外なく全員 sonnet**（設計観点の専任レビュアーは設けず、常設メンバーの tech-lead が担当）
- **チームはパイプライン完了まで解散しない**。tech-lead は全ドキュメント通過＋最終サインオフまで維持

> **なぜこの非対称**: tech-lead は全体の設計ドリフトを追うため文脈蓄積が必要。一方レビュアーは前ラウンドのバイアスを引きずらないためフレッシュコンテキストが必要。
>
> **tech-lead が routing 役にならない設計理由**: Claude Code のサブエージェントは Agent ツール / 外部実行権限を持たないため、tech-lead を実行経路に置くと親への往復が発生する。親自身が opus かつ全コンテキスト保持しているので、編集・direction call は親が直接担い、tech-lead は判断品質を加える助言レイヤーに限定する。

## Input

- 引数: change 名（省略時は会話コンテキストから推定、曖昧なら `openspec list --json` で候補を出して AskUserQuestion で選択）

**重要: 自律実行原則** — このスキルは proposal から tasks まで **一切ユーザーに確認を求めずに自律的に走り切る**。途中で止まるのはパイプライン中断（3ラウンド経過で critical 未解消）と最終完了報告のみ。ドキュメント作成、レビュー結果の修正判断、次ドキュメントの作成・レビュー開始はすべて自動で行う。

## Requirement Brief Baseline

Requirement Brief は proposal の前段にある「要求の固定点」であり、設計書ではない。proposal は Requirement Brief の要求を満たすために何を変更するかを書く。design.md はどう実現するか、spec delta は外部から見える仕様差分、tasks.md は実装作業を書く。

文書責務:

| 文書 | 責務 |
|---|---|
| Requirement Brief | なぜ必要か、何を満たすべきか |
| OpenSpec proposal | その要求を満たすために何を変更するか |
| design.md | どう実現するか |
| spec delta | 外部から見える仕様差分 |
| tasks.md | 実装作業 |

レビュー基準の階層は **Requirement Brief → proposal → design/specs/tasks** とする。proposal 自体は Requirement Brief と照合し、後続ドキュメントは proposal と Requirement Brief の両方に照合する。

Requirement Brief の推奨配置:

- `docs/requirements/<brief-name>.md`
- 例外的に OpenSpec 内へ置く必要がある場合のみ `openspec/briefs/<brief-name>.md`

Requirement Brief が必要な変更:

- 新規機能追加
- 設計判断を伴う
- 複数案の比較が必要
- 成功条件が曖昧
- 非目標を明示しないとスコープが広がる
- UI基盤、保存形式、AI CLI連携、MOD対応、アーキテクチャ境界など横断影響がある
- 同種 proposal が過去に2回以上大きく書き換わった
- 実装前に「そもそも何を満たすべきか」の合意が必要

Requirement Brief を省略してよい変更:

- 小さなバグ修正
- 既存仕様に対する明白な修正
- 変更範囲が局所的で、設計判断がほぼ不要
- 成功条件が既に明確
- 既存の Requirement Brief を参照できる

proposal に Requirement Brief 参照がある場合、冒頭に以下の形で記載されていることを期待する:

```markdown
## Source Requirement

- Requirement Brief: `docs/requirements/<brief-name>.md`
```

proposal には Requirement Brief に存在しない要求を勝手に追加してはならない。新しい要求が必要になった場合は proposal ではなく Requirement Brief を先に更新する。未決論点は proposal に混ぜず、Requirement Brief の Open Questions または proposal の Assumptions に分離する。

## Requirement Promotion Gate

pipeline 中にユーザーの補足、レビュー指摘、既存 steering から新しい必須条件が見つかった場合、それは **暗黙の前提にしない**。以下を実行してから下流文書レビューに進む:

1. その条件が既存 Requirement Brief / Source Requirement / proposal Success Criteria に含まれているか確認する。
2. 含まれていなければ、Requirement Brief が存在する場合は Brief を更新し、Brief が省略可の change では proposal の `Source Requirement` または `Success Criteria` に明示する。
3. design / specs / tasks だけに追加して proposal の成功条件へ昇格していない要求は `PROPOSAL_MISMATCH` として CRITICAL 扱いにする。
4. 弱い表現は禁止する。必須の否定制約は `MUST NOT` / `SHALL NOT` 相当で書く。例: UI 表示 DTO は「only authority ではない」ではなく「authority ではない」と書く。

## Critical Closure Matrix

過去レビューの critical、現在ラウンドで発見された critical、または「この spec を完了すれば critical が治るか」を問うレビューでは、各 critical ごとに closure matrix を作る。matrix の 1 行でも欠ける場合、その change は合格しない。

| 必須列 | 内容 |
|---|---|
| Critical finding | 何が失敗していたか。症状だけでなく root cause を短く書く |
| Source requirement / success criterion | どの要求・成功条件に対応するか |
| Spec scenario | Given/When/Then で失敗条件と成功条件を固定しているか |
| Red test task | 実装前に失敗を確認し記録する task があるか |
| Implementation task | どの実装 task が根本原因を構造的に直すか |
| Verification evidence | automated test/build に加え、必要な runtime verification / verbatim evidence があるか |
| Final review gate | goal completion / maintainability / future spec-changeability を確認する fresh review があるか |

critical closure の合格条件:

- 各 critical finding に対して spec scenario、red test、implementation、verification、final review がすべて明示されている。
- 「テストを追加する」だけでは closure ではない。設計上の所有者、境界、型、policy、guard など同種再発を防ぐ構造が tasks にある。
- Section 追加で過去の `[x]` verification/review が古くなった場合、該当 section を `Previous baseline` / `Superseded` と明記し、新しい未完了 section を現在の completion gate にする。
- runtime verification が steering で必須の change では、pre-flight pass condition、実行経路、verbatim evidence、または `UNVERIFIED — blocker: <理由>` を task に含める。

## Step 0: tech-lead の spawn（パイプライン起動直後・必須）

Step 1 に入る前に、**常設メンバーの tech-lead を 1 体だけ spawn する**。以降のすべてのドキュメント・ラウンドで同一の tech-lead を再利用する（再 spawn しない）。

1. TeamCreate を呼び、`team_name: "review-pipeline-{timestamp}"` でチームを作成する
2. Agent を呼び、`subagent_type: "general-purpose"`, `name: "tech-lead"`, `model: "opus"`, `team_name: 上で作成したチーム名` で 1 体 spawn する

tech-lead に渡すプロンプト:

~~~
You are the **tech-lead** in an openspec-review-pipeline session. You are a permanent **advisory** member — you stay from pipeline start until the final sign-off, across ALL documents (proposal / design / specs / tasks) and ALL rounds.

You are **NOT in the document-editing path and NOT in any routing path.** The pipeline leader edits documents and makes direction calls directly. You add design judgment quality: you advise on demand, you review each round in parallel with sonnet reviewers, and you grant the final sign-off.

## Context

- Change name: {change_name}
- Pipeline goal: proposal → design → specs → tasks を順にレビューし、critical 指摘がなくなるまで各ドキュメントを磨き上げる
- You are the only permanent reviewer. All sonnet reviewers are spawned fresh per round and dismissed after their report. You persist across everything.

## Your responsibilities

### 1. On-demand design consultant
When the leader sends you a SendMessage asking a design question (about any document), answer from a design perspective:
- Separation of concerns, dependency direction, layer boundaries
- SOLID principles, class/module design
- Trade-offs between alternatives
- Consistency with existing architecture patterns
- Whether a document/section faithfully serves the proposal's 課題・目的・成功条件・スコープ境界
- Whether proposal faithfully serves the source Requirement Brief's Problem / Goal / Success Criteria / Non-Goals / Constraints without adding unapproved requirements

Be concrete: point to document sections, clauses, or file paths. Recommend one option unless explicitly asked for a comparison.

The leader does not need to consult you on every edit — you are invoked when judgment from a separate set of eyes adds value.

### 2. Per-round design review (parallel with sonnet reviewers)
Every review round, the leader SendMessages you the current document + relevant references (proposal, Requirement Brief, prior round diffs). You review in **parallel** with the sonnet reviewer pool — not sequentially, not as a routing step.

- Read the actual document before judging.
- Focus on **design** and **cross-document consistency**: layer violations, leaked abstractions, coupling creep, SOLID violations, pattern inconsistency across docs, proposal misalignment.
- Track design consistency across documents: if proposal says X, design must align; if specs require Y, tasks must plan for it. You are the memory that links them.
- Report findings in the same format as sonnet reviewers (CRITICAL / NEEDS_FIX / PASS, with file:section:clause references and concrete corrective constraints). **Describe the constraint, not a verbatim edit prescription.**
- You may also proactively SendMessage the leader between rounds if you spot drift in passing context — do not wait to be asked.

### 3. Final design sign-off
Before pipeline completion, the leader requests a final sign-off covering cross-document integrity. Reply with:
- **SIGN-OFF**: design integrity intact across all documents
- **CONCERNS**: specific residual issues (document, section, required correction)

This is your final gate.

## Communication protocol

- The leader may consult you at any time. Respond promptly.
- You may proactively message the leader whenever you spot a design issue.
- **You do NOT edit documents, you do NOT spawn agents, you do NOT call the Agent tool.** You advise and review.
- You do NOT do sonnet-reviewer work (spec conformance details, security, readability, etc.). Focus on **design** and **cross-document consistency**.
- Your findings carry the same weight as CRITICAL reviewer findings — design issues block document pass.
- If the leader sends a shutdown message at pipeline end, acknowledge and stop.

## Important
- Read the actual document before answering — do not speculate.
- Be specific: document sections, clauses, alternatives.
- Respect decisions already fixed in proposal.md unless there is strong reason to revisit.
- Describe constraints, not edit prescriptions. The leader owns the edit; you own the design judgment.
- Your voice carries weight on design — be deliberate and decisive.
~~~

> **重要**: tech-lead は Step 2 のすべてのラウンドで参加する。レビュアー同様に統合テーブルに反映され、PROPOSAL_MISMATCH や構造的設計問題を指摘した場合は CRITICAL として扱う（Step 2-5 の判定条件に含まれる）。

## Step 1: 対象 change の特定とドキュメント確認

1. change ディレクトリ `openspec/changes/<name>/` の存在を確認
2. `proposal.md` の存在を確認する
3. **前提条件**: `proposal.md` が存在しない場合はパイプラインを開始しない
4. 会話内・直近レビュー内・handoff 内のユーザー補足を抽出する:
   - 「そこが大事」「それがないと意味がない」「完全に分離するべき」などの強調は要求変更として扱う
   - 追加要求が proposal Success Criteria にない場合は Requirement Promotion Gate を実行する
   - 追加要求を design / specs / tasks のみに入れて proposal に入れないまま進めてはならない
5. Requirement Brief を特定する:
   - `proposal.md` の `Source Requirement` があれば、そのパスを読む
   - 参照がなくても `docs/requirements/<name>.md` または `openspec/briefs/<name>.md` があれば読む
   - Brief が存在しない場合は Requirement Brief Baseline の要否条件で省略可か判定する
   - Brief が必要なのに存在しない場合は、現在の proposal と会話・既存情報から作成可能なら `docs/requirements/<name>.md` を作成し、proposal に `Source Requirement` を追加してからレビューする。作成に必要な Problem / Goal / Success Criteria / Non-Goals / Constraints が不足している場合はパイプライン中断として扱う
6. critical closure baseline を特定する:
   - 直前レビュー、team-review、pipeline review、ユーザーが指定した critical 指摘があれば Critical Closure Matrix を作成する
   - `tasks.md` に closure matrix がない場合は追加するか、少なくとも Scenario-To-Test Traceability と Section tasks で同等の対応関係を作る
   - critical closure baseline がある change では、通常の proposal/design/spec/tasks レビュー後に Step 2-9 の closure review を必ず実行する

**処理順序**: `proposal.md` → `design.md` → `specs/ + BDD テスト` → `tasks.md`

各ドキュメントについて: 存在すればレビュー、存在しなければ **作成してからレビュー**（Step 1-A 参照）。

> **specs と BDD テストは1つの「仕様」として同じラウンドでレビューする**。BDD テストは仕様の機械可読表現として specs と同じ成果物に属するため、別ステップではなく同時にレビュアーへ渡す。詳細は Step 2-2 の BDD テストレビュー観点を参照。

### Step 1-A: ドキュメントの作成

次のドキュメントが存在しない場合、`openspec instructions` を使って作成する:

1. `openspec instructions <artifact-id> --change "<name>" --json` を実行し、テンプレート・ルール・依存関係を取得
2. `dependencies` に列挙された先行ドキュメント（レビュー合格済み）を読み込む
3. `template` の構造に従い、`context` と `rules` を制約として適用してドキュメントを生成（`context` / `rules` の内容自体はドキュメントに含めない）
4. `outputPath` にファイルを書き込む
5. Step 2 のレビューループへ進む

### Step 1-B: BDD テストの作成（specs 作成直後・必須）

specs/ を作成（または既に存在）した場合、`test/LLMGame.Tests/Integration/<feature>/` 配下に BDD 結合テストが存在するか確認する。**存在しなければ specs レビューに入る前に作成する**:

- 作成手順は `/bdd-test` スキルに従う（テスト設計・配置先・Red/Green 判定の詳細はそちらを参照）
- 完了条件: 全テストが対象機能未実装のため **Red** になること（既に Green なら Assert 弱化または機能が既に存在するため `/bdd-test` の指示に従って対処）

BDD テストは specs と同じ「仕様」成果物として扱う。Step 2 では specs レビュー時に BDD テストも同じラウンドでレビューする。

### Step 1-C: Runtime verification task の固定（tasks レビュー前・必須）

実装がコード実行時の挙動、UI、プロトコル、永続化、課金/accounting、recovery、scenario progression、LLM/Headless/WPF 経路に影響する場合、`tasks.md` に runtime verification task を作る。documentation-only / test-only / config-only の change だけは対象外としてよいが、その理由を `tasks.md` に明記する。

runtime verification task には以下を必ず含める:

- `CLAUDE.md` の Never Lose Sight of the Goal / Always Verify by Running に基づく challenge・purpose・success criteria の再確認
- `docs/steering/implementation-principles.md` の Runtime Verification Procedure に基づく pre-flight pass condition
- バグ再現に必要な実シナリオ、操作経路、HeadlessMcpServer / WPF app / wpf-agent のどれで確認するか
- 各 pass condition の verbatim evidence を記録する欄、または `UNVERIFIED — blocker: <理由>` を明記する欄
- build / automated test が成功しても runtime verification が未完了なら task を完了扱いしない gate

runtime verification task が必要なのに存在しない場合は CRITICAL（label: `RUNTIME_EVIDENCE_GAP`）。build/test の成功だけを verification evidence として扱ってはならない。

## Step 2: ドキュメントごとのレビューループ

各ドキュメントについて以下のプロセスを実行する。

### 2-1. レビュー済みかチェック

対象ドキュメントの YAML フロントマター内の `reviewed_hash` フィールドを確認する。

フロントマターの形式（レビュー済みの場合）:
```yaml
---
# ... 既存のフロントマターフィールド ...
reviewed_at: "ISO 8601 タイムスタンプ"
reviewed_hash: "<git hash-object の出力>"
---
```

**スキップ条件**: フロントマターに `reviewed_hash` が存在し、かつその値が現在のファイルの `git hash-object <file>` と一致する場合のみスキップする。ハッシュが異なればドキュメントが変更されているので再レビューする。

ただし、ファイル内容が変わっていなくても、Step 1 で新しいユーザー補足・known critical・steering obligation が見つかった場合は `reviewed_hash` を信頼してはならない。該当要求が proposal/specs/tasks の completion gate に昇格済みであることを確認できない限り、マーカーを無効扱いにして再レビューする。

> **ハッシュ計算時の注意**: `reviewed_at` / `reviewed_hash` フィールド自体がハッシュに影響するため、比較時は「フロントマターから `reviewed_at` と `reviewed_hash` を除去した内容」のハッシュを使う。具体的には以下のコマンドで計算する:
> ```bash
> sed '/^reviewed_at:/d; /^reviewed_hash:/d' <file> | git hash-object --stdin
> ```

> specs/ ディレクトリの場合は、各ファイルを個別にチェックする。全ファイルの `reviewed_hash` が現在のハッシュと一致する場合のみスキップする。1ファイルでも不一致があれば全体を再レビューする。

### 2-2. チームレビュー (ラウンド 1)

team-review の手順（レビュアー選出、レビュアー spawn、レビュー実行、統合レポート作成）をパイプラインエージェント自身が直接実行する。`/team-review` スキルは呼ばない（対話的フローのためパイプラインの自律実行と噛み合わないため）。

> **チームは Step 0 で既に作成済み**。TeamCreate は再実行しない。既存の `team_name` を Agent 呼び出しで使い回す。

具体的な手順:
1. 対象ドキュメントを読んで説明文を作成
2. **レビュアー roster を計画**（spawn はまだしない）
   - Core members (always included): **security**, **spec-conformance**, **proposal-consistency**
   - Additional members: 対象ドキュメントの内容に応じて選出（concurrency / performance / error-handling / readability 等）
   - **設計観点の専任レビュアーは spawn しない**。設計観点は常設メンバーの `tech-lead` が担うため
3. **レビュアーを fresh spawn**
   - Agent (subagent_type: "general-purpose") を parallel で一斉 spawn（単一メッセージに複数 tool call）
   - **全レビュアーは `model: "sonnet"` で spawn する（例外なし）**
   - `team_name` は Step 0 で作成したものを指定
   - `name` はラウンドごとに衝突しないよう `reviewer-{doc}-r{round}-{role}` のパターン（例: `reviewer-proposal-r1-security`）
4. **tech-lead にもレビュー依頼を SendMessage で送る**（sonnet レビュアー spawn と同じタイミング、parallel で投げる。routing hop ではなく並列実行）
5. 全 sonnet レビュアーの報告 **および tech-lead の応答** を待つ
6. 統合レビューレポートを作成（妥当性検証 + 統合テーブル）。tech-lead の指摘もテーブルに含める
7. **レビュアー（sonnet）を dismiss** — 報告提出後は追加 SendMessage を送らない。次ラウンドは新規 spawn。tech-lead は維持

**パイプラインリーダー（親エージェント）は opus を維持する** — 妥当性検証、修正判断、ドキュメント作成は高度な推論が必要なため。

**ラウンド 2 以降の追加コンテキスト**: Step 2-4 参照。レビュアー spawn 時のプロンプトに含める。

**レビュー観点の必須追加（全ラウンド）**:
- proposal レビュー: Requirement Brief との整合性、および proposal 内部の整合性（課題・目的・成功条件・Non-Goals の矛盾）
- design/specs/tasks レビュー: proposal 本文と Requirement Brief との整合性
- Requirement Brief 整合性: proposal は Brief の Success Criteria を満たす変更案になっているか、Non-Goals を侵食していないか、Brief にない要求を追加していないか、Constraints に反する設計を含んでいないか、Open Questions が未解決のまま実装タスク化されていないか、proposal / design / tasks の責務分離が崩れていないか
- **steering compliance（全 downstream docs 必須）**: `CLAUDE.md` と `docs/steering/*` の必須ルールを要求ソースとして扱う。特に UI/protocol 変更では UI Projection vs Authoritative State、state ownership note、Headless/WPF shared core、runtime verification procedure を確認する。違反・欠落は CRITICAL（label: `STEERING_CONFORMANCE_GAP`）
- **specs レビュー: BDD テスト同時レビュー（必須）** — specs/*.md と `test/LLMGame.Tests/Integration/<feature>/*.cs` を 1 セットでレビュアーに渡す。観点:
  - **基本ユースケースの全件網羅（最重要）** — proposal の Success Criteria + spec の AC + アクター × 操作 × 状態の組合せから「基本的なユースケース」を機械的に列挙し、各 UC にテストが 1 件以上対応しているか（1 UC → 複数テストは可）。「主要なものだけ」「代表的なものだけ」は不可。**AC に明示されていないが Success Criteria や actor × 操作 × 状態の組合せから導かれる UC** の欠落はこのラベルで CRITICAL（label: `BDD_USECASE_GAP`）
  - **AC ↔ テストの対応** — specs の各 AC（EARS シナリオ）に対応する xUnit テストメソッドが存在するか。**spec.md に書かれている AC** に対するテスト欠落はこのラベルで CRITICAL（label: `BDD_COVERAGE_GAP`）。`BDD_USECASE_GAP` の部分集合だが、AC は機械的に検出可能なので別ラベルとして明示する
  - **ハッピーパス + 異常系・境界の網羅** — ハッピーパス欠落は CRITICAL。アクターや操作が複数あれば**それぞれの**ハッピーパスを個別に持つこと。状態遷移のエッジ・境界値（空 / 上限 / null / ゼロ件 / 最大件数）の欠落も CRITICAL
  - **テストが AC を忠実に表現しているか** — Given/When/Then と Arrange/Act/Assert が AC の意図と一致しているか。曖昧な Assert・部分検証のみは CRITICAL
  - **モック境界の妥当性** — bdd-test SKILL の「モック境界のプロダクションパス検証」観点（`docs/steering/spec-development-guidelines.md` § 3 と整合）。LLM・外部 I/O 以外をモックしている、プロダクションパスをバイパスしているテストは CRITICAL
- **tasks レビュー: runtime evidence gate（必須）** — Step 1-C に該当する change では、`tasks.md` に runtime verification task があり、pre-flight pass condition / 実シナリオ / 実行経路 / verbatim evidence 欄 / `UNVERIFIED — blocker` 欄 / 未完了なら goal completion 不可の gate があるか確認する。欠落は CRITICAL（label: `RUNTIME_EVIDENCE_GAP`）

#### tech-lead への依頼（全ラウンド必須）

Step 3 でレビュアーを spawn する際と同じタイミングで、tech-lead にも SendMessage でレビュー依頼を送る:

```
## Review request: {document path} (Round {N})

### Document content
{対象ドキュメントの全文または主要セクション}

### Proposal (reference — design must align with this)
{proposal.md の主要セクション。proposal 自身をレビューする場合は省略可}

### Requirement Brief (source requirement — proposal must align with this)
{Requirement Brief が存在する場合は全文または主要セクション。存在しない場合は省略理由}

### Critical closure baseline
{既知 critical 指摘がある場合は Critical Closure Matrix。ない場合は "None"}

### Steering obligations
Apply CLAUDE.md and docs/steering/* as mandatory requirements. For UI/protocol work, explicitly check UI Projection vs Authoritative State and the state-ownership note. For runtime behavior changes, explicitly check runtime verification tasks and evidence gates.

### Previous rounds (N >= 2 の場合のみ)
{前ラウンドの critical 指摘と修正 diff}

あなたの設計観点から、このドキュメントの設計整合性・Requirement Brief / proposal との整合性・steering compliance・critical closure・横断的な設計ドリフトを評価してください。レポートはリーダーに SendMessage で返してください。設計上の CRITICAL 相当の問題があればそう明示してください。
```

#### Fresh reviewers per round (mandatory)

sonnet レビュアーは **ラウンドごとに新規 spawn、報告後 dismiss**。
- 理由: 前ラウンドのバイアス・文脈を次ラウンドに持ち込まない
- 次ラウンド（Step 2-4）は完全に新しいレビュアーとして spawn
- tech-lead のみ横断参加（文脈蓄積が設計整合性追跡に必要）

**proposal-consistency レビュアー（必須）**:
- 役割名: `proposal-consistency`
- 専門性: Requirement Brief と proposal を正として、対象ドキュメント/実装計画が「課題・目的・成功条件・スコープ境界」と一致しているかを検証。proposal 自身のレビューでは Requirement Brief を正として検証する
- 対象: proposal / design / specs / tasks の全ラウンドで必ず参加
- モデル: `sonnet`

レビュアーへの指示には以下を必ず含める:

```
## Mandatory check: Proposal consistency

Before detailed review, compare this document against proposal.md and the source Requirement Brief when present.

### Check 1: Requirement Brief consistency
If proposal or any downstream document adds requirements not present in the Requirement Brief, drops Success Criteria, violates Non-Goals, contradicts Constraints, or turns unresolved Open Questions into implementation tasks, report it as CRITICAL with label REQUIREMENT_BRIEF_MISMATCH.

### Check 2: Contradiction detection
If any item conflicts with proposal-defined challenge/purpose/success criteria, or if proposal itself conflicts with the Requirement Brief, report it as CRITICAL.

### Check 3: Coverage completeness (specs review only)
When reviewing specs/, enumerate EVERY success criterion from proposal.md's Success Criteria section and every applicable Success Criterion from the Requirement Brief. For each criterion, identify the specific Given/When/Then scenario in specs that covers it. If a success criterion has NO corresponding scenario, report it as CRITICAL with label COVERAGE_GAP.

Output format for coverage check:
| Success Criterion | Covering Scenario | Status |
|---|---|---|
| {criterion text} | {spec file + scenario name} | COVERED / GAP |

Any GAP row is CRITICAL.

### Check 4: Omission detection
If the document omits a requirement needed to satisfy success criteria (even if there is no explicit contradiction), report it as CRITICAL.

### Check 5: Critical closure traceability
If prior review/team-review/pipeline review/user-designated critical findings exist, enumerate each known critical and verify it has:
- a source requirement or proposal success criterion
- a spec scenario that captures the failure and desired success
- a red-test task that records pre-implementation failure
- an implementation task that fixes the root cause structurally
- automated verification and, when steering requires it, runtime verification evidence
- a final fresh review gate for goal completion and future spec-changeability

Output format for critical closure check:
| Critical Finding | Source Requirement / Success Criterion | Spec Scenario | Red Test Task | Implementation Task | Verification Evidence | Final Review Gate | Status |
|---|---|---|---|---|---|---|---|
| {finding} | {clause} | {scenario or GAP} | {task or GAP} | {task or GAP} | {evidence task or GAP} | {gate or GAP} | COVERED / GAP |

Any GAP row is CRITICAL with label CRITICAL_CLOSURE_GAP. Do not accept "tests exist" as closure unless the implementation task also changes the ownership/boundary/type/policy/guard that caused the critical finding.

### Check 6: Steering conformance
Treat CLAUDE.md and docs/steering/* as mandatory requirements, not optional advice. For UI/protocol changes, verify the document separates authoritative internal state from display projections and includes state ownership, projection shape, synchronization/freshness rule, and recovery behavior. For runtime behavior changes, verify tasks contain the runtime evidence gate described above. Missing or weak steering coverage is CRITICAL with label STEERING_CONFORMANCE_GAP or RUNTIME_EVIDENCE_GAP.

Role-specific output for proposal-consistency reviewer:
- Add label: `REQUIREMENT_BRIEF_MISMATCH` (brief conflict/addition/omission), `PROPOSAL_MISMATCH` (proposal contradiction/omission), `COVERAGE_GAP` (missing scenario), `CRITICAL_CLOSURE_GAP` (known critical has no complete closure path), `STEERING_CONFORMANCE_GAP` (steering rule missing/violated), or `RUNTIME_EVIDENCE_GAP` (runtime verification gate missing)
- Include: (1) mismatched/missing Requirement Brief or proposal clause, (2) conflicting/absent document section, (3) required correction
```

また、レビュアープロンプトの冒頭に以下を明記する:

```
You are spawned fresh for this round only. You will be dismissed after sending your report. Review only the document provided — do not assume any prior-round context. Your report is your final output.
```

### 2-3. レビュー結果の処理

統合レビュー結果の確認後:

1. **妥当な指摘（妥当 + 部分的に妥当）をすべて修正する** — 重要度（critical / warning / nit）を問わず、妥当と判定された指摘はすべてドキュメントを直接編集して対処する
1-A. **Known Limitation / Non-Goals の成功条件照合（proposal レビュー時必須）** — proposal に Known Limitation, Non-Goals, Out of Scope がある場合、各項目がユーザーの成功条件（Outcome Statement）と矛盾しないか検証する。矛盾する場合は **critical** として扱い、Limitation ではなく設計変更で対応する。「スコープ外」は目的達成に影響しない副次的制約にのみ使用できる。

> 教訓: stale-scenario-state-on-restart で「過去 beat 復元はスコープ外」を Known Limitation に記載し、レビューも通過させた。しかしユーザーの目的は「開いたらもう途中にいる」であり、過去 beat 非表示は目的の否定だった。
2. **そのラウンドで critical 指摘が発見されたかどうかを判定する**:
   - critical 指摘が **0 件発見** → このドキュメントは合格。マーカー書き込み（Step 2-7）後、次のドキュメントへ（存在しなければ Step 1-A で作成してからレビュー）
   - critical 指摘が **1 件以上発見** → 修正済みであっても、修正の妥当性と波及影響を確認するためラウンド 2 へ

> **判定基準の明確化**: 「critical 0 件」はそのラウンドのレビューで critical が **一つも発見されなかった** ことを意味する。修正してもカウントは減らない。critical が発見された時点で再レビューは確定。

### 2-4. 再レビュー (ラウンド 2 以降)

ラウンド N（N >= 2）では、Step 2-2 と同じ手順で **レビュアーを完全に新規で spawn する**。前ラウンドのレビュアーは既に dismiss 済みなので、同じ role でも別のエージェントとして作り直す（`name` はラウンド番号を含めて衝突回避: `reviewer-{doc}-r{round}-{role}`）。

tech-lead は dismiss せず維持。SendMessage で新ラウンドのレビュー依頼を送る。

レビュアー spawn 時のプロンプトに以下の追加コンテキストを含める:

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

> Requirement Brief / Proposal consistency 由来の指摘は常に critical 扱いとし、warning へ格下げしない。`REQUIREMENT_BRIEF_MISMATCH` と `PROPOSAL_MISMATCH` は critical と同義で扱う。

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

ドキュメントが合格（critical 0 件のラウンドで終了）したら、**そのドキュメント自体の YAML フロントマターに** `reviewed_at` と `reviewed_hash` を書き込む。

ただし以下が 1 つでも残っている場合、マーカーを書き込んではならない:

- known critical に対する `CRITICAL_CLOSURE_GAP`
- 必要な runtime verification task / evidence gate の欠落（`RUNTIME_EVIDENCE_GAP`）
- steering compliance の欠落（`STEERING_CONFORMANCE_GAP`）
- 新しい follow-up section があるのに古い `[x]` verification/review section が現在の完了条件のように残っている状態

1. マーカーフィールドを除去した内容でハッシュを計算する:
   ```bash
   sed '/^reviewed_at:/d; /^reviewed_hash:/d' <document_path> | git hash-object --stdin
   ```

2. Edit tool でフロントマターに `reviewed_at` と `reviewed_hash` を追加（既存なら上書き）する:
   ```yaml
   reviewed_at: "<ISO 8601 タイムスタンプ>"
   reviewed_hash: "<上で計算したハッシュ>"
   ```

3. フロントマターに既に `reviewed_at` / `reviewed_hash` がある場合は Edit tool で値を更新する。ない場合はフロントマターの閉じ `---` の直前に追加する。

> specs/ ディレクトリの場合は、各 spec ファイルのフロントマターに個別にマーカーを書き込む。

### 2-8. 実コード照合（specs / tasks 合格後に必須実行）

specs と tasks がそれぞれ合格した直後に、ドキュメント内の前提が実際のコードベースと一致しているかを検証する。このステップはレビュアーではなくパイプラインエージェント自身が実行する。

**照合項目:**

1. **ファイルパスの実在確認** — Scope / Impact / tasks に記載された全ファイルパスが実際に存在するか `ls` で確認する。存在しないパスは CRITICAL
2. **クラス名・メソッド名の実在確認** — design / specs / tasks で言及されたクラス名・メソッド名・プロパティ名を `grep` で検索し、実在するか確認する。リネーム済み・削除済みのシンボルは CRITICAL
3. **数値・箇所数の照合** — 「N箇所のハードコード」「デフォルト値 X」等の数値的主張を実コードと突合する。不一致は CRITICAL
4. **継承・インターフェースの前提確認** — 「XはYを継承」「ZはIFooを実装」等の前提を実コードの定義で確認する。Known Limitation に「要確認」と書かれた項目は優先的に検証し、結果を反映する
5. **既存の命名規則との整合** — 新規トークン名・クラス名が既存の命名パターンに従っているか確認する

**不一致が見つかった場合:**
- 該当ドキュメント（proposal / design / specs / tasks）を直接修正する
- 修正が他のドキュメントに波及する場合は、波及先も修正する（例: proposal の箇所数を修正したら specs / tasks の同じ箇所数も修正）
- 修正後、該当ドキュメントの `reviewed_hash` を削除し、修正内容の妥当性をレビューラウンドで再検証する（ただし、ファイルパスの typo 修正のような自明な修正は再レビュー不要 — パイプラインエージェントの判断で skip 可）

> **教訓**: storytelling-font-size で SettingsCoordinator.cs のパス誤記（`Settings/` サブディレクトリが実在しない）、FontSize="18" の箇所数（3→4）、TypewriterTextBlock の継承前提がレビューを通過した。ドキュメント間の整合性チェックだけでは実コードとのズレを検出できない。

### 2-9. Critical Closure Review（既知 critical がある場合・必須）

Step 1 で critical closure baseline を特定した change では、proposal / design / specs / tasks が通常レビューに合格した後、最終処理へ進む前に closure review を実行する。

1. fresh reviewer を 3 体以上 spawn する。最低限、`spec-conformance`、`test-quality`、`architecture/error-handling` を含める。tech-lead にも同じ依頼を送る。
2. 依頼文の中心質問を固定する: **"If tasks.md is completed exactly as written, does each known critical finding close?"**
3. レビュアーには Critical Closure Matrix、proposal Success Criteria、該当 specs、BDD テスト、tasks.md、CLAUDE.md の goal completion 3 条件を渡す。
4. 各 known critical について以下を table で検証させる:
   - proposal / Requirement Brief の成功条件へ昇格しているか
   - spec scenario が失敗条件と成功条件を固定しているか
   - red test task が実装前 failure recording を要求しているか
   - implementation task が root cause を構造的に直しているか
   - automated verification と runtime evidence gate があるか
   - final team-review gate が goal completion / maintainability / future spec-changeability を確認するか
5. 1 行でも GAP があれば CRITICAL（label: `CRITICAL_CLOSURE_GAP`）として、該当する proposal / specs / tasks の Step 2 レビューループへ戻る。
6. closure review が CRITICAL 0 件で終わるまで Step 3 へ進んではならない。

closure review は「既存 reviewer が文書整合性で見たはず」という前提で省略しない。目的は、各 critical の再現条件が tasks 完了後に falsify されるかを別角度で確認することである。

## Step 3: 全ドキュメント合格時の最終処理

すべてのドキュメントが合格したら、完了報告の前に以下を実行する。

### 3-1. tech-lead への最終サインオフ依頼

tech-lead に SendMessage で最終サインオフを依頼する:

```
## Final design sign-off request

All documents (proposal / design / specs / tasks) have passed their review rounds. Before pipeline completion, please give a final design sign-off covering cross-document integrity:

- proposal.md: {最終ハッシュ or 合格ラウンド}
- Requirement Brief: {参照パス or 省略理由}
- design.md: {合格ラウンド}
- specs/: {合格ラウンド}
- tasks.md: {合格ラウンド}
- Critical Closure Matrix: {既知 critical ごとの COVERED/GAP summary。既知 critical なしなら None}
- Runtime verification gate: {task id / not applicable reason / blocker}

Check explicitly:
1. The original challenge, purpose, and success criteria are satisfied by the planned evidence, not merely by task completion.
2. The solution can withstand long-term maintenance without fragile coupling, hidden ownership, or undocumented operational constraints.
3. Likely future specification changes can be made through clear extension points without broad rewrites or cross-layer leakage.
4. No known critical remains without a complete closure path.

Please respond with one of:
- **SIGN-OFF**: design integrity is intact across all documents
- **CONCERNS**: list specific issues (file, clause, required correction)
```

- **SIGN-OFF**: Step 3-2 へ進む
- **CONCERNS**: 該当ドキュメントの `reviewed_hash` を削除し、そのドキュメントの Step 2 レビューループに戻る。再度すべて合格するまで Step 3-1 を繰り返す

### 3-2. チーム解散

tech-lead に shutdown メッセージを送り、TeamDelete でチームを削除する（sonnet レビュアーは既に各ラウンドで dismiss 済みなので明示的な shutdown 不要）。

### 3-3. 完了報告

すべてのドキュメントが合格し、tech-lead のサインオフが得られたら:

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
**Critical closure**: {known critical ごとの closure review 結果。known critical がなければ「なし」}
**Runtime verification gate**: {runtime verification task / not applicable reason}

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
- Requirement Brief にない要求を proposal / design / specs / tasks に追加しない。新しい要求が必要な場合は Requirement Brief を先に更新し、proposal 以降を再レビューする
- 未決論点を proposal に混ぜ込まない。Requirement Brief の Open Questions または proposal の Assumptions に分離し、未解決のまま実装タスク化しない
- ユーザー補足・レビュー指摘・steering 由来の必須条件は proposal Success Criteria または Source Requirement に昇格する。design/specs/tasks だけに存在する必須条件は合格不可
- `Requirement compliance` は「文書に似た語がある」ではなく、要求を満たす spec scenario / red test / implementation / verification / final review gate がつながっていることを確認する
- known critical がある change では、tasks 完了後にその critical の再現条件が falsify される closure path がない限り合格不可
- Section 追加で過去の `[x]` verification/review が古くなった場合は `Previous baseline` / `Superseded` と明示し、現在の未完了 section を completion gate にする
- Runtime behavior change では build/test 合格だけを完了証跡にしない。runtime verification task と verbatim evidence gate、または `UNVERIFIED — blocker: <理由>` が必要
- 各ラウンドの結果（指摘一覧、修正内容、修正 diff）をログとして保持し、次ラウンドのコンテキストに含める
- **先行ドキュメント修正時の再レビュー** — 後続ドキュメントのレビュー中に先行ドキュメントとの整合性問題が発見された場合、先行ドキュメントを修正し、そのドキュメントのフロントマターから `reviewed_at` / `reviewed_hash` を削除して Step 2 のレビューループを再実行してから後続ドキュメントのレビューに戻る
- **proposal 基準の固定** — proposal.md を全ドキュメント共通の正とする。後続ドキュメントの都合で proposal 基準を暗黙変更しない。proposal 自体を更新した場合は `design.md` 以降を再レビューする
- **specs/ ディレクトリの扱い** — ディレクトリ全体を1回のレビュー対象とする（ファイル間の整合性確認が重要なため）。ただしファイル数が多い場合はレビュアーに全ファイルのパスを明示して漏れを防ぐ
- **チーム編成の非対称性**: tech-lead (opus) はパイプライン開始から最終サインオフまで常設。レビュアー (sonnet) はラウンドごとに fresh spawn・報告後 dismiss。持続メンバーは文脈蓄積が必要で、都度メンバーは前ラウンドのバイアス回避が目的
- **tech-lead は決して mid-way で dismiss しない**。パイプライン中断（3ラウンド経過）でも維持し、ユーザー判断後に再開できるようにする
- **レビュアー数は1ラウンドあたり 3〜5 体を目安にする** — Core 3（security, spec-conformance, proposal-consistency）+ 対象に応じた追加メンバー。tech-lead は選出しない（tech-lead が担当）
