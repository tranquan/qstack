# q-workflow: how the pieces fit together

This folder is the source of `~/.claude/{agents,skills,q-workflow}` for the q-workflow.
`./sync.sh` keeps the two in sync (dry run by default, `--apply` to copy).

## What Claude Code loads, and what it doesn't

| Folder | Loaded by Claude Code? | Role |
|---|---|---|
| `agents/q-*.md` | Yes. Each file is a sub-agent: model, tools and system prompt | The three roles: planner, reviewer, coder |
| `skills/q-*/SKILL.md` | Yes. Each is a `/q-*` slash command | The orchestrator script the main session follows |
| `q-workflow/RULES.md` | **No.** Plain file, nothing special to Claude Code | Shared rulebook. Every agent and skill starts with "read RULES.md". It works only because they have a Read tool and the path is hard-coded |

So `q-workflow/` is a convention, not a requirement. It exists so the rules are written once instead of pasted into seven files.

## Who talks to whom

Only the orchestrator talks to the human. Agents talk to each other through files in the task folder, never directly.

```mermaid
flowchart TB
    H([Human])
    subgraph MS["Main session (orchestrator) running a /q-* skill"]
        O[Orchestrator]
    end
    subgraph Agents["Sub-agents, each with its own context"]
        P[q-planner]
        R[q-reviewer<br/>fresh instance per round]
        C[q-coder<br/>one per repo]
    end
    subgraph State["Shared state on disk"]
        T["worker/tasks/&lt;slug&gt;/<br/>index.md · plan.md · impl-plan.md<br/>review/*.md · ailog.md"]
        RU[q-workflow/RULES.md]
        L["worker/docs/review-lessons.md<br/>worker/docs/repos/&lt;alias&gt;.md"]
        G["git repo(s) in ~/Documents/z-agaton/<br/>task branch or worktree"]
    end

    H <-->|"gates, questions,<br/>escalations"| O
    O -->|"Agent() prompt: task folder + job"| P
    O -->|"Agent() prompt: mode + round + output file"| R
    O -->|"Agent() prompt: repo scope + job"| C
    P & R & C -->|"short report<br/>(JOB / FILES / NEEDS_HUMAN)"| O
    O -->|"SendMessage: revise / fix-findings"| P & C

    P <-->|"spec, plan, impl-plan,<br/>planner responses"| T
    R -->|"review/*-rN.md"| T
    R -.->|reads| T
    C <-->|"impl-plan Notes, coder responses"| T
    C -->|"code + local commits"| G
    P -->|"branch setup, push, PR"| G
    O -->|"phase, log, approvals"| T
    P & R & C -.->|"read first, every time"| RU & L
    O -.->|reads| RU
```

Three rules the picture encodes:

- **Fresh reviewer, same author.** A new `q-reviewer` is spawned for every round, so it never inherits the author's reasoning. The planner and coder are continued with `SendMessage` so they keep their context.
- **Files are the hand-off.** The reviewer writes `review/plan-r1.md`; the planner appends `## Planner response` to the same file; the next reviewer reads both. Nothing important travels only in chat.
- **Only the coder writes code, only the reviewer writes reviews.** The planner writes plans and runs git. The orchestrator writes `index.md` and talks to you.

## The full flow (`/q-plan-impl`)

```mermaid
sequenceDiagram
    autonumber
    actor H as Human
    participant O as Orchestrator
    participant P as q-planner
    participant R as q-reviewer
    participant C as q-coder
    participant F as task folder

    Note over O: phase: planning
    O->>P: spec+plan
    P->>F: plan.md (§0 spec + plan)
    P-->>O: report (+ NEEDS_HUMAN if ambiguous)
    opt blocking questions
        O->>H: ask
        H-->>O: answers
        O->>P: finish plan
    end
    O->>R: mode plan, round 1
    R->>F: review/plan-r1.md
    R-->>O: verdict
    opt NOT APPROVED with a blocker
        O->>P: revise (plan-r1.md)
        P->>F: plan.md + Planner response
        O->>R: round 2 (delta)
    end

    Note over O,H: GATE 1
    O->>H: plan summary
    H-->>O: approve / feedback

    Note over O: phase: impl-planning
    O->>P: branch+impl-plan
    P->>F: impl-plan.md (branch created in repo)
    O->>R: mode impl-plan, round 1
    R->>F: review/impl-r1.md
    Note over O: phase: ready (not a gate)

    Note over O: phase: impl
    loop one coder per repo, in plan order
        O->>C: implement, scoped to repo
        C->>F: ticks impl-plan.md, fills its Notes
        C-->>O: commits, checks
    end

    Note over O: phase: impl-review
    par round 1
        O->>R: mode code, round 1
        R->>F: review/code-r1.md
    and
        O->>O: /code-review (+ /security-review)
        O->>F: review/code-r1-codereview.md
    end
    O->>R: verify code-review findings, merge
    R-->>O: verdict
    opt NOT APPROVED
        O->>C: fix-findings (code-r1.md)
        C->>F: fixes + Coder response
        O->>R: round 2 (delta)
    end

    Note over O: phase: impl-done
    O->>P: pr-draft
    P->>F: draft-pr.md

    Note over O,H: GATE 3
    O->>H: PR title/body, commits
    H-->>O: OK to push
    O->>P: pr-open
    P->>P: pre-push checks, merge origin/main if behind
    opt merge conflict or broken check
        P-->>O: blocked
        O->>C: fix-findings (merge failure)
        O->>R: delta re-check
        O->>P: pr-open again
    end
    P->>P: push, gh pr create
    Note over O: phase: pr-open
    O->>H: PR URL

    Note over O,H: after merge: /q-plan-impl <slug> done
    O->>O: retro (missed / undocumented / stale)
    O->>F: Log line, phase: done, move to tasks-archived/
```

`/q-plan` is steps 1 to the end of impl-planning. `/q-impl` is impl through impl-done. `/q-plan-impl` is all of it. Each resumes from `phase:` in `index.md`.

## Phases and artifacts

| Phase | Who acts | Writes | Human? |
|---|---|---|---|
| `planning` | planner, reviewer | `plan.md` (§0 spec), `review/plan-rN.md` | only if the planner raises blocking questions |
| `gate-1` | nobody | `index.md` phase | **yes: approve plan** |
| `impl-planning` | planner, reviewer | branch, `impl-plan.md`, `review/impl-rN.md` | no |
| `ready` | nobody | `impl-plan.md` status: agreed | may read, not required |
| `impl` | coder (per repo) | code, local commits, `impl-plan.md` Notes | no |
| `impl-review` | reviewer + `/code-review`, coder for fixes | `review/code-rN.md`, fix commits | no |
| `impl-done` | planner | `draft-pr.md` | no |
| `gate-3` | nobody | `index.md` phase | **yes: OK to push and open PR** |
| `pr-open` | planner | push, PR | no |
| `done` | orchestrator | retro (lessons added or removed), archive to `tasks-archived/` | says "done" or "archive" after the merge |

After the PR exists, `/q-pr-resolve <PR>` runs a short separate loop: reviewer triages each comment into fix / invalid / out-of-scope / escalate, the coder fixes the `fix` bucket, one reviewer re-check, push.

## Which skill spawns what

| Skill | q-planner | q-reviewer | q-coder | Other |
|---|---|---|---|---|
| `/q-plan` | spec+plan, revise, branch+impl-plan | plan, impl-plan | | |
| `/q-impl` | | code (r1 full, r2+ delta) | implement, fix-findings | `/code-review`, `/security-review` |
| `/q-plan-impl` | all of the above + pr-draft, pr-open | all of the above | all of the above | |
| `/q-pr-resolve` | | pr-triage, pr-recheck | fix-findings | reuses `pr-resolve` skill's fetch logic |

## Review loop in one picture

```mermaid
flowchart LR
    A[Author writes] --> R1[Fresh reviewer<br/>full review]
    R1 -->|APPROVED| M{open minors?}
    M -->|yes| F1[Author fixes or waives<br/>no re-review] --> D([done])
    M -->|no| D
    R1 -->|NOT APPROVED<br/>blocker/major| A2[Same author revises<br/>accept or rebut with evidence]
    A2 --> R2[Fresh reviewer<br/>delta: open findings + revision diff only]
    R2 -->|APPROVED| M
    R2 -->|still open at cap| E([Escalate to human])
    R1 & R2 -->|ESCALATE| E
```

Caps: plan 1 round (+1 for a blocker), impl-plan 1 (+1 for blocker/major), code 2 (+1 for a blocker), pr-resolve 1 (+1 for a blocker). Only blockers and majors cost a round.

## Related docs

- `~/Documents/z-agent/worker/docs/agent-workflow.md`: usage manual for the `/q-*` commands.
- `~/Documents/z-agent/worker/tasks/agent-workflow/plan.md`: the original design and its rationale.
- `q-workflow/RULES.md`: the shared contract (files, phases, loop rules, branch guard, quality gate, style).
