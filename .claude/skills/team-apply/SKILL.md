---
name: team-apply
description: "Implement tasks as a team with a leader, implementer(s), and multiple specialist reviewers. The leader coordinates without implementing, reviews progress, and ensures overall direction is correct."
maxTurns: 100
license: MIT
metadata:
  author: vibe
  version: "2.0"
---

# Team Apply

Leader-driven team implementation. The leader never writes code — they coordinate, verify direction, and report. Implementer(s) do the work autonomously. Multiple specialist reviewers do batch reviews at natural breakpoints, each from their own perspective.

**Input**: Whatever the user provides — an OpenSpec change name, a task list, a description of work. If ambiguous, ask.

## Step 1: Input parsing and task list

### 1-1. Determine the work

Parse `$ARGUMENTS` and conversation context to understand what needs to be done.

- **OpenSpec change name** (e.g., "sakimitama-mood-config"): Read `openspec/changes/<name>/tasks.md` and context files (proposal, design, specs)
- **Direct task list**: Use as-is
- **Vague description**: Break it down into concrete tasks yourself, then confirm with the user before proceeding

### 1-2. Define the Outcome Statement (mandatory)

Before building the task list, the leader **must** formulate and write down the **Outcome Statement** — a single document that anchors ALL subsequent work:

```
## Outcome Statement

**課題 (Challenge)**: {ユーザーまたはシステムが直面している問題。タスクではなく問題を書く}
**目的 (Purpose)**: {この課題が解決されると何が可能になるか}
**成功条件 (Success Criteria)**: {課題が解決されたことをどう確認するか — 観察可能な振る舞いで記述}
**スコープ境界 (Out of Scope)**: {明示的にやらないこと — implementer の脱線防止}
```

**Rules:**
- 課題は「ユーザーが〜できない」「システムが〜しない」の形式。「XxxViewModel を修正する」はタスクであり課題ではない
- 成功条件は実行して確認できるもの（「コードが存在する」ではなく「ユーザーが○○できる」）
- スコープ境界は最低1つ記述する。implementer は明示的に除外された作業に手を出してはならない
- **課題や目的が入力から明確に読み取れない場合は、推測せずユーザーに確認する**

This Outcome Statement is included in EVERY communication to implementers and reviewers.

### 1-3. Build the task list

Create an internal task list with statuses:

```
pending     → not started
in_progress → implementer working on it
review      → waiting for batch review
fix         → review found issues, needs fixing
done        → reviewed and approved
```

**BDD test injection (OpenSpec change only):**

When the input is an OpenSpec change, check tasks.md for Group 0 "BDD integration tests" **before building the internal task list.** If Group 0 is missing:

1. Add Group 0 at the top of tasks.md:
   ```markdown
   ## 0. BDD integration tests (create before implementation, verify Red)
   - [ ] 0.1 Generate BDD integration tests from all spec scenarios (leader runs `/bdd-test` skill)
   - [ ] 0.2 Verify all tests are Red (failing) with `dotnet test`
   ```
2. Then build the internal task list from the updated tasks.md (Group 0 included from the start).

This ensures the task list displayed to the user always includes BDD tests as the first group.

### 1-4. Gather context

Read all relevant context files so you (the leader) understand the full picture:
- OpenSpec artifacts (proposal, design, specs) if applicable
- Relevant source files referenced in tasks
- Any existing code patterns the implementation should follow

Display the task list and context summary to the user. **Proceed to implementation without asking for confirmation.** Only pause for confirmation if the user explicitly requests it.

### 1-5. Execute BDD tests (mandatory, before implementation)

When implementing an OpenSpec change, **execute Group 0 before spawning implementers.**

1. The leader runs `/bdd-test` skill to generate BDD integration tests from the specs
2. Verify all tests are Red (failing) with `dotnet test`
3. Mark Group 0 tasks as `done` in internal tracking

Group 0 is handled by the leader (implementer subagents cannot invoke skills).

If not an OpenSpec change: skip this step.

**For OpenSpec changes, this step must not be skipped.** Do not begin implementation without BDD tests.

## Step 2: Team creation

### 2-1. TeamCreate

```
team_name: "apply-{timestamp}"
description: "Team apply: {work summary}"
```

### 2-2. Spawn implementers (parallel implementation)

**Analyze dependencies and identify tasks that can run in parallel.**

1. Read the task list and build a dependency graph:
   - Tasks touching the same files → sequential
   - Tasks touching different files/modules → parallelizable
   - Tasks explicitly depending on output of prior tasks → sequential
2. **Spawn one implementer per parallelizable task group** (up to 3). If all tasks are sequential, spawn a single implementer with all tasks.
3. Assign sequentially-dependent tasks to the same implementer in order

Spawn each implementer via Agent (subagent_type: "general-purpose") with `team_name` and `name: "implementer-{N}"`.

#### モデル選択ガイドライン (implementer)

implementer は **opus** を使用する。コード実装は複雑な推論、設計判断、既存コードとの整合性確保が必要であり、安いモデルでは品質が低下するリスクが高い。

**Important**: When multiple independent tasks exist, **batch all Agent tool calls into a single message for parallel spawn**. Sequential spawning is prohibited.

Prompt:

```
You are **implementer-{N}** in a team-apply session. You write code autonomously.

## Outcome Statement (MOST IMPORTANT — read before every task)

{Outcome Statement from Step 1-2 — 課題, 目的, 成功条件, スコープ境界}

Your work is only valuable if it moves the team toward the Success Criteria above.
If you find yourself doing something that does NOT contribute to the Success Criteria, STOP and report to the leader.

## Context

{context summary — what the overall work is about, design decisions, relevant patterns}

## Your assigned tasks

{full list of tasks assigned to this implementer}

## Communication protocol

### Autonomous execution mode
- Implement assigned tasks **sequentially from top to bottom, without waiting for approval**
- Move to the next task immediately after completing each one (do not wait for leader instructions)
- Send a **single completion report** after all tasks are done

### Direction check (mandatory, after each task)
After completing each task, explicitly answer the following three questions before moving to the next task:
1. Does my change contribute to the **成功条件**?
2. Did I stay within the **スコープ境界**?
3. Would someone reviewing this change say "yes, this addresses the 課題"?
If the answer to any of these is NO or UNCERTAIN, report to the leader before continuing.

### When to report to the leader (exceptions only)
Report to the leader via SendMessage and wait for guidance ONLY when:
- You discover a critical issue requiring a design decision (approach fundamentally changes)
- You need to modify files owned by another implementer (conflict avoidance)
- A task turns out to be infeasible
- **Your direction check reveals uncertainty about whether your work addresses the 課題**

### Completion report (after all tasks are done)
After completing all tasks, send the leader a SendMessage with:
- Changed files and change summary per task
- **For each task: one sentence explaining how it contributes to the 成功条件**
- Any deviations from expectations and why
- Concerns if any

### General rules
- Implement ONLY the assigned tasks
- Do not refactor, improve, or clean up code beyond the task scope
- **Do not work on anything listed in スコープ境界 (Out of Scope)**
- If the leader sends a correction, adjust immediately
- If the leader sends a shutdown message, finish your current action and stop
- Keep changes minimal and focused
- Run `dotnet build` after changes to verify compilation when applicable
```

### 2-3. Select reviewers

Based on the target content, select reviewers from the following pool.

#### モデル選択ガイドライン (reviewer)

全レビュアーは **sonnet** を使用する。レビューはコードの読解とパターン照合が主であり、sonnet で十分な品質が得られる。spawn 時に `model: "sonnet"` を指定すること。

**例外: architect レビュアーは opus を使用する** — システム全体を俯瞰するメタ的推論が必要なため。

#### Core members (always included)

| Name | Expertise |
|------|-----------|
| **architect** | Separation of concerns, dependency direction, layer boundaries, SOLID principles, class/module design |
| **security** | Injection (SQL, command, XSS), secrets management, auth/authz, unsafe deserialization, path traversal |
| **spec-conformance** | Divergence from use cases, requirements coverage, inconsistencies with specified behavior |
| **proposal-consistency** | proposal を正として課題・目的・成功条件・スコープ境界との整合性を検証し、ズレを検出 |

#### Additional members (selected based on content)

| Name | Expertise | Selection criteria |
|------|-----------|-------------------|
| **concurrency** | Thread safety, race conditions, deadlock, async/await, lock strategy | Code contains async, lock, thread, Task, ConcurrentXxx, etc. |
| **performance** | Computational complexity, allocations, hot paths, caching, excessive LINQ | Code contains loops, bulk data operations, frequently-called paths |
| **error-handling** | Boundary values, exception propagation, recovery, failure modes, error message quality | Code contains try/catch, Result types, error boundaries |
| **readability** | Naming, complexity (cognitive/cyclomatic), pattern consistency, clarity of intent | Large changes, new file additions, refactoring |

#### Selection rules

1. **Core 4 are always included**
2. Read the task content and target code, select additional members matching the criteria
3. When in doubt, **include them** (coverage is important)

### 2-4. Spawn reviewers

Spawn each selected reviewer via Agent (subagent_type: "general-purpose"). **Always specify `team_name` and `name` parameters** to assign them to the team.

Pass the following prompt to each reviewer:

~~~
You are a **reviewer** in a team-apply session. Your role is **{role_name}** — your expertise is {expertise}.

## Context

{context summary}

## Your process

When the leader sends you a review batch:

1. **Requirements alignment check (FIRST)** — Before looking at code quality, read the Outcome Statement included in the batch. For each task, ask: "Does this change contribute to the 成功条件?" If a change does NOT address the stated requirements, mark it **WRONG_DIRECTION** immediately — do not review its code quality.
2. **Read the actual code changes** — `git diff` for the files mentioned, plus surrounding context
3. **Focus on your area of expertise.** You are {role_name}. Review deeply from your perspective. Do not try to cover everything — your teammates cover other perspectives.
4. **Consult teammates when needed.** If you find something that crosses into another reviewer's domain, or want a second opinion, send them a message using SendMessage with their name. Your teammates are: {teammate_names}.
5. **Produce a review report**

## Review report format

For each task in the batch:

```
### Task: {task description}
**Requirements alignment**: YES / PARTIAL / NO (with explanation)
**Verdict**: PASS / NEEDS_FIX / CRITICAL / WRONG_DIRECTION / PROPOSAL_MISMATCH

If WRONG_DIRECTION:
- What was implemented vs. what the 成功条件 requires
- This takes priority over all other findings

If PROPOSAL_MISMATCH:
- Which proposal clause is violated (課題 / 目的 / 成功条件 / スコープ境界)
- What was implemented vs. what proposal requires
- Required correction to restore consistency

If NEEDS_FIX or CRITICAL:
- **File:Line** — issue description
- **Severity**: critical / warning / nit
- **Suggestion**: concrete fix or alternative
```

Summary at the end:
- Total tasks reviewed
- PASS / NEEDS_FIX / CRITICAL / WRONG_DIRECTION / PROPOSAL_MISMATCH counts
- If all PASS: "Batch approved from {role_name} perspective"
- **If any WRONG_DIRECTION or PROPOSAL_MISMATCH: flag prominently — this is the highest priority issue**

Send the report to the leader via SendMessage.

## Important
- Always read the actual code, not just the completion reports
- Be specific: file paths, line numbers, concrete fixes
- CRITICAL means "this will break something or is a security issue" — use sparingly
- If the leader sends a shutdown message, finish your current review and stop
~~~

## Step 3: Implementation loop

**Implementers execute all tasks autonomously. The leader waits for completion reports and intervenes only on exceptions.**

### 3-1. Execution start

After spawning all implementers in parallel, **the leader waits for completion reports from all implementers.**

- Implementers execute all assigned tasks autonomously without approval
- The leader intervenes only when an implementer reports an exception (design issue, conflict, infeasibility)
- **No progress checks or interim reports to the user** — report in bulk when everything is complete

### 3-2. Exception handling

When an implementer reports an exception:

1. **Assess the problem** — Does it require a design change? Does it affect other implementers?
2. **Decide** — Continue, change approach, or pause
3. **Respond with clear instructions**

If other implementers are affected, notify them via SendMessage as well.

### 3-3. Completion handling — Direction Validation Gate

When an implementer sends a completion report, the leader performs a **direction validation** before proceeding:

1. **Read the actual changes** — `git diff` for the files the implementer reports changing. Do not trust the report alone.
2. **Requirements-first check** — For each completed task, answer:
   - Does this change address the **課題** stated in the Outcome Statement?
   - Does this change move toward the **成功条件**?
   - Does this change stay within the **スコープ境界**?
3. **Judgment**:
   - **Aligned**: Record tasks as `review` status, proceed
   - **Partially aligned**: Send the implementer a correction message specifying exactly what is off-track and what the correct direction is. Reference the Outcome Statement. Wait for revised completion.
   - **Completely off-track**: Send the implementer a STOP + redirect message. Re-assign the task with clearer instructions that explicitly reference the Outcome Statement. This is the leader's failure, not the implementer's — it means the initial instructions were unclear.

4. **Wait for all implementers to pass validation** — Once everyone is validated and aligned, send review batch (Step 3-4)

**This gate is mandatory.** Do not send code to reviewers until the leader has verified direction alignment. Reviewers check code quality; the leader checks direction. These are different responsibilities.

### 3-4. Sending review batches

When sending to **all reviewers** (send the same batch to each):

```
## Review batch

### Outcome Statement (review against this)
{Outcome Statement from Step 1-2 — 課題, 目的, 成功条件, スコープ境界}

### Tasks to review:
{list of tasks completed since last review}

### Files changed:
{summary of files modified per task}

### Context:
{any design context the reviewer needs}

Please review from your perspective. FIRST check whether the changes address the 成功条件, THEN check code quality.
```

### 3-5. Handling review results

**Wait for reports from ALL reviewers before making a judgment.** Do not judge based on partial reports.

Once all reports are collected:

1. **Validity check** — For each reported issue, the leader re-reads the actual code and judges:
   - Valid — A real problem. Must be addressed
   - False positive — Not actually a problem when code/context is read correctly. Explain in one sentence
   - Partially valid — Direction is correct but severity or content needs adjustment

2. **Integrated table** — Deduplicate and merge all findings into a single table:

```
| # | Reviewer | Severity | Location | Finding | Validity | Reason |
|---|----------|----------|----------|---------|----------|--------|
```

3. **Judgment**:
   - **0 valid findings**: Mark tasks as `done`, write review markers (Step 3-6)
   - **WRONG_DIRECTION (valid)**: This is the highest priority. Stop all other review processing. Re-read the Outcome Statement, understand where the implementer went wrong, and send a redirect message with explicit instructions referencing the 成功条件. Do NOT let WRONG_DIRECTION code proceed to fix — it needs to be re-implemented from the correct direction.
   - **PROPOSAL_MISMATCH (valid)**: This is the highest priority (same level as WRONG_DIRECTION). Stop all other review processing. Re-open `proposal.md` and identify the exact violated clause, then send a redirect message that names the clause and required correction. Do NOT process as incremental fix only — re-align implementation direction first.
   - **NEEDS_FIX (valid)**: Add fix items to the fix queue, mark affected tasks as `fix`
   - **CRITICAL (valid)**: Flag for immediate attention. If implementer is working, send interrupt with the critical issue. CRITICAL items follow the same fix-queue flow as NEEDS_FIX but take priority — they must be fixed before any NEEDS_FIX items.

For NEEDS_FIX items, **batch all fix tasks and assign to the implementer** (if multiple implementers, assign to the original task owner):

```
## Fix required: {task descriptions}

### Review findings:
{integrated findings from multiple reviewers — include reviewer name and specifics}

Fix all issues and send a completion report. No interim check-ins needed.
```

The implementer executes fixes autonomously and sends only a completion report.

### 3-6. Writing review markers and updating checkboxes

When a batch passes review:

**a) Update tasks.md checkboxes (mandatory).** Change `- [ ]` to `- [x]` for all completed tasks. This is the leader's responsibility, not the implementer's. Review pass = task complete, so update immediately when the review passes. The `openspec` CLI reads these checkboxes to track progress — leaving them unchecked blocks downstream operations like archiving.

**b) Write review markers to tasks.md frontmatter.** For each approved task that has a corresponding task_id:

For each approved task that has a corresponding task_id:

1. Stage changes and get tree hash:
   ```bash
   git add -A && git write-tree
   ```

2. Edit tool で `tasks.md` のフロントマターに `reviewed_tasks` フィールドを追加・更新する:
   ```yaml
   ---
   # ... 既存のフロントマターフィールド ...
   reviewed_tasks:
     "1.1": { hash: "<tree_hash>", at: "<ISO 8601>" }
     "2.1": { hash: "<tree_hash>", at: "<ISO 8601>" }
   ---
   ```

3. `reviewed_tasks` が既に存在する場合は、新しいタスクエントリを追加（既存エントリは保持）する。同じ task_id が既にある場合は上書きする。

If the work is not associated with an openspec change (tasks.md がない場合), skip marker writing.

### 3-7. Post-implementation verification (mandatory for OpenSpec changes)

After all tasks pass review (marked `done`), the leader runs BDD tests to verify Green:

1. `dotnet test` — run all BDD integration tests
2. **All Green**: Proceed to Step 4
3. **Any Red**: Identify which tests fail, create fix tasks referencing the failing test and the 成功条件, assign to the appropriate implementer. Return to the implementation loop (Step 3-1).

This step is the final gate before completion. Review approval does not guarantee correctness — only running the tests does.

If not an OpenSpec change: skip this step (no BDD tests exist).

### 3-8. WPF 実機確認ゲート (WPF 変更を含む場合は必須)

変更対象に WPF の View/ViewModel/Control が含まれる場合、BDD テスト通過後に WPF 実機確認を行う:

1. **変更に WPF ファイル（`src/LLMGameApp/`）が含まれるか確認する**。含まれない場合はスキップ。
2. **実機確認が必要な場合**: ユーザーに WPF アプリでの確認を依頼する。確認手順を明示する（何を操作し、何を確認するか）。
3. **確認結果が NG の場合**: 原因調査 → 修正 → 再確認のループに入る。BDD テストが Green でも WPF 実機で NG なら完了としない。

> 教訓: BDD テストはモック経由で実行され、WPF 固有の動作（DependencyProperty バインディング順序、ObservableCollection の UI 更新タイミング、タイマー駆動のアニメーション）を再現しない。BDD 9/9 Green でも WPF 実機でデグレードしていた事例がある。

## Step 4: Completion

When all tasks are `done` (implemented + review passed + BDD tests passed + WPF 実機確認 passed):

### 4-1. Shutdown team

Send shutdown messages to all implementers and all reviewers.

### 4-2. Final report to user

```
## Team Apply Complete

**Work:** {description}
**Tasks:** {N}/{N} complete

### Completed tasks
- [x] Task 1
- [x] Task 2
...

### Review summary
- Batches reviewed: {N}
- First-pass approvals: {N}
- Required fixes: {N}

### Files modified
{list of all files changed}

{If OpenSpec change: suggest marking tasks in tasks.md and/or archiving}
```

## Guardrails

### Leadership principles (direction control)
- **State the outcome, not just the task list.** Every delegation must include the Outcome Statement (課題, 目的, 成功条件, スコープ境界). An implementer who only knows "what to do" but not "why" will drift.
- **Validate direction at every boundary.** Never let a task's output flow to reviewers without the leader checking it against the Outcome Statement. Reviewers check code quality; the leader checks direction. These are different jobs.
- **Catch wrong-direction early, catch style issues late.** Requirements alignment is the first gate; code quality is the second. A polished implementation that solves the wrong problem is worse than a rough implementation that solves the right one.
- **If an implementer drifts, it's the leader's fault.** The leader's instructions were unclear. Fix the instructions, not the implementer.
- **Context is the leader's advantage.** The leader sees the full picture. Use it to catch direction issues early, before they compound.

### Execution rules
- **Leader never writes code.** Not even "just this one small fix." All code changes go through the implementer.
- **Implementers execute autonomously.** No pre-approval required. They report to the leader only on exceptions. The leader ensures quality through review results.
- **Don't rubber-stamp reviews.** Actually verify the code before judging review findings.
- **Fix queue takes priority over new tasks.** Address review findings before moving forward.
- **WRONG_DIRECTION takes priority over everything.** Do not let an implementer continue fixing code quality issues in code that solves the wrong problem.
- **Critical issues interrupt.** Don't let the implementer pile up more changes on top of a critical problem.
- **Minimize user confirmation.** Proceed to implementation without confirmation after displaying the task list. No interim progress reports needed. Report in bulk when everything is complete.
- **Update tasks.md checkboxes immediately.** After review passes, the leader updates `- [ ]` → `- [x]` in Step 3-6. Never leave checkboxes unchecked in the completion report. The `openspec` CLI tracks progress via these checkboxes.
- **Spawn implementers in parallel.** When independent tasks exist, spawn multiple implementers in a single message. Sequential spawning is prohibited.
- **Use `mode: "auto"` for implementers.** When spawning implementers via the Agent tool, specify `mode: "auto"` to bypass approval prompts. Reviewers are read-only (git diff, file reads) so default mode is fine for them.
