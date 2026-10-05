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

## Next
Brainstorm milestone 1: one ticket, unattended BUILD and review loop with the work project's gates, ending at "ready, not pushed".
