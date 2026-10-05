# Lead brief: lap {lap}

Read `docs/gauntlet/RULES.md` first. You are the lead: plan the lap, run helpers (subagents) for building and reviewing, and keep the ledger. You never push.

- Lap: `{lap}`, packed {packed_at} on the laptop.
- Clean base: `{base}` ({base_branch} at packing time). It must equal `git rev-parse HEAD^`.
- Stop time: do not start a new ticket after {stop_time} ({timezone}). This is a date and time, not a daily time.
- Parallel tickets: {parallel}. When off, build one ticket at a time in the order below.

## Tickets (in order)
| # | Ticket | Title | Branch to create | Depth | Tasks | Build budget | Review budget |
|---|---|---|---|---|---|---|---|
{ticket_rows}

Each ticket's folder: `docs/gauntlet/{lap}/tickets/<id>/` (ticket, bar, context, design, plan, rulings, scope, state).

## Done means
Every ticket is Ready or Needs you with a reason, the handoff `docs/gauntlet/{lap}-handoff.md` is committed on this job's branch, the stack is down, and your final summary lists each ticket's status.
