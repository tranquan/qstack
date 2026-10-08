---
name: q-plan-impl
description: >-
  Run the whole q-workflow for a task: planning with review (q-plan), human
  approval gates, implementation with review (q-impl), then a PR draft, and after
  human OK, push and open or update the PR. Resumes from wherever the task
  currently is. Triggers on: "q-plan-impl", "plan and implement", "full q flow".
argument-hint: <task text | GitHub issue URL | worker task slug> [--opus] [done]
---

# q-plan-impl: full flow, with human gates

You are the **orchestrator**. Read `~/.claude/q-workflow/RULES.md` first. This skill chains the other q-* skills and adds the PR step. "Whole flow" means you don't make the user invoke each step. **Every human gate still stops the turn.**

Input: `$ARGUMENTS`

**AI log:** follow RULES.md §10 (`ailog.md`, on unless the input or `index.md` says `log: off`).

## Flow: resume by `phase` in the task's `index.md`

| phase | Do |
|---|---|
| new / `planning` / `gate-1` / `impl-planning` | Follow `~/.claude/skills/q-plan/SKILL.md`. Once `impl-plan.md` is agreed (`ready`), show its short summary and continue **without stopping**. The user can interrupt |
| `ready` / `impl` / `impl-review` | Follow `~/.claude/skills/q-impl/SKILL.md` (pass `--opus` on). Once it reaches `impl-done`, continue below **without stopping** |
| `impl-done` | PR step, §1 |
| `gate-3` | If approved → §2. Otherwise re-show the draft |
| `pr-open` | Report the PR URL. For review comments, point to `/q-pr-resolve <PR>`. If the PR is merged, or the input says `done` / `archive` → §3 |
| `done` | Already archived. Say so and point to `tasks-archived/<slug>/` |

When the user approves at a gate, pick the flow up from the next row of this table.

## 1. PR draft (gate 3)

The gates in this flow are gate 1 (plan) and gate 3 (push + PR). The implementation plan is written down for the human to read, but it isn't a gate.

1. Continue or spawn **q-planner**, job `pr-draft`, and give it the PR attribution line from your system context. If the task has `issue: none`, ask the user for an issue first (global CLAUDE.md rule).
2. Set `phase: gate-3`. Show:
   - the PR title and body from `draft-pr.md`
   - the branch and `git log --oneline origin/main..HEAD`
   - whether a PR already exists for the branch (it will be updated)
3. Ask: "OK to push and open the PR?" and **stop.**

## 2. Push + PR (after gate 3 approval)

1. Planner job `pr-open`. It runs the RULES.md §5 pre-push checks (only this task's commits, merge `origin/main` if behind and re-check), pushes with `-u`, and creates or updates the PR.
2. **If the planner reports `blocked` on the merge** (a conflict, or a check that broke): spawn `q-coder` for that repo, job `fix-findings`, with the planner's output as the finding. When it's green and committed, run one q-impl delta re-check round (reviewed `<sha>` = the pre-merge `HEAD`). Then call the planner's `pr-open` again.
3. Set `phase: pr-open`. Add the PR to `index.md` **Links**, and update Progress, Log and the README row.
4. Report the PR URL, plus: "When reviewers comment, run `/q-pr-resolve <PR>`. When it's merged, run `/q-plan-impl <slug> done`."

## 3. Done: retro + archive

Run this when the PR is merged (check with `gh pr view --json state,mergedAt`), or when the user says the task is dropped.

1. **Retro** (RULES.md §8): answer the three questions, one line or "nothing" each.
   - *Missed:* compare the human's corrections at gates, hand edits after "done", and `git log origin/main -- <changed files>` since the merge, against the findings in `review/`. One tier 1 or tier 2 line if something was missed.
   - *Undocumented:* scan the `## Notes` of `impl-plan.md` for commands or gotchas the coder had to work out. One tier 3 line, or a runbook command.
   - *Stale:* any lesson or gotcha the task showed to be wrong, or any gotcha past 90 days without a `verified:` refresh. Delete it.
   - Keep `review-lessons.md` at or under 15 lines.
2. Add one **Log** line to `index.md`: `retro: …` with what was added and removed, or `retro: nothing`.
3. Set `phase: done`, `status: archived`, and `updated`. Move the folder to `~/Documents/z-agent/worker/tasks-archived/<slug>/`. Move its README row to **Done / Archived** with the PR link(s).
4. Offer to remove the worktree(s) (RULES.md §5 cleanup). Only do it with the user's OK.
5. Report in 3–5 bullets: the retro result, the archive path, and anything left for the human (deploy order, manual steps, follow-up issues).
