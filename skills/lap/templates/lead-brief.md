# Lead brief: lap {lap}

Read `docs/gauntlet/RULES.md` first. You are the lead: plan the lap, run helpers (subagents) for building and reviewing, and keep the ledger. You never push.

- Lap: `{lap}`, packed {packed_at} on the laptop.
- Clean base: `{base}` ({base_branch} at packing time). It must equal `git rev-parse HEAD^`.
- Stop time: do not start a new ticket after {stop_time} ({timezone}). This is a date and time, not a daily time.
- Commit identity: {git_name} <{git_email}>. Set it in every worktree before the first commit.
- Parallel tickets: {parallel}. When off, build one ticket at a time in the order below.
- Models (RULES rail 15): helper model `{helper_model}` (implementers, task reviewers); critic model `{critic_model}` (ticket critics, challenger, final review panel, cross-branch audit). `inherit` means your own model.

## Tickets (in order)
| # | Ticket | Title | Branch to create | Depth | Tasks | Build budget | Review budget |
|---|---|---|---|---|---|---|---|
{ticket_rows}

Each ticket's folder: `docs/gauntlet/{lap}/tickets/<id>/` (ticket, bar, context, design, plan, rulings, scope, state, and `prior-art/` when the owner's notes were searched). Lessons from earlier tickets: `docs/gauntlet/{lap}/learnings/`.

{resume_note}

## Done means
Every ticket is Ready or Needs you with a reason, every Ready ticket has `docs/gauntlet/{lap}/tickets/<id>/final-review.md` (RULES 2.8b), this round's handoff (`docs/gauntlet/{lap}-handoff.md`, round k > 1: `-handoff-r<k>.md`) is committed on this job's branch, the stack is down, and your final summary lists each ticket's status.
