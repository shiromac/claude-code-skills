# Claude Code Review Skills

Claude Code で使えるチームレビュー・チーム実装スキル集。複数の専門レビュアーエージェントを自動生成し、コードやドキュメントを多角的にレビューします。

## Skills

### `/openspec-review-pipeline`

proposal → design → specs → tasks の各ドキュメントを順にチームレビューし、critical 指摘が解消されるまで繰り返す自律パイプライン。

- ドキュメントごとに専門レビュアーチーム（architect, security, spec-conformance, doc-consistency + 追加メンバー）を自動構成
- critical 指摘が見つかれば修正→再レビューを最大3ラウンド自動実行
- 全ドキュメント合格まで一切ユーザー確認なしで自律進行

### `/team-apply`

リーダー＋実装者＋レビュアーによるチーム実装。リーダーはコードを書かず、指揮・検証・報告に専念します。

- 依存関係を分析し、独立タスクは複数の実装者が並行実行
- 実装完了後、専門レビュアーチームがバッチレビュー
- 指摘があれば修正→再レビューを自動で繰り返し

### `/team-review`

複数の専門レビュアーによるチームレビュー。コード変更やドキュメントを多角的にレビューします。

- コアレビュアー4人（architect, security, spec-conformance, doc-consistency）が常に参加
- 対象に応じて追加メンバー（concurrency, performance, test-quality, error-handling, readability, ux）を自動選出
- レビュアー同士が互いに相談可能
- 親エージェントが指摘の妥当性を検証し、誤検出を除外

### `/self-review`

サブエージェントによるセルフレビュー。親エージェントが変更内容を説明し、サブエージェントが独立にコードを読んで検証します。

- 親エージェントの説明を鵜呑みにせず、実際のコードを読んで検証
- セキュリティ、パフォーマンス、エッジケース、テストカバレッジなど多面的にチェック
- 親エージェントが最終的に指摘の妥当性を検証

### `/team-investigate`

複数メンバーで根本原因を調査するコマンド。実装ミスだけでなく、設計・仕様・要件レベルまで掘り下げて再発防止策を提案します。

- code, design, spec, prevention の観点から独立調査
- 表面的なバグ修正ではなく構造的な再発防止を重視
- 最近の変更履歴や OpenSpec 文脈も踏まえて意図的変更か退行かを切り分け

## Install

プロジェクトルートで以下を実行するだけです:

```bash
curl -fsSL https://raw.githubusercontent.com/shiromac/claude-code-skills/main/install.sh | bash
```

### 手動インストール

```bash
git clone --depth 1 https://github.com/shiromac/claude-code-skills.git /tmp/claude-code-skills
mkdir -p .claude/skills .claude/commands
cp -r /tmp/claude-code-skills/.claude/skills/* .claude/skills/
cp -r /tmp/claude-code-skills/.claude/commands/* .claude/commands/
rm -rf /tmp/claude-code-skills
```

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) が利用可能であること
- Claude Code の Agent tool、TeamCreate、SendMessage 等のチーム機能が利用可能であること

### openspec-review-pipeline の追加要件

このスキルは [OpenSpec](https://github.com/openspec-dev/openspec) ワークフローを前提としています:

- `openspec` CLI がインストール済みであること
- `openspec/changes/<name>/` にドキュメント（proposal.md, design.md, specs/, tasks.md）があること

> **team-apply, team-review, self-review は OpenSpec なしでも単独で利用できます。**

> **team-investigate も OpenSpec なしで利用できますが、関連仕様がある場合は OpenSpec 文書の確認を行います。**

## File Structure

```
.claude/
  skills/
    openspec-review-pipeline/
      SKILL.md          # ドキュメントレビューパイプライン
    team-apply/
      SKILL.md          # チーム実装
  commands/
    team-review.md      # チームレビュー
    self-review.md      # セルフレビュー
    team-investigate.md # チーム調査
```

### Dependency Graph

```
openspec-review-pipeline
  └── team-review (手順を参照)
        └── self-review (妥当性検証を参照)

team-apply
  └── (独立、ただし同じレビュアー構成パターンを使用)
```

## Usage

Claude Code の会話で以下のように呼び出します:

```
/team-review                      # 未コミット変更をチームレビュー
/team-review src/MyModule/        # 特定ディレクトリをレビュー
/self-review                      # セルフレビュー
/team-investigate ログイン後に画面が固まる  # 根本原因の調査
/team-apply my-feature            # OpenSpec change をチーム実装
/openspec-review-pipeline my-feature  # ドキュメント一式をパイプラインレビュー
```

## Customization

### レビュアーの追加・変更

`team-review.md` の「レビュアーの選出」セクションでレビュアーの名前・専門領域・選出基準を編集できます。プロジェクト固有の専門家（例: database, accessibility, i18n）を追加することも可能です。

### レビュー基準の調整

`self-review.md` の「Review against checklist」セクションでレビュー観点をカスタマイズできます。

## License

MIT
