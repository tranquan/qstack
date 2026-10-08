---
name: q-impl
description: >-
  Implement an approved q-workflow plan. q-coder implements it and gets all
  checks green, then /code-review and an independent q-reviewer review the diff,
  and they iterate until it's clean. It refuses if the task has no approved plan.
  Triggers on: "q-impl", "implement the approved plan".
argument-hint: <worker task slug> [--opus]
---

# q-impl: coder ⇄ reviewer on an approved plan

You are the **orchestrator**. Read `~/.claude/q-workflow/RULES.md` first.

Input: `$ARGUMENTS`

**Comms log (default on).** Read RULES.md §10. If the input says "no log", "skip the log" or "without logging", set `log: off` in `index.md` and tell every sub-agent `log: off`. Otherwise read `log:` from `index.md` (missing = `on`). While it's on, append an entry to `comms.md` for each prompt or feedback message you send to a sub-agent.

## 0. Preconditions (all must hold)

1. Resolve the task: a slug in `~/Documents/z-agent/worker/tasks/`. If none is given, infer it from `tasks/README.md` or from the current branch matching an `index.md` `branch:`. If that's ambiguous, ask.
2. **The plans are ready.** Both must hold:
   - `plan.md` has an `approved: <date> by human` line.
   - `impl-plan.md` exists, with `status: agreed …`.

   If not, reply exactly:
   > No approved plan and agreed implementation plan for this task. Run `/q-plan <slug>` first.

   and stop. Don't implement from an unapproved plan, even a trivial one.
3. `phase` is `ready`, `impl`, `impl-review` or `impl-done`. A later phase (`impl-done` or beyond) → ask whether to re-run the review.
4. **Branch guard** (RULES.md §5): the recorded branch exists. If `branch: none`, run the guard's setup now and record the result. If any check fails, stop and report.

## 1. Implement

Set `phase: impl`. Spawn **q-coder** (`Agent(subagent_type: "q-coder")`; add `model: "opus"` if the input has `--opus`).

- **One coder per repo.** If `impl-plan.md` has more than one `## <repo>` section, spawn a fresh coder for each section, in the `## Order` the plan gives. Wait for one to finish before starting the next. A small context per coder keeps each turn fast. The next coder picks up what the previous one produced from the files the plan names (for example a generated client diff).
- Prompt each coder with:
  - the task folder
  - job `implement`, scoped to `## <repo>` (omit the scope for single-repo tasks)
  - the commit attribution line from your system context
- Keep each agent id, mapped to its repo, for `SendMessage`.
- When a coder finishes, tell the human in one line: the repo, the commits, and the checks.

Handling reports:
- Report `blocked`, or `NEEDS_HUMAN` → escalate (RULES.md §3) and stop.
- Report shows failing checks → send it back once. If it's still failing, escalate.

## 2. Review loop (max 2 rounds; a 3rd only if a blocker is still open)

Set `phase: impl-review`. Before each round, record `HEAD` of each repo (the reviewed `<sha>`).

### Round 1: full review, in parallel

1. In one message, start both:
   - **A fresh q-reviewer**, in the background, with: the task folder, mode `code`, round 1, the output file `review/code-r1.md`, and "`/code-review` runs in parallel; wait for its findings after your own review".
   - **The `code-review` skill** at `high` against the task branch, in each recorded checkout or worktree. Save its findings to `review/code-r1-codereview.md`. If plan §1 flags risks or security (auth, tenant data, secrets, external input), also run **`security-review`**, and append its output to the same file.
2. When both are done, `SendMessage` the reviewer: "verify `review/code-r1-codereview.md` and merge the real findings into `review/code-r1.md`". Read the verdict from its report.

### Round 2 and later: delta re-check

Spawn a fresh q-reviewer with: the task folder, mode `code`, round N, "delta re-check", the previous round's file, the reviewed `<sha>` per repo from the previous round, and the output file `review/code-r<N>.md`. **Don't run `code-review` again.**

### After each round

- **`APPROVED`** with no open minors → stop the loop.
- **`APPROVED`** with open minors or nits → `SendMessage` the owning coder(s): job `fix-findings`, file `review/code-r<N>.md`, "minors only, fix or waive". **No re-review.** Stop the loop.
- **`ESCALATE`**, or a blocking `NEEDS_HUMAN` → escalate and stop.
- **`NOT APPROVED`** → `SendMessage` the coder that owns the files for each finding: job `fix-findings`, file `review/code-r<N>.md`. If that coder is gone, spawn a fresh one scoped to that repo. Wait for the reports, then run the next round.

If round 2 ends with majors still open, or round 3 ends with a blocker still open → escalate.

## 3. Done

Set `phase: impl-done`. Update `index.md` and the README row. Report in short bullets (RULES.md §9):
- **Branch** and commits (not pushed).
- **Checks:** the commands and results.
- **Review:** the number of rounds, what got fixed, rebuttals, and waived minors.
- **Deviations from plan:** from `impl-notes.md`.
- **Next:** `/q-plan-impl <slug>` continues to the PR step. Or ask me to draft the PR.

**Don't push or open a PR from q-impl.**
