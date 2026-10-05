---
name: lap
description: Run Planned tickets as an unattended gauntlet lap on the devbox - pack the Queued tickets with the lap rules into the repo, start a devbox lead, bring the results and handoff home in the morning, forward the owner's answers as round 2, and do push day from the laptop. Used by /v3-lap.
---

# Lap

Read `v3-gauntlet:ticket-workspace` first (project config, rulings, scripts). `TW` = `$SKILL_DIR/../ticket-workspace/scripts`. `Q` = `node "$TW/notion-queue.mjs"`. `CFG` = the project config `.claude/v3-gauntlet.md`.

**Where things run.** The laptop packs, starts, fetches and pushes. The devbox lead builds, reviews, tests and writes the handoff, following `docs/gauntlet/RULES.md`. The devbox has none of these plugins: everything the lead needs travels as files in the repo.

**Laptop rules.**
- Never send the user's working checkout to the devbox: a lap is packed and pushed from a **clean temporary worktree at the base**, so local uncommitted edits never leave the laptop.
- `docs/gauntlet/` is never committed in the user's checkout and never pushed to GitHub.
- The board never blocks a lap: a `could-not-run` from `notion-queue.mjs` is reported in one line and the lap goes on.

## Finding devbox
- `DG` = the newest `~/.claude/plugins/cache/devbox/devbox/*/scripts/devbox-git` (`ls -1 ... | sort -V | tail -1`). None → stop: the devbox plugin is not installed (`/plugin install devbox@devbox`, then `/devbox:setup`).
- Start, follow-up and result go through the devbox MCP tools (`start_agent`, `get_result`, `wait_for_agents`, `send_followup`); load them with ToolSearch if they are deferred.
- `REPO` = the main checkout's folder name (what `devbox-git push` prints as `repo=` from the main checkout). Always pass it explicitly: `bash "$DG" push "$REPO"`, `bash "$DG" fetch "$REPO"`.

## Lap record
`LR` = `~/.v3-gauntlet/laps/<repo>/<lap>/` (`TICKETS_HOME`'s parent overrides `~/.v3-gauntlet`). `lap.md` holds `key: value` lines written with `bash "$TW/state.sh" "$LR/lap.md" set <key> <value>`: `lap`, `job`, `job_branch`, `base`, `base_branch`, `tickets` (space-separated IDs), `status` (`running`, `returned`, `round2`, `pushed`), `started`, `returned`. `packed/` keeps a copy of what was sent; `handoff.md` the latest handoff.

## /v3-lap (start)
1. **Tickets.** Given IDs → those. Otherwise, with `queue: notion`, `$Q list --status Queued` (the order is the board's Order). For each: `WS=$(bash "$TW/ticket-ws.sh" path "<id>")`; its `phase` must be `approved` (Planned). Skip any other ticket with its reason (not planned on this laptop, still planning, already built). None left → say so and stop.
2. **Lap id:** `lap-$(date +%Y%m%d-%H%M)`. Stop time: `CFG` `lap_stop_time` (default `06:30`) in `lap_timezone` (default the space's `Asia/Manila`), as a date and time, never a bare time: `STOP=$(node "$SKILL_DIR/scripts/stop-time.mjs" <lap_stop_time> <lap_timezone>)` (exit 2: bad time or zone in `CFG`, say so and stop). Parallel: `CFG` `lap_parallel` (default `off`: one ticket at a time, as the house rule "one heavy thing at a time" suggests).
3. **Clean worktree.** `B=<CFG base_branch or the remote default>`; `git fetch origin "$B" -q`; `BASE=$(git rev-parse "origin/$B")`. `WT="<CFG lap_worktree_dir, else <parent of the main checkout>/<repo> worktrees>/gauntlet-<lap>"` (the folder name may hold a space, so always quote it); `git worktree add --detach "$WT" "$BASE"`.
4. **Pack:** `bash "$SKILL_DIR/scripts/lap-pack.sh" "$WT" "<lap>" "<WS>"...`. Exit 2 → show the reasons, remove the worktree, stop.
5. **Rules:** write `"$WT/docs/gauntlet/RULES.md"` = `"$SKILL_DIR/templates/RULES.md"` followed by `CFG`'s `## Gates`, `## Stack` and `## House rules` sections copied verbatim (under those headings). No such section in `CFG` → write `## Gates` with the tickets' recorded `gate.<name>` commands and say the stack is not described. When `CFG` names a `reviewer_agent`, append `## Project conventions review` with that agent's instructions (its definition file without the frontmatter, from `.claude/agents/<name>.md` in the project or `~/.claude/agents/<name>.md`): the devbox has no agents, so the lead's conventions critic reads them from here.
6. **Brief:** write `"$WT/docs/gauntlet/<lap>/lead-brief.md"` from `"$SKILL_DIR/templates/lead-brief.md"`: `{lap}`, `{packed_at}` (`date -u +%Y-%m-%dT%H:%M:%SZ`), `{base}`, `{base_branch}`, `{stop_time}` (`$STOP`), `{timezone}`, `{parallel}`, and one `{ticket_rows}` line per ticket from `tickets.tsv` plus its state (`budget_impl_max`, `budget_review_max`): `| <n> | <id> | <title> | devbox/<lap>/<branch> | <depth> | <tasks> | <impl budget> | <review budget> |`.
7. **Send:** from `$WT`, `bash "$DG" push "$REPO"`; note `base=` (the snapshot ref). Then `start_agent` with `mode: lead`, `source: local`, `repo: $REPO`, `base: <that ref>`, `title: "Gauntlet lap <lap>"`, `task:` exactly
   `Run the gauntlet batch in docs/gauntlet/<lap>/lead-brief.md. Read docs/gauntlet/RULES.md first. The clean base is <BASE>; it must be the parent of your starting commit. Never push.`
8. **Record:** create `LR`, copy `"$WT/docs/gauntlet/"` to `"$LR/packed/"`, set `lap`, `job`, `job_branch` (from the start result), `base`, `base_branch`, `tickets`, `status running`, `started`. In each ticket's state: `set lap <lap>`. Board: `$Q status --key <id> --status Running --notes "lap <lap>, job <job>"`.
9. **Clean up:** `git worktree remove --force "$WT"` (everything in it was sent and copied to `packed/`).
10. Tell the user in a few lines: the lap id, the job id, the tickets in order, the stop time, and that they can close the laptop; `/v3-lap result` brings it home.

## /v3-lap result [lap]
Default lap: the newest record with `status running` or `round2`.
1. `get_result <job>`. Still running → say so (and how long), stop.
2. `bash "$DG" fetch "$REPO"`. The job's branch arrives as `refs/remotes/<job_branch>` (it already starts with `devbox/`), each ticket branch as `refs/remotes/devbox/<lap>/<branch>`.
3. Read the handoff from the job branch: `git show "refs/remotes/<job_branch>:docs/gauntlet/<lap>-handoff.md"` (round 2: `<lap>-handoff-r2.md`). Missing → the lead did not finish: show its summary, mark every ticket Needs you on the board, stop. Save it as `"$LR/handoff.md"`; `set status returned`, `set returned <time>`. Then put it on each ticket's card: for each ticket, `$Q page --key <id> --file "$LR/handoff.md" --child "Handoff <lap>"`. Any failure (exit 1 card missing, 2 bad input, 3 could-not-run) is one line and the step goes on.
4. **Board:** for each ticket row in section 1: `Ready` → `$Q status --key <id> --status Ready --notes "lap <lap>: ready"`; anything else → `--status "Needs you" --notes "lap <lap>: <reason>"`.
5. Show the user section 0 (the questions with picks) and section 1 (the ticket table), and the path to the full handoff. Answers go back with `/v3-lap answer`; ready tickets go out with `/v3-lap push`.

## /v3-lap answer [lap] "<reply>"
1. Count section 0's questions; parse with `bash "$TW/ruling-reply.sh" <n> "<reply>"` (exit 2 → show it and ask again). Free-text answers to yes/no questions are allowed: forward them verbatim.
2. Record the answers in each ticket's `rulings.md` as `source: user` rulings (T-level from the question).
3. If any answer asks for a change: `send_followup <job>` with `Owner's answers to section 0 of docs/gauntlet/<lap>-handoff.md: <the parsed lines>. Run round 2 as RULES.md section 3 says. Never push.`; `set status round2`; board `Running` for the tickets that change. Otherwise nothing is sent.

## /v3-lap push [lap] [ids]
Only on the user's explicit word. Default: every ticket the handoff marks Ready whose last question ("Ready tickets go to push day?") was answered yes, or the IDs given.
For each ticket:
1. `R=refs/remotes/devbox/<lap>/<branch>`. `bash "$SKILL_DIR/scripts/lap-check.sh" "$R" "<base>"`. Not ok → show why, skip this ticket.
2. Local branch: `git branch "<branch>" "$R"`. If `<branch>` already exists locally and differs, stop for this ticket and ask (never overwrite a local branch).
3. Secrets: `git diff "<base>..<branch>" | bash "$TW/secret-scan.sh" [--deny-file .claude/v3-gauntlet-deny.txt] -`. Any hit → show rule and location (never the value), skip this ticket.
4. In the ticket's state: `set push_approved yes` (the guard hook blocks the push without it), `set branch <branch>`.
5. Push and open the PR as `CFG`'s `## Push day` section says. Without that section: `git push -u origin <branch>`, then `gh pr create --draft --base <base_branch> --title "<type>(<id>): <title>" --body` built from the ticket's bar, the handoff's evidence and rulings for that ticket. No tool attribution of any kind.
6. `set pr_url <url>`, `bash "$TW/state.sh" "<WS>/state.md" phase pr`; board `--status "PR open" --report <url>`.
Then `set status pushed` on the lap if every ticket is done or skipped, and list the PR URLs. After a merge, `/v3-ticket <id>` closes the ticket as usual.
