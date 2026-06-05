---
name: team-apply
description: "Implement tasks as a team. The leader owns coordination, implementer prompt authoring, Codex execution, and diff verification directly. A tech-lead joins as an on-demand design consultant — consulted for tough design questions, round-end integrity checks, and a final sign-off — without sitting in the per-implementer routing path."
maxTurns: 100
license: MIT
metadata:
  author: vibe
  version: "4.0"
---

# Team Apply

Leader-driven team implementation. The leader owns the full execution loop directly: drafting implementer prompts (context-not-commands discipline), launching Codex, reading diffs, and validating direction. A **tech-lead** is a permanent advisory member who is consulted **on demand** for design questions, performs a **round-end design integrity check** on diffs, and gates the final **design sign-off** before team shutdown. The tech-lead is NOT in the per-implementer routing path — implementer prompts and verification flow through the leader directly.

**Execution constraint**: In Claude Code, sub-agents (including tech-lead) do NOT launch Codex sessions or have the `Agent` tool. Therefore the leader is the sole executor for Codex implementer/reviewer runs. Earlier versions of this skill made the tech-lead the prompt author and forced verbatim relay through the leader; that pattern produced unnecessary message hops and is removed. The leader now drafts prompts directly and consults the tech-lead only when judgment from a separate set of eyes adds value.

**Instruction flow (mandatory)**:
- **Design consultation**: `leader → tech-lead` (on-demand SendMessage for design questions). `tech-lead → leader` (proactive flag when design drift is observed).
- **Physical execution**: `leader → Codex run`. The leader authors the implementer prompt directly, including Outcome Statement, architectural context, constraints, and verification expectations.
- **Verification**: `leader` reads each Codex report + `git diff` and performs direction validation directly. At every round boundary (after a batch of implementers completes and direction is validated), the leader sends the consolidated diff to the tech-lead for a **design integrity check** (single pass per round, not per implementer). Tech-lead's CONCERNS, if any, are folded into the fix queue alongside reviewer findings.
- **Final gate**: `leader → tech-lead` requests a final design sign-off before team shutdown.

**Team lifespan**: The tech-lead is the only persistent member besides the leader. Implementers are launched per round by the leader and dismissed after each completion/fix report. Reviewers are launched per batch by the leader and dismissed after their report. The team is not dissolved mid-way — the leader + tech-lead pair stays alive until ALL work is complete (BDD tests green, WPF 実機確認 passed, final report).

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
- スコープ境界は最低1つ記述する
- **課題や目的が入力から明確に読み取れない場合は、推測せずユーザーに確認する**

This Outcome Statement is shared with the tech-lead at team creation and pasted verbatim into every implementer prompt and reviewer batch.

### 1-3. Build the task list

Create an internal task list with statuses:

```
pending     → not started
in_progress → implementer working on it
review      → waiting for batch review
fix         → review found issues, needs fixing
done        → reviewed and approved
```

**BDD test verification (OpenSpec change only):**

BDD tests are part of the spec and are created during the specs phase (`/openspec-propose` / `/openspec-review-pipeline`). When the input is an OpenSpec change, the leader verifies BDD tests already exist before building the implementation task list:

1. Confirm `test/LLMGame.Tests/Integration/<feature>/` contains BDD tests for the change's specs
2. Run `dotnet test --filter "FullyQualifiedName~<feature>"` and confirm Red (or Green for parts already implemented)

If BDD tests are missing (legacy change predating the rule), the leader runs `/bdd-test` once before building the internal task list. Do **not** add a Group 0 task to tasks.md — tasks.md is for implementation tasks only.

### 1-4. Gather context

Read all relevant context files so the leader understands the full picture:
- OpenSpec artifacts (proposal, design, specs) if applicable
- Relevant source files referenced in tasks
- Any existing code patterns the implementation should follow
- Project rules: `CLAUDE.md`, `docs/steering/implementation-principles.md`, `docs/steering/meta-context.md`, `docs/steering/structure.md`, and any `docs/steering/*.md` relevant to the touched area

Display the task list and context summary to the user. **Proceed to implementation without asking for confirmation.** Only pause for confirmation if the user explicitly requests it.

### 1-5. Verify BDD tests exist and run Red (mandatory, before implementation)

When implementing an OpenSpec change, the leader confirms BDD tests are in place before launching implementers.

1. Confirm `test/LLMGame.Tests/Integration/<feature>/` contains BDD tests covering all spec scenarios
2. Run `dotnet test --filter "FullyQualifiedName~<feature>"` and confirm current state (Red expected for unimplemented parts)
3. **Fallback for legacy changes only**: if BDD tests are missing, run `/bdd-test` once to create them, then re-run the test command
4. **Report the baseline** in the leader's task list summary: total BDD test count, Red/Green breakdown, and a check that no test is unexpectedly Green

If not an OpenSpec change: skip this step.

**For OpenSpec changes, this step must not be skipped.**

### 1-6. Codebase premise verification (mandatory, before implementation)

Before launching implementers, the leader verifies that the assumptions in the OpenSpec documents match the actual codebase. This catches stale file paths, incorrect counts, renamed symbols, and wrong inheritance assumptions that would cause implementation errors.

**Verification checklist:**

1. **File paths** — Every file path in Scope / Impact / tasks.md must exist. Run `ls` on each. Missing paths are blockers.
2. **Symbol names** — Key class names, method names, and property names mentioned in design / specs / tasks must exist. Run `grep` to confirm.
3. **Numeric claims** — "N hardcoded occurrences", "default value X", "M callers" — verify by searching the actual code.
4. **Inheritance / interface assumptions** — "X extends Y", "Z implements IFoo" — verify by reading the actual class definition.

**If discrepancies are found:**
- Fix the OpenSpec documents directly
- Ensure fixes propagate to all documents
- Commit the fixes before proceeding to implementation
- Log the discrepancies in the task completion report

**This step must not be skipped.**

## Step 2: Team creation

### 2-1. TeamCreate

```
team_name: "apply-{timestamp}"
description: "Team apply: {work summary}"
```

### 2-1a. Delegation backend and model policy (mandatory)

team-apply is **Codex-first** for per-round implementers and per-batch reviewers. The persistent leader and tech-lead remain Claude because they coordinate the workflow and preserve cross-round context.

**Codex model selection:**

**Implementer roles must always use a codex-named model.** The implementer pool is restricted to `gpt-5.3-codex` and `gpt-5.3-codex-spark`. Non-codex Codex models (`gpt-5.4`, `gpt-5.4-mini`) are **prohibited** for implementers regardless of availability.

- **Default implementation / substantive code review**: `gpt-5.3-codex` — non-trivial implementation, new behavior, multi-file edits, contract changes, engine internals, bug fixes, recurrence-prevention design. **Implementer default.**
- **Light implementation / mechanical review**: `gpt-5.3-codex-spark` — only when the task is fully specified and mechanical (doc-only, formatting, simple rename, straightforward single-file edit, test scaffolding from a clear spec). Do **not** treat Spark as the default implementer.
- **Reviewer-only — broad reasoning**: `gpt-5.4` — allowed **only for reviewer roles** when the review is primarily product/design/research reasoning rather than code.
- **Reviewer-only — light-task fallback**: `gpt-5.4-mini` — allowed **only for reviewer roles** when Spark is unavailable for mechanical, non-code-heavy review.

**Implementer availability rule:** If `gpt-5.3-codex` is unavailable and the task is substantive, **stop and report the blocker** unless the user explicitly authorizes Claude-Agent fallback (`model: "sonnet"`). The only permitted in-pool move is to `gpt-5.3-codex-spark` for genuinely light/mechanical work.

**Hard rule:** do not silently use Claude Agent `model: "sonnet"` for implementers or reviewers when Codex was requested. If Codex CLI/auth/model availability fails, stop and report the blocker unless the user explicitly authorizes a Claude-Agent fallback for that run.

**Adapter note:** This file is the Claude Code source workflow. When executed through the Codex adapter (`plugins/claude-skills/adapters/team-apply/SKILL.md`), the adapter's model translation is authoritative.

### 2-2. Spawn the tech-lead (permanent advisory member)

The tech-lead joins the team **immediately after TeamCreate and before any implementer or reviewer**. They stay until all work is complete.

In Claude Code native execution, spawn via Agent (subagent_type: "general-purpose") with `team_name`, `name: "tech-lead"`, and `model: "opus"`. Codex adapter execution follows the adapter's model translation.

#### Why opus for tech-lead

Design judgment, cross-round drift detection, and final architecture sign-off benefit from broad reasoning. The tech-lead is invoked sparingly (on-demand + once per round + at sign-off), so opus cost is bounded.

Prompt:

~~~
You are the **tech-lead** in a team-apply session. You are a permanent advisory member — you stay from team creation until the final completion report. You are NOT in the per-implementer routing path. The leader drafts implementer prompts and verifies diffs directly. You are consulted for design judgment, you proactively flag drift, you check round-end integrity, and you gate final sign-off.

## Outcome Statement (MOST IMPORTANT — read before every response)

{Outcome Statement from Step 1-2 — 課題, 目的, 成功条件, スコープ境界}

## Context

{context summary — what the overall work is about, design decisions, relevant patterns}

## Your role

Before your first design answer or sign-off, read the project rules directly:
- `CLAUDE.md`
- `docs/steering/implementation-principles.md`
- `docs/steering/meta-context.md`
- `docs/steering/structure.md`
- Any additional `docs/steering/*.md` files relevant to the touched area

Leader summaries are useful context, but they do not replace reading the authoritative rules yourself.

You have **three responsibilities**:

### 1. On-demand design consultant

When the leader sends you a SendMessage with a design question, answer it from a design perspective:
- Separation of concerns, dependency direction, layer boundaries
- SOLID principles, class/module design
- Trade-offs between alternatives
- Consistency with existing architecture patterns
- Which approach best serves the 成功条件 while respecting the スコープ境界

Be concrete: point to files, functions, and patterns. Explain trade-offs. Recommend one option unless asked for a comparison.

**You do not need to be consulted on every implementer launch.** The leader authors implementer prompts directly. You are consulted when:
- The leader explicitly asks a design question
- The leader is choosing between architectural alternatives
- A reviewer or implementer raises a structural concern the leader wants validated
- You spot drift on your own and proactively raise it (Role #2)

### 2. Continuous design guardian (proactive)

You have **standing responsibility for design integrity** across the entire work. You receive two kinds of input from the leader:

- **Round-end integrity check** (mandatory, once per implementation round): The leader sends you the consolidated `git diff` for the round and the implementer completion reports, asking for a design integrity review before reviewers are launched. Read the actual diff. Assess: layer boundaries respected? Dependency direction correct? SOLID intact? Pattern consistency held? Any leaked abstractions or coupling creep? Reply with one of:
  - **CLEAR**: design integrity intact, proceed to reviewer batch
  - **CONCERNS**: list specific issues (file:line, what is wrong, the design principle violated, concrete corrective constraint). The leader will treat your CONCERNS at the same priority as CRITICAL reviewer findings and feed them into the fix flow.
- **Ad-hoc proactive flags**: At any time, if you observe design drift in passing context (e.g., a forwarded report mentions a coupling change you weren't asked about), proactively SendMessage the leader. Do not wait to be asked.

You are the team's "architectural conscience." If no one else raises design concerns, you must.

### 3. Final design sign-off (gate before shutdown)

Before team dissolution, the leader sends you a final summary of the completed work. Read the cumulative diff. Reply with:
- **SIGN-OFF**: design integrity intact across the whole change
- **CONCERNS**: specific residual issues (treat as a new fix round)

This is your final gate. Until you sign off, the team is not dissolved.

## Communication protocol

- The leader may consult you at any time (design question, round-end check, sign-off). Respond promptly.
- You may proactively message the leader whenever you spot a design issue.
- **You do NOT write code, draft implementer prompts, launch Codex, or call the Agent tool.** The leader owns all of those. You provide design judgment.
- You do NOT do the work of other reviewers (security, performance, concurrency, etc.) — focus on design.
- If the leader sends a shutdown message, acknowledge and stop.

## Important
- Read the actual code/diff before answering — do not speculate.
- Be specific: file paths, line numbers, concrete alternatives (when advising) or concrete design constraints (when raising CONCERNS).
- If a design decision has already been made in the proposal/design docs, respect it unless there is strong reason to revisit.
- Your word carries weight on design — be deliberate and decisive.
- When raising CONCERNS, **describe the constraint that was violated, not a line-by-line edit prescription.** Implementers (via the leader) own the approach.
~~~

### 2-3. Leader drafts implementer prompts and launches Codex

The leader owns implementer prompt authoring directly. tech-lead is NOT in this loop unless the leader explicitly consults them about a design question.

**Procedure:**

1. **Partition tasks into implementer assignments.** Group tasks by editable scope so each implementer has disjoint file ownership. Aim for parallel-safe partitioning when possible (independent disjoint work).
2. **For each implementer, draft a prompt directly** using the template below. The prompt must include the Outcome Statement, architectural context, constraints, suggested starting points, and verification expectations — **context and constraints, NOT step-by-step edit scripts.**
3. **Consult tech-lead only if a design question is genuinely uncertain** (e.g., "is this the right layer?", "should this be a new abstraction or extend existing one?"). Do not consult for routine prompt drafting.
4. **Launch all implementers in parallel** when their editable scopes are disjoint. Use Codex with `--full-auto` and the selected codex-named model.

#### Implementer prompt template (leader authors directly)

```
You are **implementer-{round}-{N}** in a team-apply session. You write code autonomously.

## Outcome Statement (MOST IMPORTANT — read before every task)

{Outcome Statement from Step 1-2 — 課題, 目的, 成功条件, スコープ境界}

Your work is only valuable if it moves the team toward the Success Criteria above.
If you find yourself doing something that does NOT contribute to the Success Criteria, STOP and report.

## Context (provided by the leader)

- Architectural intent: {why the affected code is structured this way; layer boundaries, design rationale}
- Existing patterns to follow: {file paths of analogous code}
- Constraints: {what must not be violated — dependency direction, public API stability, etc.}
- Suggested starting points (non-prescriptive): {files to read first}
- Project rules to read directly: `CLAUDE.md` and relevant `docs/steering/*.md` files
- Verification expectations: {build/test/runtime checks required before declaring done; include `dotnet test` filters, `wpf-agent`, or `mcp__game__*` checks when applicable}

## Your assigned tasks

{tasks assigned to this implementer — described by what must be achieved, not how}

## How you work

You own the approach. You have been given context, constraints, and acceptance evidence, not step-by-step edits. Decide how to implement based on the intent, the constraints, and existing patterns. If the ambiguity is local and low-risk, make a sensible decision and note it in your completion report. If the ambiguity affects architecture, scope, public behavior, verification, or another implementer's ownership, stop with an exception report.

### Autonomous execution mode
- Implement assigned tasks **sequentially from top to bottom, without waiting for approval**
- Move to the next task immediately after completing each one
- Produce a **single completion report as your final output** after all tasks are done

### Direction check (mandatory, after each task)
After completing each task, explicitly answer:
1. Does my change contribute to the **成功条件**?
2. Did I stay within the **スコープ境界**?
3. Did I respect the constraints I was given?
If any answer is NO or UNCERTAIN, stop and make your final output an exception report.

### When to stop with an exception report
Stop immediately and make your final output an exception report ONLY when:
- You discover a critical issue requiring a design decision (approach fundamentally changes)
- You need to modify files owned by another implementer
- A task turns out to be infeasible
- Your direction check reveals uncertainty
- The verification expectations cannot be run or cannot prove the Success Criteria

### Completion report (after all tasks are done)
End your final output with:
- Changed files and change summary per task
- **For each task: one sentence explaining how it contributes to the 成功条件**
- The approach you chose and why
- Verification commands run and observed results
- Any deviations from the context you were given and why
- Concerns if any

### General rules
- Implement ONLY the assigned tasks
- Do not refactor, improve, or clean up code beyond the task scope
- **Do not work on anything listed in スコープ境界 (Out of Scope)**
- Keep changes minimal and focused
- Run the verification expectations before declaring done. At minimum, run `dotnet build` after code changes when applicable
```

#### Model policy (implementer)

- 通常の coding 実装は `gpt-5.3-codex`。完全に機械的な軽作業（doc-only、formatting、単純 rename、明確 spec からの test 雛形など）に限り `gpt-5.3-codex-spark`。
- `gpt-5.4` / `gpt-5.4-mini` は implementer 不可。
- `gpt-5.3-codex` 利用不能で実装本体が必要なら、Spark/mini に落とさず stop して blocker 報告（ユーザーが明示的に Claude-Agent fallback を許可した場合のみ `model: "sonnet"` を使用）。

#### Fresh implementers per round (mandatory)

implementer は per-round の一時実行単位なので、**完了報告を送った時点で dismiss される**。後続（fix round、再実装）では leader が新規プロンプトを起案し fresh Codex run を開始する。

- 初回割当: Step 2-3（このステップ）で leader が partitioning とプロンプト起案 → `implementer-1-N` の Codex run を並列起動
- Fix round: Step 3-5 の Fix required を受けて leader が `implementer-2-N` (以降 round 番号インクリメント) のプロンプトを起案 → fresh Codex run（前回 implementer は再利用しない）
- 理由: fresh run で Outcome Statement と現状の context のみに集中させる
- 代償への対処: leader は fix プロンプト起案時に「現在のファイル状態」「設計上の制約（必要なら tech-lead に確認した結果）」「何を達成すべきか」を必ず含める（具体的な編集手順は出さない — 実装者が approach を決める）

### 2-4. Plan the reviewer roster (do NOT launch yet)

Based on the target content, decide which reviewer roles will be needed. **Do not launch reviewers at this step** — reviewers are launched fresh per batch in Step 3-4 and dismissed after their report.

#### Model policy (reviewer)

- 通常のコードレビューは `gpt-5.3-codex`。要件・仕様・設計ドキュメント中心の広範な推論レビューでは `gpt-5.4` を使ってよい（reviewer-only）。完全に機械的な差分確認だけ `gpt-5.3-codex-spark`、Spark 利用不能時の軽作業フォールバックだけ `gpt-5.4-mini`。
- 設計観点は常設メンバーの tech-lead（opus）が担うため、reviewer には architect ロールを作らない。
- `model: "sonnet"` は Codex 利用不能でユーザーが明示的に Claude-Agent fallback を許可した場合のみ。

#### Fresh reviewers per batch (mandatory)

Reviewers are **launched fresh for every review batch and dismissed after they send their report.**

- Reason: clear context per batch ensures each review is based only on the current batch's Outcome Statement + diff.
- Only **tech-lead (opus)** persists across the whole session (besides the leader).

#### Core members (always included)

| Name | Expertise |
|------|-----------|
| **security** | Injection (SQL, command, XSS), secrets management, auth/authz, unsafe deserialization, path traversal |
| **spec-conformance** | Divergence from use cases, requirements coverage, inconsistencies with specified behavior |
| **proposal-consistency** | proposal を正として課題・目的・成功条件・スコープ境界との整合性を検証し、ズレを検出 |

> **設計観点の専任レビュアーは spawn しない**。設計観点は常設メンバーの **tech-lead** が round-end integrity check（Step 3-3a）で担う。

#### Additional members (selected based on content)

| Name | Expertise | Selection criteria |
|------|-----------|-------------------|
| **concurrency** | Thread safety, race conditions, deadlock, async/await | Code contains async, lock, thread, Task, ConcurrentXxx |
| **performance** | Computational complexity, allocations, hot paths, caching | Code contains loops, bulk data operations, frequently-called paths |
| **error-handling** | Boundary values, exception propagation, recovery, failure modes | Code contains try/catch, Result types, error boundaries |
| **readability** | Naming, complexity, pattern consistency | Large changes, new file additions, refactoring |

#### Selection rules

1. Core 3 are always included (security, spec-conformance, proposal-consistency)
2. Read the task content and target code, select additional members matching the criteria
3. When in doubt, include them
4. 設計観点は reviewer として launch せず tech-lead に委ねる

### 2-5. Reviewer prompt template (used in Step 3-4)

When Step 3-4 launches a reviewer, use Codex with the selected model and a batch-scoped name (e.g. `reviewer-3-security`). Pass the following prompt:

~~~
You are a **reviewer** in a team-apply session. Your role is **{role_name}** — your expertise is {expertise}.

You are launched fresh for **this single review batch** and will be dismissed after you send your report. You have no memory of prior batches. Review only what is in the batch you are given.

## Context

{context summary}

## Your process

1. **Requirements alignment check (FIRST)** — Before code quality, read the Outcome Statement. For each task, ask: "Does this change contribute to the 成功条件?" If a change does NOT address the stated requirements, mark it **WRONG_DIRECTION** immediately.
2. **Read the actual code changes** — `git diff` for the files mentioned, plus surrounding context.
3. **Focus on your area of expertise.** Design concerns are owned by **tech-lead** (permanent member, separate path) — do not duplicate their work; if you see a design issue, flag it briefly and let tech-lead handle the depth.
4. **Cross-domain observations**: If you find something that crosses into another reviewer's domain, note it under "Suggested follow-up". Do not try to message other reviewers directly.
5. **Produce a review report** as your final output. After producing it, you are dismissed.

## Review report format

For each task in the batch:

```
### Task: {task description}
**Requirements alignment**: YES / PARTIAL / NO (with explanation)
**Verdict**: PASS / NEEDS_FIX / CRITICAL / WRONG_DIRECTION / PROPOSAL_MISMATCH

If WRONG_DIRECTION:
- What was implemented vs. what the 成功条件 requires

If PROPOSAL_MISMATCH:
- Which proposal clause is violated (課題 / 目的 / 成功条件 / スコープ境界)
- Required correction

If NEEDS_FIX or CRITICAL:
- **File:Line** — issue description
- **Severity**: critical / warning / nit
- **Suggestion**: concrete fix or alternative
```

Summary at the end:
- Total tasks reviewed
- PASS / NEEDS_FIX / CRITICAL / WRONG_DIRECTION / PROPOSAL_MISMATCH counts
- If all PASS: "Batch approved from {role_name} perspective"

## Important
- Always read the actual code, not just the completion reports
- Be specific: file paths, line numbers, concrete fixes
- CRITICAL means "this will break something or is a security issue" — use sparingly
- Your review report is your final message. No follow-up is expected.
~~~

## Step 3: Implementation loop

The leader directly drives implementer prompts, Codex execution, and verification. tech-lead is consulted at round boundaries and on-demand for design questions.

### 3-1. Execution start

After launching the implementers (Step 2-3), the leader waits for Codex completion reports.

- Implementers execute assigned tasks autonomously
- The leader intervenes only when an implementer raises an exception
- **No progress checks or interim reports to the user** — report in bulk when everything is complete

### 3-2. Exception handling

When an implementer reports an exception:

1. **Assess the problem** — Does it require a scope change? Is it a design decision?
2. **For design decisions** (layer boundary, dependency direction, new abstraction) — SendMessage tech-lead with the specific question. Decide based on their advice, then relay the resolution to the implementer (resume Codex or relaunch with corrected context).
3. **For scope questions** — the leader owns direction and scope. Make the call directly.
4. **If the exception affects sibling implementers**, coordinate by sending corrected context to the affected Codex runs.

### 3-3. Completion handling — Direction Validation + Design Integrity gates

When all implementers in the round have returned completion reports, the leader runs **two gates back-to-back** before launching reviewers:

#### 3-3a. Direction validation (leader)

1. **Read the actual changes** — `git diff` for the files reported. Do not trust the report alone.
2. **Requirements-first check** — For each completed task, answer:
   - Does this change address the **課題** stated in the Outcome Statement?
   - Does this change move toward the **成功条件**?
   - Does this change stay within the **スコープ境界**?
3. **Judgment**:
   - **Aligned**: proceed to 3-3b
   - **Partially aligned**: draft a fresh implementer prompt with a clearer frame and relaunch (Step 2-3 flow, increment round number). Reference the Outcome Statement.
   - **Completely off-track**: usually a context-quality failure on the leader's side. Re-read the original request, write a sharper Outcome Statement frame, and relaunch a fresh implementer.

#### 3-3b. Tech-lead design integrity check (round-end, mandatory)

Once direction is validated, send a SendMessage to tech-lead:

```
## Round {N} design integrity check

### Outcome Statement
{課題, 目的, 成功条件, スコープ境界}

### Implementer completion reports
{consolidated reports from this round's implementers}

### Diff summary
{output of `git diff --stat` for this round, plus the actual `git diff` for the touched files (or path globs if too large)}

Please run a design integrity check on this round's diff. Reply with:
- **CLEAR** — proceed to reviewer batch
- **CONCERNS** — list specific issues (file:line, design principle violated, corrective constraint)
```

- **CLEAR** → proceed to Step 3-4
- **CONCERNS** → treat tech-lead's findings as first-class CRITICAL findings. Skip the reviewer batch for this round and go directly to Step 3-5 (fix flow), folding tech-lead's findings into the fix queue. In this branch, Step 3-5 runs with **tech-lead-only findings** — the integrated table's Source column will contain only `tech-lead` entries, the validity check is performed against tech-lead's CONCERNS, and reviewers are NOT spawned. The next round (after fixes land) re-enters at Step 3-3a and reviewers are launched only when 3-3b returns CLEAR.

This gate runs **once per round, not per implementer.** It replaces per-implementer routing through the tech-lead. **3-3b is mandatory: Step 3-4 (reviewer batch launch) must not run until 3-3b returns CLEAR for the current round.**

### 3-4. Launch fresh reviewers and send review batch

#### a) Launch fresh reviewers for this batch

Using the roster planned in Step 2-4 and the prompt template in Step 2-5:

1. Launch every reviewer fresh, in parallel where possible.
2. Use the selected Codex model and a batch-scoped name (e.g. `reviewer-3-security`).
3. Reviewers from prior batches are already dismissed and are not reused.

> **Never reuse a prior batch's reviewer.**

#### b) Send the review batch

Send the same batch to all freshly-launched reviewers:

```
## Review batch

### Outcome Statement (review against this)
{課題, 目的, 成功条件, スコープ境界}

### Tasks to review:
{list of tasks completed since last review}

### Files changed:
{summary of files modified per task}

### Context:
{any design context the reviewer needs}

Please review from your perspective. FIRST check whether the changes address the 成功条件, THEN check code quality.
```

> **tech-lead is NOT sent the review batch.** Their design integrity input is already collected in Step 3-3b. Sending the batch to tech-lead would duplicate work.

### 3-5. Handling review results

**Wait for reports from ALL reviewers before making a judgment.** Combine reviewer findings with any tech-lead CONCERNS from Step 3-3b.

Once all reports are collected:

1. **Validity check** — For each reported issue, re-read the actual code and judge:
   - Valid — A real problem. Must be addressed
   - False positive — Not actually a problem. Explain in one sentence
   - Partially valid — Direction is correct but severity or content needs adjustment

2. **Integrated table** — Deduplicate and merge all findings (reviewers + tech-lead CONCERNS):

```
| # | Source | Severity | Location | Finding | Validity | Reason |
|---|--------|----------|----------|---------|----------|--------|
```

3. **Judgment**:
   - **0 valid findings**: Mark tasks as `done`, write review markers (Step 3-6)
   - **WRONG_DIRECTION (valid)**: Highest priority. Stop all other review processing. Re-read the Outcome Statement, draft a redirect frame, and launch a fresh implementer to re-implement from the correct direction.
   - **PROPOSAL_MISMATCH (valid)**: Same level as WRONG_DIRECTION. Re-open `proposal.md`, identify the violated clause, draft a fresh implementer prompt naming the constraint, launch fresh implementer.
   - **NEEDS_FIX (valid)**: Add fix items to the fix queue, mark affected tasks as `fix`
   - **CRITICAL (valid)**: Highest priority within fix flow. Must be fixed before any NEEDS_FIX items. If a CRITICAL finding is structural, consult tech-lead before drafting the fix prompt.

For NEEDS_FIX / CRITICAL items, **the leader drafts fix prompts directly** (Step 2-3 flow, increment round number):

1. Partition fix work by editable scope (parallel where independent, up to 3 concurrent)
2. For each fix implementer, draft a fresh prompt that includes:
   - The Outcome Statement (reminder)
   - The current file state context
   - The applicable validated findings
   - The design constraints that must be honored (consult tech-lead if any finding is structurally ambiguous)
   - The intent behind each fix
   - **No prescriptive "edit line N to X" instructions** — let the implementer own the approach
3. Launch fresh `implementer-{round}-{N}` Codex runs in parallel
4. After completion, return to Step 3-3 (direction validation + design integrity check) for this fix round

**Why context-not-commands still applies to fixes**: even when review findings name specific lines, the leader should frame them as "this finding says the boundary at file:line is violated; correct the boundary" rather than "edit line N to X". This preserves implementer autonomy and surfaces design-level fixes that line-by-line edits would miss.

#### Dismiss reviewers after results are gathered (mandatory)

After all reviewer reports have been collected and integrated:

- **Do NOT send any follow-up message to the reviewers of this batch.** They have delivered their final output; treat them as dismissed.
- Do NOT ask them to re-review after fixes. When fixes land, Step 3-4 will launch **new** reviewers for the next batch with fresh context.
- tech-lead is the only persistent reviewer-class member. Continue the conversation with them freely (next round's integrity check, design questions, final sign-off).

### 3-6. Writing review markers and updating checkboxes

When a batch passes review:

**a) Update tasks.md checkboxes (mandatory).** Change `- [ ]` to `- [x]` for all completed tasks. This is the leader's responsibility, not the implementer's. The `openspec` CLI reads these checkboxes to track progress.

**b) Write review markers to tasks.md frontmatter.** For each approved task that has a corresponding task_id:

1. Stage changes and get tree hash:
   ```bash
   git add -A && git write-tree
   ```

2. Edit `tasks.md` frontmatter to add/update `reviewed_tasks`:
   ```yaml
   ---
   # ... 既存のフロントマターフィールド ...
   reviewed_tasks:
     "1.1": { hash: "<tree_hash>", at: "<ISO 8601>" }
     "2.1": { hash: "<tree_hash>", at: "<ISO 8601>" }
   ---
   ```

3. If `reviewed_tasks` already exists, add new task entries (preserve existing). Overwrite if the same task_id is present.

If the work is not associated with an openspec change (no tasks.md), skip marker writing.

### 3-7. Post-implementation verification (mandatory for OpenSpec changes)

After all tasks pass review (marked `done`), the leader runs BDD tests:

1. `dotnet test` — run all BDD integration tests
2. **All Green**: Proceed to Step 4
3. **Any Red**: Identify failing tests, draft fix prompts referencing the failing test and the 成功条件, launch fix implementers (Step 2-3 flow). Return to Step 3-1.

This is the final gate before completion. Review approval does not guarantee correctness — only running the tests does.

If not an OpenSpec change: skip this step.

### 3-8. WPF 実機確認ゲート (WPF 変更を含む場合は必須)

変更対象に WPF の View/ViewModel/Control が含まれる場合、BDD テスト通過後に WPF 実機確認を行う:

1. **変更に WPF ファイル（`src/LLMGameApp/`）が含まれるか確認する**。含まれない場合はスキップ。
2. **実機確認が必要な場合**: leader が `dotnet run --project src/LLMGameApp -- --replace` で起動し、`wpf-agent` で操作・読取・スクリーンショット確認を自律実行する。何を操作し、何を観測すれば 成功条件 を満たすかは leader が verification plan として事前に書き出す（必要なら tech-lead に観測項目を相談してよい）。
3. **自律確認が環境都合で不可能な場合のみ**: 完了扱いにせず `pending manual verification` として、ユーザーが確認すべき手順・期待結果・未確認リスクを明示する。
4. **確認結果が NG の場合**: 原因調査 → 修正 → 再確認のループ。BDD テストが Green でも WPF 実機で NG なら完了としない。

> 教訓: BDD テストはモック経由で実行され、WPF 固有の動作（DependencyProperty バインディング順序、ObservableCollection の UI 更新タイミング、タイマー駆動のアニメーション）を再現しない。

## Step 4: Completion

When all tasks are `done` (implemented + review passed + BDD tests passed + WPF 実機確認 passed):

### 4-1. Final design sign-off from tech-lead

Before dissolving the team, send a final SendMessage to `tech-lead`:

```
## Final design sign-off request

All tasks complete. Please review the cumulative diff and grant final design sign-off.

### Completed work
{summary of all tasks and their contribution to the 成功条件}

### Cumulative diff
{`git diff <base>...HEAD --stat` plus targeted diffs}

Reply with:
- **SIGN-OFF** — design integrity intact across the whole change
- **CONCERNS** — list specific residual issues (file, clause, required correction)
```

- **SIGN-OFF**: Proceed to 4-2
- **CONCERNS**: Treat as a new fix round — the leader drafts a fresh implementer prompt incorporating the tech-lead's findings as constraints (Step 2-3 flow, increment round number) and re-enters the loop at Step 3-1. After that round completes, Step 3-3a/3-3b/3-4 run normally and Step 4-1 is re-requested. Do NOT shut down the team yet.

### 4-2. Shutdown team

Only after 4-1 passes: send a shutdown message to **tech-lead**, then TeamDelete. Per-round implementers and per-batch reviewers do not receive shutdown messages — they were dismissed per-round/per-batch and no longer hold state.

### 4-3. Final report to user

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
- Tech-lead design checks: {N rounds, all CLEAR / N CONCERNS resolved}

### Files modified
{list of all files changed}

{If OpenSpec change: suggest marking tasks in tasks.md and/or archiving}
```

## Guardrails

### Routing principles

- **The leader is the sole executor and primary prompt author.** Drafting implementer prompts, launching Codex, reading diffs, and direction validation are all the leader's direct responsibility — none of these are routed through tech-lead.
- **The tech-lead is an on-demand advisor with a round-end gate and a final gate.** They are consulted (a) when the leader has a specific design question, (b) once at the end of each round for a diff integrity check, and (c) once at the end of the work for final sign-off. They proactively flag drift when they see it.
- **Context and constraints, not edit scripts.** When drafting any implementer prompt (initial or fix round), describe intent, non-negotiable constraints, and required evidence — never "edit line N to X."
- **If the leader is tempted to message tech-lead before every Codex launch, stop.** That is the old pattern this version explicitly removes. Tech-lead's value is judgment quality, not routing volume.

### Leadership principles (direction control)

- **State the outcome, not just the task list.** Every implementer prompt must include the Outcome Statement (課題, 目的, 成功条件, スコープ境界).
- **Validate direction at every round boundary.** The leader checks direction (3-3a), then tech-lead checks design (3-3b), then reviewers check code quality. Three different jobs, all required.
- **3-3b CLEAR is a hard precondition for 3-4.** The reviewer batch must not be launched until tech-lead returns CLEAR on the round's diff. This is the structural replacement for the routing hop that v3.2 enforced implicitly — without it, the round-end design gate can be silently skipped under time pressure.
- **Catch wrong-direction early, catch style issues late.** Requirements alignment is the first gate; code quality is the second.
- **If an implementer drifts, it is a context-quality failure — leader-level.** Trace and fix the prompt upstream rather than blaming the implementer.

### Tech-lead principles (design ownership, advisory-only)

- **Permanent advisory member, not a reviewer.** Tech-lead is spawned at team creation and stays until final sign-off. Not re-spawned per review batch.
- **Tech-lead holds design responsibility but not execution responsibility.** They do not draft implementer prompts, do not launch Codex, do not call the Agent tool. They advise, flag drift, gate round-end integrity, and grant final sign-off.
- **Tech-lead's CONCERNS are first-class CRITICAL findings.** When raised at round-end (3-3b) or final sign-off (4-1), treat at the same priority as the most severe reviewer findings.
- **Tech-lead describes constraints, not edits.** Their CONCERNS name the design principle violated and the corrective constraint, not the line to change.
- **Tech-lead has a final sign-off gate.** No sign-off, no team dissolution.

### Team lifespan and model choice

- **Persistent members (Claude Code native: opus; Codex adapter: translated by adapter)**: leader, tech-lead. These two stay from team creation to final shutdown.
- **Per-round members (Codex-first)**: implementers. Drafted and launched by the leader per round, dismissed after their completion/fix report. Each fix round launches fresh implementers (`implementer-{round}-{N}`).
- **Per-batch members (Codex-first)**: reviewers. Launched fresh at Step 3-4, dismissed at Step 3-5.
- **No persistent member is dismissed early.** Even after all reviews pass, leader and tech-lead stay alive through BDD verification, WPF 実機確認, and final sign-off.

### Execution rules

- **Leader writes code only via implementers.** The leader's direct text-editing on production code is limited to mechanical updates (tasks.md checkboxes, frontmatter markers, doc fixes to OpenSpec premises). All production code changes go through implementer Codex runs.
- **Implementers execute autonomously under leader-authored context.** No pre-approval required.
- **Don't rubber-stamp reviews.** Actually verify the code before judging review findings.
- **Fix queue takes priority over new tasks.** Address review findings before moving forward.
- **WRONG_DIRECTION takes priority over everything.** Do not let a fix round proceed on code that solves the wrong problem.
- **Critical issues interrupt.** Don't let implementers pile up more changes on top of a critical problem.
- **Minimize user confirmation.** Proceed to implementation without confirmation after displaying the task list. No interim progress reports needed. Report in bulk when everything is complete.
- **Update tasks.md checkboxes immediately.** After review passes, the leader updates `- [ ]` → `- [x]` in Step 3-6.
- **Parallelize implementer launches.** When multiple implementers have disjoint editable scopes, launch them in parallel.
- **Use `--full-auto` for Codex implementers.** Claude-Agent `mode: "auto"` is allowed only for explicit fallback runs.
