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

### 1-2. Build the task list

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

### 1-3. Gather context

Read all relevant context files so you (the leader) understand the full picture:
- OpenSpec artifacts (proposal, design, specs) if applicable
- Relevant source files referenced in tasks
- Any existing code patterns the implementation should follow

Display the task list and context summary to the user. **Proceed to implementation without asking for confirmation.** Only pause for confirmation if the user explicitly requests it.

### 1-4. Execute BDD tests (mandatory, before implementation)

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

**Important**: When multiple independent tasks exist, **batch all Agent tool calls into a single message for parallel spawn**. Sequential spawning is prohibited.

Prompt:

```
You are **implementer-{N}** in a team-apply session. You write code autonomously.

## Context

{context summary — what the overall work is about, design decisions, relevant patterns}

## Your assigned tasks

{full list of tasks assigned to this implementer}

## Communication protocol

### Autonomous execution mode
- Implement assigned tasks **sequentially from top to bottom, without waiting for approval**
- Move to the next task immediately after completing each one (do not wait for leader instructions)
- Send a **single completion report** after all tasks are done

### When to report to the leader (exceptions only)
Report to the leader via SendMessage and wait for guidance ONLY when:
- You discover a critical issue requiring a design decision (approach fundamentally changes)
- You need to modify files owned by another implementer (conflict avoidance)
- A task turns out to be infeasible

### Completion report (after all tasks are done)
After completing all tasks, send the leader a SendMessage with:
- Changed files and change summary per task
- Any deviations from expectations and why
- Concerns if any

### General rules
- Implement ONLY the assigned tasks
- Do not refactor, improve, or clean up code beyond the task scope
- If the leader sends a correction, adjust immediately
- If the leader sends a shutdown message, finish your current action and stop
- Keep changes minimal and focused
- Run `dotnet build` after changes to verify compilation when applicable
```

### 2-3. Select reviewers

Based on the target content, select reviewers from the following pool.

#### Core members (always included)

| Name | Expertise |
|------|-----------|
| **architect** | Separation of concerns, dependency direction, layer boundaries, SOLID principles, class/module design |
| **security** | Injection (SQL, command, XSS), secrets management, auth/authz, unsafe deserialization, path traversal |
| **spec-conformance** | Divergence from use cases, requirements coverage, inconsistencies with specified behavior |

#### Additional members (selected based on content)

| Name | Expertise | Selection criteria |
|------|-----------|-------------------|
| **concurrency** | Thread safety, race conditions, deadlock, async/await, lock strategy | Code contains async, lock, thread, Task, ConcurrentXxx, etc. |
| **performance** | Computational complexity, allocations, hot paths, caching, excessive LINQ | Code contains loops, bulk data operations, frequently-called paths |
| **error-handling** | Boundary values, exception propagation, recovery, failure modes, error message quality | Code contains try/catch, Result types, error boundaries |
| **readability** | Naming, complexity (cognitive/cyclomatic), pattern consistency, clarity of intent | Large changes, new file additions, refactoring |

#### Selection rules

1. **Core 3 are always included**
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

1. **Read the actual code changes** — `git diff` for the files mentioned, plus surrounding context
2. **Focus on your area of expertise.** You are {role_name}. Review deeply from your perspective. Do not try to cover everything — your teammates cover other perspectives.
3. **Consult teammates when needed.** If you find something that crosses into another reviewer's domain, or want a second opinion, send them a message using SendMessage with their name. Your teammates are: {teammate_names}.
4. **Produce a review report**

## Review report format

For each task in the batch:

```
### Task: {task description}
**Verdict**: PASS / NEEDS_FIX / CRITICAL

If NEEDS_FIX or CRITICAL:
- **File:Line** — issue description
- **Severity**: critical / warning / nit
- **Suggestion**: concrete fix or alternative
```

Summary at the end:
- Total tasks reviewed
- PASS / NEEDS_FIX / CRITICAL counts
- If all PASS: "Batch approved from {role_name} perspective"

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

### 3-3. Completion handling

When an implementer sends a completion report:

1. **Record completed tasks** — Update internal tracking to `review` status
2. **Wait for all implementers to complete** — Once everyone is done, send review batch (Step 3-4)
3. If only some implementers have completed, wait for the rest

### 3-4. Sending review batches

When sending to **all reviewers** (send the same batch to each):

```
## Review batch

### Tasks to review:
{list of tasks completed since last review}

### Files changed:
{summary of files modified per task}

### Context:
{any design context the reviewer needs}

Please review from your perspective and report.
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
   - **NEEDS_FIX (valid)**: Add fix items to the fix queue, mark affected tasks as `fix`
   - **CRITICAL (valid)**: Flag for immediate attention. If implementer is working, send interrupt with the critical issue

For NEEDS_FIX items, **batch all fix tasks and assign to the implementer** (if multiple implementers, assign to the original task owner):

```
## Fix required: {task descriptions}

### Review findings:
{integrated findings from multiple reviewers — include reviewer name and specifics}

Fix all issues and send a completion report. No interim check-ins needed.
```

The implementer executes fixes autonomously and sends only a completion report.

### 3-6. Writing review markers

When a batch passes review, write a marker for the associated task(s).

Markers are written to the openspec change directory: `openspec/changes/<change_name>/.review-task-<task_id>.json`

For each approved task that has a corresponding task_id:

1. Stage changes: `git add -A`
2. Get tree hash: `git write-tree`
3. Write `openspec/changes/<change_name>/.review-task-<task_id>.json`:

```bash
bash -c 'tree=$(git add -A && git write-tree) && cat > openspec/changes/<change_name>/.review-task-<task_id>.json << EOF
{
  "task_id": "<task_id>",
  "task_subject": "<task description>",
  "tree_hash": "'$tree'",
  "reviewed_at": "<ISO 8601>",
  "ok": true
}
EOF'
```

If tasks don't have individual task_ids (e.g., ad-hoc work), write a single marker `openspec/changes/<change_name>/.review-task-default.json`.

If the work is not associated with an openspec change, write to `openspec/.reviews/.review-<descriptive_name>.json`.

## Step 4: Completion

When all tasks are `done` (implemented + review passed + BDD tests passed):

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

- **Leader never writes code.** Not even "just this one small fix." All code changes go through the implementer.
- **Implementers execute autonomously.** No pre-approval required. They report to the leader only on exceptions. The leader ensures quality through review results.
- **Don't rubber-stamp reviews.** Actually verify the code before judging review findings.
- **Fix queue takes priority over new tasks.** Address review findings before moving forward.
- **Critical issues interrupt.** Don't let the implementer pile up more changes on top of a critical problem.
- **Context is the leader's advantage.** The leader sees the full picture. Use it to catch direction issues early, before they compound.
- **Minimize user confirmation.** Proceed to implementation without confirmation after displaying the task list. No interim progress reports needed. Report in bulk when everything is complete.
- **Spawn implementers in parallel.** When independent tasks exist, spawn multiple implementers in a single message. Sequential spawning is prohibited.
- **Use `mode: "auto"` for implementers.** When spawning implementers via the Agent tool, specify `mode: "auto"` to bypass approval prompts. Reviewers are read-only (git diff, file reads) so default mode is fine for them.
