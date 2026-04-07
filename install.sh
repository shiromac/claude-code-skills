#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/youfo/claude-code-skills.git"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Downloading claude-code-skills..."
git clone --depth 1 --quiet "$REPO" "$TMPDIR/repo"

mkdir -p .claude/skills .claude/commands

cp -r "$TMPDIR/repo/.claude/skills/"* .claude/skills/
cp -r "$TMPDIR/repo/.claude/commands/"* .claude/commands/

echo ""
echo "Installed:"
echo "  .claude/skills/openspec-review-pipeline/SKILL.md"
echo "  .claude/skills/team-apply/SKILL.md"
echo "  .claude/commands/team-review.md"
echo "  .claude/commands/self-review.md"
echo ""
echo "Done! Use /team-review, /self-review, /team-apply, or /openspec-review-pipeline in Claude Code."
