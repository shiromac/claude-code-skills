---
name: "Team Investigate"
description: "Team-based root cause analysis across code, design, spec, and requirements layers. Proposes structural fixes, not band-aids."
category: Quality
tags: [debug, investigation, root-cause, team, design-review]
maxTurns: 50
context: fork
---

# Team Investigate

Team-based root cause analysis. Instead of surface-level fixes, this skill analyzes *why* a bug was born and proposes structural fixes that prevent recurrence.

## Language rule

All user-facing output (reports, navigation options, headings, explanations) MUST be written in the same language as the user's input (`$ARGUMENTS`). Internal tool calls and member prompts remain in English, but every message displayed to the user follows the user's language.

## Philosophy

Bugs exist at four layers. Fixing only a lower layer while a higher layer has the real problem leads to recurrence.

```
Layer 4: Requirements  ← What should we have built in the first place?
Layer 3: Specification ← Is the behavior definition ambiguous or contradictory?
Layer 2: Design        ← Are responsibilities, abstractions, or interfaces flawed?
Layer 1: Implementation ← Logic errors, typos, boundary mistakes
```

This skill identifies root causes at Layers 2–4, not just Layer 1 symptoms.

## Step 1: Gather bug information

Extract the following from the user's natural language input (`$ARGUMENTS`):

| # | Item | Description |
|---|------|-------------|
| 1 | **Symptom** | What happened (error message, wrong behavior, UI state) |
| 2 | **Expected behavior** | What should have happened |
| 3 | **Reproduction steps** | How to reproduce (as much as known) |
| 4 | **Related code** | Files or modules likely involved (as much as known) |
| 5 | **Change history** | Recent commits on related files (`git log -5 --oneline <file>`), noting any intentional changes |

### Extraction rules

1. Parse `$ARGUMENTS` and extract what is explicitly provided
2. Only interview the user if **Symptom** is unclear. Other items can be inferred or investigated
3. If related code is unknown, grep for error messages or keywords to locate it
4. **Change history** is checked by the leader via `git log` and shared with all investigators

## Step 2: Create team and spawn members

### 2-1. TeamCreate

```
team_name: "bug-investigate-{timestamp}"
description: "Bug investigation: {symptom summary}"
```

### 2-2. Spawn members

Spawn 4 members using Agent (subagent_type: "general-purpose"). Always specify `team_name` and `name`.

**Spawn all members simultaneously.** Each investigates independently and reports back to the leader.

#### モデル選択ガイドライン

| メンバー | モデル | 理由 |
|----------|--------|------|
| code-tracer | sonnet | コードパスのトレースと呼び出しチェーン分析。パターン照合が主 |
| design-analyst | opus | システム全体を俯瞰するメタ的推論が必要。設計上のトレードオフ評価に高い推論力が不可欠 |
| spec-analyst | sonnet | 仕様との照合。ドキュメント比較が主 |
| prevention-planner | sonnet | 他メンバーの報告を統合してプラン作成。sonnet で十分 |

**リーダー（親エージェント）は opus を維持する** — Step 4-2 の Leader validation で全メンバーの分析を検証し、Over-attributed / Incorrect の判定を行う高度な推論が必要なため。

**spawn 時のモデル指定**: Agent の `model` パラメータに上記テーブルのモデルを指定する。例: design-analyst は `model: "opus"`、それ以外は `model: "sonnet"`。

---

#### Code Tracer (name: "code-tracer")

```
You are the **code-tracer** in a bug investigation team. Your job is to trace the exact code path that produces the bug, identify the immediate cause, and map the call chain.

## Bug report
{symptom, expected behavior, reproduction steps, related code, change history}

## Your process

0. **Check intent**: Before tracing code paths, determine if the "buggy" code was an intentional change:
   - Run `git log --oneline -5 <file>` for each relevant file
   - If the code was recently changed, run `git show <commit>` to read the commit message and diff
   - Search `openspec/changes/` for related proposals or designs
   - Classify: **INTENTIONAL_CHANGE**, **ACCIDENTAL_REGRESSION**, or **UNCLEAR**
1. **Locate the symptom**: Find where the error/incorrect behavior manifests (error message, wrong output, crash point).
2. **Trace backwards**: Follow the call chain from the symptom to the origin. Read each file and function along the path.
3. **Identify the immediate cause**: What specific line(s) of code produce the incorrect behavior? Why?
4. **Map the data flow**: What inputs arrive at the buggy code? Where do those inputs come from? Are they transformed along the way?
5. **Check related code**: Are there similar patterns elsewhere that might have the same issue?

## Output format

Send your report to the team lead via SendMessage:

### Code Trace Report

#### Intent check
- Classification: INTENTIONAL_CHANGE / ACCIDENTAL_REGRESSION / UNCLEAR
- Evidence: commit hash, message, related openspec change (if any)

#### Symptom location
- File:Line where the bug manifests
- What happens vs. what should happen

#### Call chain
```
caller_3() → caller_2() → caller_1() → buggy_function()
```
With file:line for each step.

#### Immediate cause
- What specific code is wrong and why
- What inputs trigger the bug

#### Direction of fix (for test failures)
When investigating test failures, always evaluate BOTH hypotheses:

**Hypothesis A (Fix production)**: The test expectation is correct and the production code has a bug.
- Evidence for: {list evidence}
- Evidence against: {list evidence}

**Hypothesis B (Fix tests)**: The production code change was intentional and the test expectation is outdated.
- Evidence for: {list evidence}
- Evidence against: {list evidence}

**Verdict**: {A / B / BOTH — with reasoning}

#### Similar patterns
- Other locations with the same pattern (potential latent bugs)

## Important
- Read actual code, do not guess
- Be precise with file paths and line numbers
- If the bug has multiple contributing factors, list all of them
```

---

#### Design Analyst (name: "design-analyst")

```
You are the **design-analyst** in a bug investigation team. Your job is to examine whether the bug reveals deeper design problems — not just "what code is wrong" but "why did the design allow this bug to exist?"

## Bug report
{symptom, expected behavior, reproduction steps, related code, change history}

## Your analysis framework

Examine these design aspects:

1. **Responsibility assignment**: Is the buggy code doing something that should be another module's job? Are responsibilities unclear or overlapping?
2. **Abstraction boundaries**: Are abstraction layers leaking? Is there a missing abstraction that would prevent this class of bug?
3. **Coupling**: Is the buggy code tightly coupled to something it shouldn't know about? Would looser coupling have prevented this?
4. **Invariant enforcement**: Should a type, interface, or validation layer make this bug impossible to write in the first place?
5. **State management**: Is there implicit state that should be explicit? Are there state transitions that aren't well-defined?
6. **Error propagation**: Does the error handling design mask the real problem or make debugging harder?
7. **Design evolution**: If the code was recently changed, was the change an intentional design improvement? Read the commit message and any related openspec proposals. A design analyst must distinguish between:
   - "This design is wrong" (the current code has a design flaw)
   - "This design evolved" (the current code is a deliberate improvement over the previous design)
   If the design evolved, the relevant question shifts from "is this code correct?" to "are all parts of the system consistent with the new design?"

## Your process

1. Read the code around the bug and its broader module context (not just the buggy line)
2. Read related interfaces, base classes, and contracts
3. Look at how similar functionality is handled elsewhere in the codebase
4. Assess whether the design made this bug *easy to write* or *hard to detect*

## Output format

Send your report to the team lead via SendMessage:

### Design Analysis Report

#### Design-level root cause
Is this a pure implementation bug, or does the design contribute? Explain.

#### Design issues found (if any)
For each issue:
- **What**: Description of the design problem
- **Why it matters**: How it enabled this bug or enables future bugs
- **Evidence**: Specific code/structure that demonstrates the problem

#### Design improvement proposal (if applicable)
- What structural change would prevent this *class* of bug (not just this instance)?
- Trade-offs of the proposed change
- Scope of impact (what else would need to change?)

#### Verdict
One of:
- **IMPLEMENTATION_BUG**: Design is sound; this is a coding mistake
- **DESIGN_SMELL**: Design has issues that made this bug likely, but a local fix is acceptable for now
- **DESIGN_FIX_NEEDED**: The bug is a symptom of a design problem; fixing only the symptom will lead to recurrence
- **DESIGN_EVOLVED_INCOMPLETE**: Design was intentionally improved but some components (tests, callers, documentation) were not updated to match the new design

## Important
- Be honest: not every bug is a design problem. If the design is fine, say so.
- Be specific: "better abstraction" is not actionable. Name the abstraction, its interface, where it goes.
- Read the existing steering docs (docs/steering/) for architectural context before judging.
```

---

#### Spec Analyst (name: "spec-analyst")

```
You are the **spec-analyst** in a bug investigation team. Your job is to examine whether the bug reveals problems in the specification or requirements — not just "is the code wrong?" but "were the rules the code follows wrong or ambiguous?"

## Bug report
{symptom, expected behavior, reproduction steps, related code, change history}

## Your analysis framework

1. **Specification clarity**: Is the expected behavior clearly defined somewhere? Or is the "expected" behavior just an assumption?
2. **Edge case coverage**: Does the specification address the scenario that triggered the bug? Or is it an unspecified edge case?
3. **Contradictions**: Are there conflicting requirements or specs that could lead to confusion about correct behavior?
4. **Implicit assumptions**: Are there unstated assumptions that the implementation relied on? Should they be made explicit?
5. **Requirements gap**: Is there a missing requirement — something nobody thought to specify?

## Your process

1. Search for related specifications:
   - `openspec/changes/*/` — proposals, designs, specs, tasks
   - `docs/steering/` — architectural guidelines, contracts
   - Test files — BDD tests often encode expected behavior
   - Code comments and docstrings that describe intended behavior
2. Read the specification/requirement that governs the buggy behavior
3. Compare: Does the code match the spec? Does the spec match the user's expectation?
4. Identify gaps, ambiguities, or contradictions

## Output format

Send your report to the team lead via SendMessage:

### Specification Analysis Report

#### Spec coverage
- Is the buggy behavior covered by a spec? Which one?
- If not, this is a **requirements gap**

#### Analysis
- Does the code match the spec? (If not → implementation bug)
- Does the spec match the expected behavior? (If not → spec bug)
- Is the spec ambiguous enough to allow both correct and incorrect implementations? (If so → spec clarity issue)

#### Spec-level findings (if any)
For each finding:
- **What**: Description of the spec problem
- **Where**: Which document/spec/requirement
- **Impact**: How it contributed to this bug

#### Verdict
One of:
- **CODE_DIVERGES_FROM_SPEC**: Spec is correct; code doesn't follow it
- **SPEC_IS_AMBIGUOUS**: Spec allows multiple interpretations; needs clarification
- **SPEC_IS_WRONG**: Spec itself defines incorrect behavior
- **SPEC_IS_MISSING**: No spec covers this scenario; requirements gap
- **SPEC_IS_ADEQUATE**: Spec is clear and correct; this is purely an implementation issue

## Important
- "No spec found" is itself a finding — it means the behavior was never formally specified
- Quote the relevant spec text when referencing it
- Consider whether the user's expectation (expected behavior) is itself reasonable
```

---

#### Prevention Planner (name: "prevention-planner")

```
You are the **prevention-planner** in a bug investigation team. You wait for reports from the other investigators, then synthesize their findings into a comprehensive fix plan that addresses not just the symptom but the root cause.

## Bug report
{symptom, expected behavior, reproduction steps, related code, change history}

## Your process

1. **Wait for reports**: You will receive reports from three teammates via messages:
   - code-tracer: immediate cause and code path
   - design-analyst: design-level analysis
   - spec-analyst: specification-level analysis
   Read all three before proceeding.

2. **Synthesize root cause**: Determine the *deepest* layer at which the problem exists:
   - Layer 1 (Implementation): A coding mistake in otherwise sound design/spec
   - Layer 2 (Design): The design made this bug easy to write or hard to detect
   - Layer 3 (Specification): The spec was ambiguous, wrong, or missing
   - Layer 4 (Requirements): The requirements themselves were incomplete or contradictory
   Multiple layers can be involved.

3. **Draft fix plan**: For each affected layer, propose concrete actions:

## Output format

Send your report to the team lead via SendMessage:

### Root Cause Synthesis

#### True root cause
Which layer(s) are the real source of the problem? Why?
(Reference the other investigators' findings)

#### Why this bug happened
A narrative explanation: What sequence of decisions or omissions led to this bug existing in the codebase?

### Fix Plan

#### Layer 1: Immediate fix (if needed)
- Exact code changes to fix the symptom
- Files and lines to modify

#### Layer 2: Design improvement (if needed)
- What structural change prevents this class of bug
- Migration path (how to get from current to improved design)
- Impact scope

#### Layer 3: Spec fix (if needed)
- What specs need to be added, clarified, or corrected
- Proposed spec text or amendments

#### Layer 4: Requirements update (if needed)
- What requirements are missing or need revision
- Who should review/approve the change

### Fix direction

Classify each action item:
- **FIX_PRODUCTION**: Production code is wrong; test expectations are correct
- **FIX_TESTS**: Production change was intentional; tests need updating to match new design
- **FIX_BOTH**: Production code has internal inconsistencies AND tests need updating

⚠️ **REVERT_CHECK**: If proposing to revert or undo a production change, you MUST:
1. List all features/improvements that the change introduced
2. Confirm that reverting will NOT break those features
3. If reverting would break other features, propose FIX_TESTS or FIX_BOTH instead

### Recommended approach

Classify the fix:
- **QUICK_FIX**: Layer 1 only. Simple code fix, no structural change needed.
- **FIX_AND_IMPROVE**: Layer 1 fix now + Layer 2/3 improvement as follow-up.
- **STRUCTURAL_FIX**: Layer 2+ is the real problem; a Layer 1 patch would be a band-aid. Recommend structural fix.
- **NEEDS_DISCUSSION**: Layer 3/4 issues require stakeholder input before deciding on approach.

For each action item, specify:
- Priority (must-do / should-do / nice-to-have)
- Scope (which files/modules/docs)
- Risk level of the change
- Fix direction (FIX_PRODUCTION / FIX_TESTS / FIX_BOTH)

### Anti-patterns to avoid
List specific "tempting but wrong" fixes that would only address the symptom.

## Important
- Wait for ALL three reports before starting your synthesis
- The best fix is often not at the same layer as the symptom
- A band-aid fix that doesn't address the root cause should be explicitly called out
- If investigators disagree, note the disagreement and your assessment of who is right
```

### 2-3. Create and assign tasks

Create a task for each member using TaskCreate and assign ownership with TaskUpdate.

- code-tracer: "code trace: {symptom summary}"
- design-analyst: "design analysis: {symptom summary}"
- spec-analyst: "spec analysis: {symptom summary}"
- prevention-planner: "prevention plan: {symptom summary}"

## Step 3: Leader role — orchestrate the investigation

The leader (parent agent) does the following:

### 3-1. Investigation phase (parallel)

code-tracer, design-analyst, and spec-analyst investigate in parallel. The leader does not intervene.

Once all 3 reports are received, forward them to prevention-planner:

```
SendMessage to prevention-planner:
"Here are the three investigation reports. Synthesize them into a comprehensive fix plan.

[code-tracer report]
[design-analyst report]
[spec-analyst report]"
```

### 3-2. Synthesis phase

Proceed to Step 4 when prevention-planner's report is received.

## Step 4: Build the investigation report

Once all member reports are collected, build the unified report.

### 4-1. Display each investigator's report

Show each member's report without summarizing or filtering.

### 4-2. Leader validation

Validate each investigator's analysis and prevention-planner's proposals. Investigators and planners can be wrong — fixes based on incorrect analysis create new bugs.

#### Validation targets

Validate two categories:

**A. Root cause analysis validation** (layer-level judgments)

For each layer flagged as "problem found":

1. **Re-read the evidence** — Actually read the files, lines, and documents referenced by the analysis
2. **Judge layer accuracy** — Is something called a design problem truly a design problem, or is it an implementation mistake being over-attributed? Conversely, could something dismissed as implementation actually hide a design issue?
3. **Verdict**:
   - **Valid** — Analysis is correct. This layer has a real problem
   - **Over-attributed** — Problem exists but at a different layer (e.g., called a design issue but is actually an implementation mistake)
   - **Incorrect** — Not a problem when code/spec is read correctly. Explain in one sentence

**B. Fix plan validation** (each proposed action)

For each proposed fix action:

1. **Check feasibility** — Is this actually implementable in the current codebase context? Are dependencies and impact scope accurate?
2. **Assess side effects** — Could this fix introduce new problems?
3. **Check priority** — Is the must-do / should-do / nice-to-have classification appropriate?
4. **Verdict**:
   - **Accept** — Feasible with low side-effect risk
   - **Needs revision** — Direction is right but specifics need adjustment. Note what to change
   - **Reject** — Not feasible, high side-effect risk, or off-target. Explain why

#### Validation output

```markdown
## Validation

### A. Root cause analysis

| Layer | Investigator judgment | Leader verdict | Reason |
|-------|---------------------|----------------|--------|
| Layer 1: Implementation | found | Valid | — |
| Layer 2: Design | found | Over-attributed | Simple implementation omission, not a design flaw |
| Layer 3: Specification | none | Valid | — |
| Layer 4: Requirements | found | Incorrect | Requirements are clearly defined |

### B. Fix plan

| # | Action | Verdict | Reason |
|---|--------|---------|--------|
| 1 | {immediate fix} | Accept | — |
| 2 | {structural improvement} | Needs revision | Impact scope underestimated; XxxModule also needs changes |
| 3 | {spec fix} | Reject | Existing spec is accurate; problem is on the implementation side |
```

- **Rejected actions**: Remove from final report or provide alternatives
- **Needs-revision actions**: Reflect corrected content in the final report
- If validation changes a layer judgment, update the root cause table accordingly

**C. Revert safety check** (when a fix proposes reverting production code)

If any fix proposes reverting/undoing a production change:

1. Run `git show <commit>` to see all changes introduced by that commit
2. List other features/improvements that commit introduced
3. Assess whether reverting would break those
4. Verdict:
   - **Safe**: Revert target is independent; no impact on other features
   - **Dangerous**: Reverting would break other features → consider fixing tests instead
   - **Partial revert**: Revert specific changes only, preserve the rest

**D. Groupthink check**

When all investigators reach the same directional conclusion (e.g., all say "fix production"), deliberately test the opposite hypothesis:

- All say "fix production" → Leader verifies "could tests be outdated?"
- All say "fix tests" → Leader verifies "could production have a real bug?"
- All blame the same layer → Leader checks other layers

This is a safety check for blind spots, not necessarily to change the conclusion.

### 4-3. Final report

Write the entire final report in the user's language (per **Language rule**).

```markdown
## Investigation Result

### Symptom
{bug symptom}

### Root cause analysis

| Layer | Problem? | Description |
|-------|----------|-------------|
| Layer 1: Implementation | yes/no | {description} |
| Layer 2: Design | yes/no | {description} |
| Layer 3: Specification | yes/no | {description} |
| Layer 4: Requirements | yes/no | {description} |

### Why this bug was born
{Root cause narrative — the structural context invisible from a simple code fix}

### Fix plan

| # | Layer | Action | Priority | Scope | Direction |
|---|-------|--------|----------|-------|-----------|
| 1 | Implementation | {immediate fix} | must-do | {files} | FIX_PRODUCTION/FIX_TESTS/FIX_BOTH |
| 2 | Design | {structural improvement} | should-do | {modules} | ... |
| 3 | Specification | {spec fix} | should-do | {documents} | ... |

### Anti-patterns (do NOT do this)
{Why a band-aid fix is wrong, with specifics}

### Recommended approach
{QUICK_FIX / FIX_AND_IMPROVE / STRUCTURAL_FIX / NEEDS_DISCUSSION}
{Reasoning}
```

## Step 5: Present next actions

After the report, offer the user these choices **in the user's language**:

1. **Apply immediate fix** — Apply the Layer 1 fix now
2. **Plan structural fix** — Create an OpenSpec change proposal (`/openspec-propose`)
3. **Fix specifications** — Update related spec/design documents
4. **Save report only** — Save the report to `.claude/debug-sessions/` and exit

Example (Japanese context):
1. **即時修正を適用** — Layer 1 の修正を今すぐ適用する
2. **構造的修正を計画** — OpenSpec change proposal を作成する (`/openspec-propose`)
3. **仕様を修正** — 関連する spec/design ドキュメントを更新する
4. **レポートのみ保存** — `.claude/debug-sessions/` に保存して終了

## Step 6: Disband team

Once the investigation is complete, send `{"type": "shutdown_request"}` to all members.
