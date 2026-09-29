---
name: q-pr-resolve
description: >-
  Resolve PR review comments and CI failures with the q-workflow sub-agents, aiming
  to get the PR through quickly. q-reviewer verifies each comment (fix / invalid /
  out-of-scope / escalate), q-coder applies the small in-scope fixes with checks
  green, one quick re-check follows, then it pushes. Results are reported in chat
  only. Triggers on: "q-pr-resolve", "resolve PR comments with reviewer".
argument-hint: [PR number or URL]
---

# q-pr-resolve: get the PR through, fast

You are the **orchestrator**. Read `~/.claude/q-workflow/RULES.md` first (§5 branch guard, §7 outward-facing actions).

**Goal:** get the PR through review as fast as possible. Try to address every comment, but treat each one as a claim to verify, not a fact.

Input: `$ARGUMENTS`

## 1. Fetch

1. Resolve the PR: from the input, or `gh pr view --json number,url,headRefName,baseRefName,mergeStateStatus` on the current branch.
2. Fetch the review threads, reviews, comments and CI checks, then pre-filter and classify human vs bot, **exactly as in `~/.claude/skills/pr-resolve/SKILL.md` §1–3**. Reuse its GraphQL query, fallbacks and bot list. For failed checks, fetch the failing logs.
3. **Task link:** grep `~/Documents/z-agent/worker/tasks/*/index.md` for the PR URL.
   - Found → write the feedback to `tasks/<slug>/pr-<repo>-<n>-feedback.md` and log it in `index.md`.
   - Not found → don't create a task. Keep the state in the conversation.

   Either way, every item gets an id (`C01`…), and each id records author (human/bot), review state, `path:line`, the comment text (trimmed), and outdated or not.
4. No actionable items → report that and stop.

## 2. Branch guard

Follow RULES.md §5, with the PR's `headRefName` as the recorded branch:
- Main checkout clean → `gh pr checkout <n>`.
- Otherwise → `git worktree add ~/Documents/z-agaton/.worktrees/<folder>/pr-<n> <headRefName>` (after `git fetch origin`).
- If `mergeStateStatus` is `BEHIND` → `git merge origin/<base>` first.

## 3. Verify + triage

Spawn a **fresh q-reviewer** with:
- mode `pr-triage`
- the feedback: the file path, or the items inline
- the PR number and the checkout path
- if a task is linked, the output file `<task>/review/pr-<n>-triage.md`

It puts each item in one bucket:

| Bucket | Action |
|---|---|
| `fix` | Valid, in scope, small/straightforward → the coder fixes it |
| `invalid` | Skip. Keep the evidence for the summary |
| `out-of-scope` | Leave as is. Mention it in the summary as a possible follow-up |
| `escalate` | Approach or architecture change → ask the human. **This doesn't block the other fixes** |

Sanity-check the triage yourself. If a `fix` item looks like it needs an approach change, move it to `escalate`.

## 4. Fix

If there are any `fix` items: spawn **q-coder**, job `fix-findings`. Give it the `fix` items (ids, locations, evidence, fix hints), the checkout path, the branch, and the commit attribution line. Priority order: human `CHANGES_REQUESTED` → human comments → bot comments → CI. It fixes everything in one pass, runs the full quality gate, and commits locally after the guard check.

- `blocked` / `NEEDS_HUMAN` → move those items to `escalate`. Keep the rest.

## 5. Quick re-check (1 round, +1 only on a blocker)

Spawn a **fresh q-reviewer**, mode `pr-recheck`, on the diff of the new commits. If a task is linked, give it the output file `review/pr-<n>-recheck.md`. A blocker or major → `SendMessage` it to the coder once, then re-check once more. Anything still open → escalate.

## 6. Push

Run the RULES.md §5 pre-push checks, then `git push`. That's the same authorization as the existing `pr-resolve` skill. Escalated items don't hold up the push of verified fixes.

**Don't** post replies, resolve threads, or comment on GitHub unless the user explicitly asks (RULES.md §7).

## 7. Summary (in chat)

```
## PR #<n> — feedback resolution

**Fixed** (<sha>):
- C03 @coderabbitai — null check on `org_id` in `repo/path.py:L42`
**Invalid:**
- C05 @copilot — claims `foo()` is async; it isn't (`repo/x.py:L10`)
**Out of scope** (possible follow-ups):
- C07 @alice — pre-existing N+1 in `list_users`; unrelated to this PR
**Escalated:**
1. C02 @bob: "move auth to middleware"
   (a) apply — … (b) keep + explain — … Recommendation: (b) because …
**Checks:** <commands → pass>. Pushed: yes/no.
```

If a task is linked, update its `index.md` log. If a `fix` item was something the q-flow should have caught before the PR (a bot or human found a real bug), append a one-line lesson to `~/Documents/z-agent/worker/docs/review-lessons.md`.
