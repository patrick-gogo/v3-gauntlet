---
name: ticket-workspace
description: Reference for the /v3-ticket pipeline - workspace layout, state keys, phase machine, ruling and finding formats, and the shared scripts. Read by every ticket stage skill; use when any /v3-ticket stage starts.
---

# Ticket workspace

`SKILL_DIR` is this skill's base directory; its scripts run as `bash "$SKILL_DIR/scripts/<name>.sh"`. Stage skills call them as `bash "$SKILL_DIR/../ticket-workspace/scripts/<name>.sh"`.

## Location
`bash "$SKILL_DIR/scripts/ticket-ws.sh" path <id>` → `~/.v3-gauntlet/tickets/<repo>/<id>/` (`TICKETS_HOME` overrides the root). The same path from every worktree of the repo. Never inside the project, never under `~/.claude/` (Claude Code refuses writes there).

## Layout
```
state.md        machine-readable "key: value" lines (below); change only via state.sh
ticket.md       ticket text verbatim (+ "## English translation" when it was in another language)
bar.md          acceptance criteria AC1..ACn, plus a "Deferred:" list
context.md      how the touched code works today (PLAN step 5)
design.md       approved design
plan.md         approved plan (round 2 appends tasks under "## Round 2")
rulings.md      binding rulings
scope.txt       allow:/forbid: lines for scope-check.sh
ledger.md       one line per completed step; state.sh appends phase changes
baseline.md     gate results on the base commit
briefs/task-N.md, reports/task-N.md
v3-review/    the review loop's own workspace (state, logs, rounds, report.md)
handoff.md      the SHIP report; pr-body.md the draft PR body
```

## State keys
`ticket`, `title`, `phase`, `branch`, `base` (sha), `base_branch`, `checkout` (`main` or the worktree path), `depth` (`lite`|`standard`|`full`), `tasks_total`, `tasks_done`, `round2` (`no`|`yes`), `budget_impl_max`, `budget_impl_used`, `budget_review_max`, `gate.<name>` (command), `gate_timeout`, `exit_pair` (`none` or the exit-pair flags), `pr_target`, `pr_url`, `preflight` (`done`), `type` (`feat`|`fix`), `graded` (path to `graded.md`), `issue_url` (GitHub issue URL, set at intake; CLOSE closes the issue by it), `parallel` (`on`|`off`), `card` (`done` once the queue card exists), `push_approved` (`yes` once the user approved the PR; SHIP sets it right before pushing).

## Phases
`bash state.sh <WS>/state.md phase <new>` is the only way to change phase; it refuses illegal jumps and logs every change.

**Guard hook.** While a ticket is open, the plugin's PreToolUse hook (`hooks/guard.sh`) blocks `git push` from the ticket branch before phase `pr` unless `push_approved: yes`, and blocks `git commit` on the ticket's `base_branch` from `approved` to `handoff` (including `blocked` and `round2`). It always blocks tool attribution in commits and PRs. A block is a message to act on (commit on the ticket branch; push only from SHIP), never a reason to work around the hook.
```
intake → designed → planned → approved → implementing → reviewing ⇄ fixing → ready
implementing | reviewing | fixing → blocked
ready | blocked → handoff → round2 → implementing ...      handoff → pr → closed
```
`approved` is **Planned** on the queue board: the plan and its rulings are approved and the ticket waits to be queued. PLAN never moves past it; BUILD starts from it only when asked (`/v3-ticket <id> build`) or when a lap picks the ticket up.

| Phase | Stage skill |
|---|---|
| none, intake, designed, planned | `v3-gauntlet:ticket-plan` |
| approved | waiting in the queue; `v3-gauntlet:ticket-build` only with `build` |
| round2, implementing, reviewing, fixing | `v3-gauntlet:ticket-build` |
| ready, blocked, handoff | `v3-gauntlet:ticket-ship` |
| pr | `v3-gauntlet:ticket-close` |
| closed | nothing left to do |

## Worktrees
If `checkout` is a worktree path and the session is not inside it, call the `EnterWorktree` tool with `path` set to it before running any stage. A worktree created with plain `git worktree add` outside the repo is not writable from the session.

## Project config
A work project may hold `.claude/v3-gauntlet.md` (keep it out of git: it can hold project details). Every key is optional; without the file the stages use their generic behaviour.
```
queue: notion | none              PLAN adds the ticket to the queue board when it reaches Planned
repo_label: <name>                value for the board's Repo column
base_branch: <branch>             default: the remote's default branch
branch_prefix.fix: <prefix>       e.g. bugfix (default: the type, fix)
branch_prefix.feat: <prefix>      e.g. feature (default: feat)
branch_keep_id_case: yes | no     keep V3-12 instead of v3-12 in branch names
translate: yes | no               add an English translation to ticket.md (default yes)
context_agent: <agent name>       read-only agent PLAN asks about the touched code
planner_agent: <agent name>       its definition is passed to the planner as the project's conventions
reviewer_agent: <agent name>      extra "conventions" critic in /v3-review; copied into the lap rules
lap_stop_time: HH:MM              no new ticket starts in a lap after this time (default 06:30)
lap_timezone: <tz>                for the stop time (default Asia/Manila, the devbox's zone)
lap_parallel: on | off            tickets in a lap at once (default off)
lap_worktree_dir: <path>          where /v3-lap makes its clean temporary copy

## Intake
<how to read a ticket: which tool, which site; free text>

## Tracker status
<how to move the user's own To Do ticket to In Progress at intake; free text, read on the laptop>

## Gates
<name>: <command>                 a lap replaces {base} with the frozen base commit

## Stack
<how to bring the project's stack up and down on the build machine; copied into the lap rules>

## House rules
<project rules the builder and critics follow; copied into the lap rules>

## Push day
<how to open PRs and announce them after "push"; free text, read on the laptop>
```
The queue's token is never in this file: `notion-queue.mjs` reads `NOTION_TOKEN` and `GAUNTLET_QUEUE_DB` from the environment or `~/.config/v3-gauntlet/notion.env`.

## Rulings
Every decision a stage makes on its own is a ruling. Nothing waits for the user: the stage takes its recommendation and the user reviews the rulings in a batch (PLAN step 8; the handoff after BUILD).

Levels:
- **T1**: an obvious technical choice with a clear best answer (a helper's name, which existing component to reuse, a test layout).
- **T2**: a choice the product owner would make (required or optional, a length limit, a default value, wording shown to users).
- **T3**: a business decision (a new feature, a changed rule, money, tax, anything legal).
- Unsure between two levels: take the higher one.

## Formats
Ruling (`rulings.md`):
```
R3 — <title> (source: planner | orchestrator | user, level: T1 | T2 | T3)
Decision: ... / Why: ... / Alternative: ... / Cost if wrong: low | medium | high / Applies to: all | task N
```
`source: user` means the user kept or changed it in a batch. A `## Batch <k>` section in `rulings.md` lists which rulings batch k asked about, numbered from 1, each with its `R` number.
Finding: the format in `v3-gauntlet:final-reviewer` (ID, Severity, Kind, Location, Trigger, Expected, Actual).
Ledger line: `<UTC time> <step> <result>`. Ledger time: always `date -u +%Y-%m-%dT%H:%M:%SZ`.

## Scripts
| Script | Use |
|---|---|
| `state.sh <state.md> get/set/incr/phase ...` | state and phases |
| `ticket-ws.sh path/init/list` | workspace location |
| `branch-name.sh [--prefix p] [--keep-id-case] <type> <id> <title...>` | branch name |
| `ruling-reply.sh <n> "<reply>"` | parse a batch reply into `<k> keep` / `<k> change <text>` lines; exit 2 names what is missing or unclear |
| `node notion-queue.mjs check / list [--status S] / upsert --key K --title T [...] / status --key K --status S [...]` | the queue board (exit 1 key not in queue, 2 bad input, 3 could-not-run) |
| `waves.sh <plan.md>` | parallel waves from `Files:` and `Depends on:` |
| `pr-state.sh <pr>` | merged / open / closed-unmerged / could-not-run |
| `pr-state.sh --head-matches <pr> <branch>` | same / differs / could-not-run: local branch tip vs the PR head |
| `secret-scan.sh [--deny-file f] <file or ->...` | secrets before a PR |
