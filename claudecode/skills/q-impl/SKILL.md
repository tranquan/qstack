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

Set `phase: impl`. Spawn **q-coder** (`Agent(subagent_type: "q-coder")`; add `model: "opus"` if the input has `--opus`). Prompt:
- the task folder
- job `implement`
- the commit attribution line from your system context

Keep its agent id for `SendMessage`.

- Report `blocked`, or `NEEDS_HUMAN` → escalate (RULES.md §3) and stop.
- Report shows failing checks → send it back once. If it's still failing, escalate.

## 2. Review loop (max 3 rounds)

Set `phase: impl-review`. For round N = 1..3:

1. **Run the code-review skill.** In the recorded checkout or worktree, run the **`code-review`** skill at `high` against the task branch.
   - Save its findings to `review/code-r<N>-codereview.md`.
   - If plan §1 flags risks or security (auth, tenant data, secrets, external input), also run **`security-review`**, and append its output to the same file.
2. **Spawn a fresh q-reviewer** with:
   - the task folder
   - mode `code`
   - round N
   - the `/code-review` findings file, so it can verify them
   - the output file `review/code-r<N>.md`
   - the previous round's file, if N > 1

   The reviewer writes the review file itself. Read the verdict from its report.
3. **`APPROVED`** → stop the loop.
4. **`ESCALATE`**, or a blocking `NEEDS_HUMAN` → escalate and stop.
5. **`NOT APPROVED`** → `SendMessage` to the coder: job `fix-findings`, file `review/code-r<N>.md`. Wait for its report.

If round 3 ends with blockers or majors still open → escalate.

## 3. Done

Set `phase: impl-done`. Update `index.md` and the README row. Report in short bullets (RULES.md §9):
- **Branch** and commits (not pushed).
- **Checks:** the commands and results.
- **Review:** the number of rounds, what got fixed, rebuttals, and waived minors.
- **Deviations from plan:** from `impl-notes.md`.
- **Next:** `/q-plan-impl <slug>` continues to the PR step. Or ask me to draft the PR.

**Don't push or open a PR from q-impl.**
