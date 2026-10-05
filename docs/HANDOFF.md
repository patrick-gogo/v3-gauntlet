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

## Next
Items 6 to 14: V3 project config with gates, `docs/gauntlet/RULES.md` template, `/v3-lap`, handoff format, SHIP split. Then a manual mini-lap.
