#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/shiromac/claude-code-skills.git"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Downloading claude-code-skills..."
git clone --depth 1 --quiet "$REPO" "$TMPDIR/repo"

mkdir -p .claude/skills .claude/commands

mkdir -p .claude/skills/openspec-review-pipeline .claude/skills/team-apply

cp "$TMPDIR/repo/.claude/skills/openspec-review-pipeline/SKILL.md" .claude/skills/openspec-review-pipeline/SKILL.md
cp "$TMPDIR/repo/.claude/skills/team-apply/SKILL.md" .claude/skills/team-apply/SKILL.md
cp "$TMPDIR/repo/.claude/commands/self-review.md" .claude/commands/self-review.md
cp "$TMPDIR/repo/.claude/commands/team-review.md" .claude/commands/team-review.md
cp "$TMPDIR/repo/.claude/commands/team-investigate.md" .claude/commands/team-investigate.md

echo ""
echo "Installed:"
echo "  .claude/skills/openspec-review-pipeline/SKILL.md"
echo "  .claude/skills/team-apply/SKILL.md"
echo "  .claude/commands/team-review.md"
echo "  .claude/commands/self-review.md"
echo "  .claude/commands/team-investigate.md"
echo ""
echo "Done! Use /team-review, /self-review, /team-investigate, /team-apply, or /openspec-review-pipeline in Claude Code."
