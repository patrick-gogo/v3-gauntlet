---
description: Plan a ticket without stopping (rulings reviewed in one batch at the end), add it to the queue as Planned, and build, review and ship it later
argument-hint: "[ticket id | url | pasted text] [build]"
---

Route this ticket using the `v3-gauntlet:ticket-workspace` skill's phase table.

1. Arguments: $ARGUMENTS. A trailing word `build` is a flag, not part of the ticket.
2. No argument: run `bash "<ticket-workspace skill dir>/scripts/ticket-ws.sh" list`. If the project config says `queue: notion`, also run `node "<ticket-workspace skill dir>/scripts/notion-queue.mjs" list --status Inbox` (exit 3: skip it and say the board could not be read). Show both lists and ask which ticket to plan or continue, or to paste a new one.
3. Turn a URL into its ID first (issue key such as `ABC-123`, or `#<number>` for `.../issues/<number>`). An ID whose workspace exists (`ticket-ws.sh path <id>` is a directory): read its `phase` with `state.sh`, enter its worktree first if `checkout` is a worktree path (see the skill's Worktrees section), then:
   - `in-lap`: say which lap is building it (`lap` in its state) and that `/v3-lap result` brings it home; never build it here.
   - `approved` (Planned): with `build`, invoke `v3-gauntlet:ticket-build`. Without it, say the ticket is Planned and waiting in the queue, and that `/v3-ticket <id> build` builds it here instead.
   - `pr`: invoke `v3-gauntlet:ticket-close`. `closed`: say the ticket is finished.
   - Any other phase: invoke the stage skill the phase table names.
4. Otherwise it is a new ticket: invoke `v3-gauntlet:ticket-plan` with the argument.
