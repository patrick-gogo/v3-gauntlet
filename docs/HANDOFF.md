# Handoff

Forked on 2026-10-05 from [beefysalad/patrick-workflows](https://github.com/beefysalad/patrick-workflows) at `5682a8a` (v0.9.0), to fit the pipeline to one work project and run it unattended.

## Renamed in the fork
| Was | Now |
|---|---|
| plugin `patrick-workflows` | `v3-gauntlet` (v0.1.0) |
| `/start` | `/v3-ticket` |
| `/gauntlet-review` | `/v3-review` |
| `~/.patrick-workflows/` | `~/.v3-gauntlet/` |
| `PATRICK_WORKFLOWS_GUARD` | `V3_GAUNTLET_GUARD` |
| `.claude/patrick-workflows-deny.txt` | `.claude/v3-gauntlet-deny.txt` |

Removed: the `hello` skill, `example-reviewer` agent, and the upstream design specs and plans (still in git history). Kept: `docs/superpowers/spikes/`, which the skills cite as evidence.

## Rules that always apply
- Public repo: nothing employer-specific (see README "Rules").
- No tool attribution in commits or PR text. `scripts/validate.sh` enforces it.
- Conventional Commit messages. Ask before pushing.
- Checks: `./scripts/validate.sh`, `bash tests/run.sh`, `claude plugin validate .`.
- Generic fixes can go back upstream with a cherry-pick (`upstream` remote).

## Done: items 1 to 5 (2026-10-05, v0.2.0)
The full plan (change list 1 to 20, decisions, order) is on the Notion page "v3-gauntlet: build plan (locked 2026-10-05)" under V3 Dev Hub. The target flow is pictured in `docs/flow.html`.
- `notion-queue.mjs`: queue board client over the Notion API (`check`, `list`, `upsert`, `status`); 16 Node tests. Live round-trip against the real board passed. Uses `process.exitCode`, never `process.exit()` (that aborts Node on Windows after a fetch).
- `ruling-reply.sh`: parses batch replies; 17 checks.
- `branch-name.sh`: `--prefix`, `--keep-id-case`; 13 checks.
- PLAN rewritten: go-ahead rulings tagged T1/T2/T3, one batch at the end, translation, project-config intake, stops at Planned and adds the board row; never starts BUILD. `/v3-ticket <id> build` builds locally.
- Full suite: only the 4 known Windows-only failures (no `python3` in Git Bash, a dev-server timing check, a fixture check).
- Notion setup done on the laptop (`~/.config/v3-gauntlet/notion.env`). Not on the devbox: SSH into the space is unknown, so the laptop does every board update for now.

## Devbox spike results (2026-10-05)
- Space: 8 CPUs, 12 GB RAM, no swap. Docker and compose work; node, python3, git, gh, jq, perl, timeout, setsid present; `uv` and `psql` missing.
- No plugins or skills in the space: the lap's rules must travel as repo files (`docs/gauntlet/RULES.md`).
- `devbox-git push` folds uncommitted laptop edits into one snapshot commit on top of the laptop HEAD. Ticket branches must start from the snapshot's parent, never the snapshot.
- No git remote and `gh` not logged in inside jobs. Notion API reachable; no token there.
- The V3 stack, a backend pytest file, the ruff ratchet (pip venv, no uv), a frontend build and a Playwright smoke test all ran unattended from a clean worktree. Cold start about 10 minutes. Some backend tests already fail on clean master, so known reds from the baseline matter. Fixed ports: one stack at a time.

## Built: items 6 to 14 (2026-10-05, v0.3.0), not yet run in a real lap
- `/v3-lap` (`skills/lap/`, `commands/v3-lap.md`): start (clean worktree at the base, `lap-pack.sh`, `RULES.md` + lead brief, `devbox-git push`, `start_agent` lead, board Running), `result` (fetch, read the handoff from the job branch, board Ready / Needs you), `answer` (parse, record, follow-up for round 2), `push` (laptop push day).
- `lap-pack.sh` (18 checks) and `lap-check.sh` (12 checks). `state.sh` allows `approved -> pr` for lap-built tickets.
- `skills/lap/templates/RULES.md`: rails, stages (GO, freeze base, baseline, build test-first, task review, ticket review, wave, run, triage, exit pair, handoff), round 2, statuses, budgets, rulings, findings, handoff format.
- Project agents: `planner_agent` is passed to the planner as conventions (format and test commands stay the plugin's, because the work project's planner writes another format for a Windows test runner); `reviewer_agent` is an extra conventions critic in `/v3-review` and is copied into `RULES.md` for the devbox.
- SHIP's "Rebase" option is now "Merge the base in"; the plugin never rebases.
- The work project's private config lives in its own `.claude/v3-gauntlet.md` (git-ignored there).

## Caveats and behaviours to know
Setup
- **No GitHub token on the devbox** (the optional field was left empty) and jobs have **no git remote**: jobs cannot push or open PRs. Push day is `/v3-lap push` on the laptop. Adding a token later would allow devbox pushes, but the plugin does not use that.
- **No Notion token on the devbox.** SSH into the space was refused for the user's key at both the relay and the LAN address; the right host or port is unknown. The board is updated by the laptop only: Running at `/v3-lap`, Ready / Needs you at `/v3-lap result`. It does not move overnight.
- **Notion token on the laptop only**, in `~/.config/v3-gauntlet/notion.env`, shared with the queue database alone. It can create and update cards, not delete them.
- **The Atlassian Rovo connection on the laptop is logged in as a different person**, so tracker reads use the Composio connection first (set in the private config's Intake).
- **The devbox runs on a shared Claude account.** The stop time (default 06:30 Asia/Manila) keeps a lap from starting new tickets right before the workday.

Devbox behaviour
- **No plugins or skills in the space** (no superpowers, no v3-gauntlet, no user agents). Everything the lead follows is in `docs/gauntlet/RULES.md`.
- **`devbox-git push` snapshots uncommitted work into a commit** on top of HEAD. A lap is packed from a clean worktree at the base so local edits never go; never run real lap work with the bare devbox commands from a dirty checkout.
- **Only `refs/heads/devbox/*` comes home** with `devbox-git fetch`. Ticket branches must be `devbox/<lap>/<branch>`.
- **Job summaries are truncated** to their last part. The handoff file on the job branch is the record. A follow-up to the same job can ask for a short re-statement.
- **`wait_for_agents` returns "timed out" well before its 600 s**; poll `get_result` / `list_agents` instead of trusting the wait.
- **Space:** 8 CPUs, 12 GB RAM, no swap; `uv` and `psql` missing (ruff ratchet runs from a pip venv). The work project's own MCP server fails there (Windows path), harmlessly.
- **Stack:** fixed ports, one stack at a time; cold start about 10 minutes with the frontend build. Some backend tests already fail on the base: they are known reds. The work project's `pytest.ini` uses a `[tool:pytest]` header pytest ignores.

Laptop and repo
- **The frontend unit-test gate (Jest) was not run in the devbox spike**; only the ruff ratchet, a backend pytest file, a frontend build and a Playwright smoke test were.
- **First real lap not run yet.** `RULES.md`, the lead brief and `/v3-lap result|answer|push` are unproven; expect fixes after lap 1.
- **Windows:** Git Bash has no `python3`, so 4 checks fail (validate JSON x2, a dev-server timing check, a fixture check). Node's `process.exit()` after a fetch aborts on Windows; the queue client sets `process.exitCode` instead.
- **Guard hook:** while a ticket is Planned (phase `approved`), commits on its base branch are blocked in that checkout.
- **Public repo:** commits so far carry the author's work email; company values stay in the private config.

## Next
Lap 1: plan one small ticket with `/v3-ticket`, drag it to Queued, run `/v3-lap`, then `result` / `answer` / `push`. Fix what it shows.
