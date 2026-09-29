---
name: q-plan-impl
description: >-
  Run the whole q-workflow for a task: planning with review (q-plan), human
  approval gates, implementation with review (q-impl), then a PR draft, and after
  human OK, push and open or update the PR. Resumes from wherever the task
  currently is. Triggers on: "q-plan-impl", "plan and implement", "full q flow".
argument-hint: <task text | GitHub issue URL | worker task slug> [--opus]
---

# q-plan-impl: full flow, with human gates

You are the **orchestrator**. Read `~/.claude/q-workflow/RULES.md` first. This skill chains the other q-* skills and adds the PR step. "Whole flow" means you don't make the user invoke each step. **Every human gate still stops the turn.**

Input: `$ARGUMENTS`

## Flow: resume by `phase` in the task's `index.md`

| phase | Do |
|---|---|
| new / `planning` / `gate-1` / `impl-planning` | Follow `~/.claude/skills/q-plan/SKILL.md`. Once `impl-plan.md` is agreed (`ready`), show its short summary and continue **without stopping**. The user can interrupt |
| `ready` / `impl` / `impl-review` | Follow `~/.claude/skills/q-impl/SKILL.md` (pass `--opus` on). Once it reaches `impl-done`, continue below **without stopping** |
| `impl-done` | PR step, §1 |
| `gate-3` | If approved → §2. Otherwise re-show the draft |
| `pr-open` | Report the PR URL. For review comments, point to `/q-pr-resolve <PR>` |

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
2. If the pre-push checks needed a merge that changed code, run one q-impl review round on the merge result before pushing.
3. Set `phase: pr-open`. Add the PR to `index.md` **Links**, and update the log and the README row.
4. Report the PR URL, plus: "When reviewers comment, run `/q-pr-resolve <PR>`."
