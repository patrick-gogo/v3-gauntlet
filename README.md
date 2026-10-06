# v3-gauntlet

An unattended ticket pipeline for Claude Code, packaged as a plugin. Forked from
[beefysalad/patrick-workflows](https://github.com/beefysalad/patrick-workflows) and being fitted to one
work project. The plan is to run it unattended on a Linux host.

## Install

```
/plugin marketplace add patrick-gogo/v3-gauntlet
/plugin install v3-gauntlet@v3-gauntlet
```

Local checkout: `/plugin marketplace add /path/to/v3-gauntlet`

## Update

```
/plugin marketplace update v3-gauntlet
/plugin update v3-gauntlet@v3-gauntlet
```

Restart Claude Code afterwards. Installs are cached by `version`, so a change
only reaches other machines after `version` is bumped in
`.claude-plugin/plugin.json`.

## Layout

| Path | What |
|---|---|
| `skills/<name>/SKILL.md` | Skills |
| `commands/<name>.md` | Slash commands |
| `agents/<name>.md` | Subagents |
| `hooks/` | PreToolUse guard (`guard.sh`, registered in `hooks.json`) |
| `templates/` | CLAUDE.md and settings.json to copy manually (plugins can't ship these) |
| `skills/lap/templates/` | the lap rules (`RULES.md`) and lead brief `/v3-lap` writes into the repo |

## /v3-ticket

```
/v3-ticket ABC-123        plan a ticket, or continue one (ID, URL, or pasted text)
/v3-ticket ABC-123 build  build a Planned ticket here instead of waiting for a lap
/v3-ticket                list tickets in this repo (and the queue's Inbox)
```

- **PLAN (on its own, then one stop):** reads the ticket (and translates it when it is not in English), settles acceptance criteria, reads the touched code, brainstorms the design, writes the plan and the autonomy brief (gates, scope, review depth, budget, parallel waves). Every open question is decided with its recommendation and logged as a ruling, tagged T1/T2/T3. Then it shows one batch: answer `1 keep 2 change: <what> 3 keep` or `all keep`. Changes go into the plan and only the changed rulings come back. When a batch is all keep, the ticket is **Planned** and lands on the queue board. PLAN never creates the branch or starts BUILD.
- **BUILD (on its own):** creates the branch from the recorded base, one fresh implementer and reviewer per task, test first, gates re-run by the orchestrator, then the `/v3-review` loop. Asks nothing.
- **SHIP (with you):** one report with numbered questions. Ask for changes and it runs a second round; say yes and it scans for secrets, then opens a draft PR.

Run `/v3-ticket <id>` again at any time to resume where it stopped. If another plugin also defines `/v3-ticket` or `/v3-review`, use the namespaced form: `/v3-gauntlet:v3-ticket`, `/v3-gauntlet:v3-review`. Working files live in `~/.v3-gauntlet/tickets/<repo>/<id>/`. After the PR is merged, run `/v3-ticket <id>` once more: it marks the ticket done (a GitHub issue is closed by the URL recorded at intake, never by bare number) and cleans up. After a squash or rebase merge it deletes the local branch with `-D` only when the branch tip is exactly the commit GitHub merged; otherwise it keeps the branch and says why.

**Project config.** A work project can keep its settings in `.claude/v3-gauntlet.md` (out of git): branch prefixes, how to read tickets, gates, the code-context agent, `queue: notion`, checkout strategy, and tracker integration. The keys are listed in the `ticket-workspace` skill.

**Queue board (Notion).** With `queue: notion`, PLAN adds each Planned ticket to a Notion database with the columns `Ticket` (title), `Key`, `Status` (Inbox, Planned, Queued, Running, Needs you, Ready, PR open, Done), `Order`, `Repo`, `Branch`, `Report`, `Notes`. One-time setup:
1. Create an internal integration at notion.so/my-integrations and copy its secret.
2. Open the database in Notion, then `•••` → Connections → add the integration (it sees only what you share with it).
3. Write `~/.config/v3-gauntlet/notion.env` (never into a repo):
   ```
   NOTION_TOKEN=<the secret>
   GAUNTLET_QUEUE_DB=<the database id from its URL>
   ```
4. Check it: `node <plugin>/skills/ticket-workspace/scripts/notion-queue.mjs check` prints `NOTION: ok (<database title>)`.

PLAN writes the tracker ticket (original and English translation) into the card body, and creates sub-pages for Design, Plan, and Rulings. When `/v3-lap result` brings a lap home, it adds a "Handoff <lap>" sub-page. Use `notion-queue.mjs page --key K --file <md> [--child "<Title>"]` to append markdown to a card and create sub-pages; the tool also converts the markdown to Notion blocks.

**Tracker integration.** When the project config has a `## Tracker status` section, PLAN moves the user's own To Do ticket to In Progress at intake. This flags the ticket as work-in-progress in the tracker.

**Checkout strategy.** By default, a local BUILD enters a worktree via the EnterWorktree tool, keeping your main checkout clean. Set `checkout: main` to work in the main checkout instead. On push day, the plugin never runs hooks in the main checkout: SHIP pushes from the ticket's worktree (or a temporary one with `checkout: main`), and a lap pushes from a temporary worktree with `--no-verify` unless `push_skip_hooks: no` is set.

The board never blocks PLAN: if Notion cannot be reached, PLAN says so and you add the card by hand.

Optional: list company names and internal hostnames, one per line, in your work project's `.claude/v3-gauntlet-deny.txt`. SHIP refuses to open a PR whose body or diff contains them.

Permission rules: absolute paths outside your home directory need a leading `//` (for example `Edit(//opt/data/**)`); paths under your home use `~/`.

## /v3-lap

Runs the queue's **Queued** tickets as an unattended lap on a devbox (an always-on machine reached through the devbox Claude Code plugin), in the gauntlet-loop style: build test-first, review with fresh critics, merge into a throwaway wave, run the gates and browser checks until two runs in a row are green, then hand off.

```
/v3-lap                     pack the Queued tickets and start a devbox lead; close the laptop
/v3-lap result              bring the night home: board updated, the handoff's questions shown
/v3-lap answer "1 keep 2 change: ..."   answer; changes start round 2 in the same devbox session
/v3-lap push                push day, only on your word: safety check, secret scan, push, draft PRs
```

The lap is sent from a clean temporary worktree at the base branch, never from your working checkout. It carries `docs/gauntlet/<lap>/` (the lead brief, each ticket's plan and rulings) and `docs/gauntlet/RULES.md` (the lap rules plus the project config's Gates, Stack and House rules). The devbox needs none of these plugins. Ticket branches come home as `devbox/<lap>/<branch>`; `lap-check.sh` refuses to push one that is not built on the clean base, has no commits, carries `docs/gauntlet/` files, or has tool attribution in a commit message.

**Final review.** Before handing off, the lead reviews each Ready ticket once more, the way you would review your own branch before a PR: four lenses (conventions, correctness, history, in-file guidance) plus an impact trace, written to `docs/gauntlet/<lap>/tickets/<id>/final-review.md` with the reviewed `head_sha`. `/v3-lap result` brings it home, puts it on the card, and copies it where the config's `## Review copy` says.

**Push day checks.** Before pushing, `/v3-lap push` checks how far the base branch has moved (`drift.sh`: commits behind, files changed on both sides, a real conflict stops the ticket), accepts the final review when the commits were only re-authored (`review-head.sh` compares trees), and otherwise runs a review first. It pushes from a temporary worktree, never the main checkout, skipping hooks by default because the gates ran in the lap. With a `## Review request` section it fills a review-request draft from the lead's handoff fields. A ticket with a pending change answer, or any ticket during round 2, is pushed only when you name it.

**Ticket records.** With a `## Ticket records` section in the project config, PLAN also creates the project's own per-ticket notes at intake (whatever a later review or guard expects).

### Known limits
- **Push day runs on the laptop.** Devbox jobs have no git remote and no GitHub login, so they never push; `/v3-lap push` does it from the laptop with your own credentials.
- **The board does not move overnight.** Devbox jobs have no Notion token, so `/v3-lap` marks tickets Running at the start and `/v3-lap result` moves them to Ready or Needs you in the morning.
- **No plugins on the devbox.** The lap's rules travel as files (`RULES.md`), including the test-first discipline; the quality of a lap depends on that file.
- **`devbox-git push` folds uncommitted changes into a snapshot commit.** That is why a lap is packed from a clean worktree. Never start real lap work from a dirty checkout with the bare devbox commands.
- **Only `devbox/...` branches come home** with `devbox-git fetch`.
- **Job summaries are cut to their last part** on the devbox; the handoff file on the job's branch is the record, not the summary.
- **One stack at a time.** A project stack with fixed ports and no swap means builds, test suites and browser runs take turns, and a cold start can take about 10 minutes.
- **Known reds.** Tests already failing on the base are recorded first and never count against a ticket; only new failures do.
- **Shared Claude accounts:** set `lap_stop_time` so a lap does not start new tickets right before the workday.

## /v3-review

Renamed from `/review-mine` in v0.9.0 so it no longer clashes with project-level skills of that name. Update allow rules from `skills/review-mine/scripts/*` to `skills/v3-review/scripts/*`. A ticket started before v0.9.0 keeps its review evidence under `review-mine/` in the ticket workspace; finish it on v0.8.x or start it again.

Reviews the current branch with fresh critics, keeps only findings that come with evidence, fixes Critical and Important ones with a failing test first, re-reviews the fixes with a new critic, and stops at an explicit PASS, a plateau, or the budget. It commits fixes to your branch and never pushes.

```
/v3-review [base] [--depth lite|standard|full] [--criteria <file>] [--scope <file>] [--graded <graded.md>]
             [--no-fix] [--prove "<cmd>" [--reset "<cmd>" --env-file <file> --db-pattern <regex>]]
```

**Parallel tasks.** `/v3-ticket`'s planner lists each task's files and dependencies; `waves.sh` groups tasks that share no files and do not depend on each other into waves. BUILD runs a wave's implementers at the same time, each in its own agent worktree, then cherry-picks their commits onto the ticket branch in plan order (a conflict reruns that task on its own) and reviews each task as usual. The brief shows the waves and a `parallel: on|off` switch (on by default; off for lite).

**Depths.** `lite` runs one Opus critic and fixes inline (budget 3 dispatches, 2 rounds). `standard` runs three critics and a fixer agent (budget 10, 4 rounds). `full` runs five critics (impact, security, regression, requirements, maintainability), then a `finding-challenger` (Opus) that tries to refute each Critical and Important finding from the code. Refuted findings never reach the fixer and are listed in the report under "Refuted by the challenger", where you can overrule them (budget 16, 4 rounds). `full` is only used when you ask for it; `/v3-ticket` suggests it for security-sensitive plans with more than 5 tasks.

**UI grading.** For features with a visual or interactive component, pass a graded scoring configuration file. The file defines reference screenshots (`image-dir:`, `route:` or `url:`), routes to capture, dev command, a `rubric:` line pointing to a rubric file (3–6 criteria with anchors for scores 1, 3, and 5), and thresholds (margin 0.3, floor 3.5, min 3). The reference is one page, compared with the first route in the routes file; rubric anchors describe qualities, never "same as the reference", and fixers are told not to copy it (a tie on every criterion is raised as a question in the report). The check passes when our score is at least the reference score minus 0.3, at least 3.5 overall, with no criterion below 3, and a second independent scorer agrees. The dev command and the screenshot tool run inside the plugin's scripts, so the `Bash(bash *skills/*/scripts/*)` rule covers them. A page that answers with a non-2xx HTTP status is not captured, and a graded bar that cannot run (dev server, capture or reference failure) ends the review BLOCKED with the reason. Screenshots use Playwright (default `npx --yes playwright screenshot --channel chrome`), which captures light and dark; only the headless Chrome fallback is light only. Requires `Bash(npx --yes playwright*)` permission rule.

Working files go to `~/.v3-gauntlet/tickets/<repo>/_reviews/` (override with `TICKETS_HOME`), never into your project. Claude Code refuses writes under `~/.claude/`, so the workspace lives outside it.

**Permissions.** To run without prompts, allow these in your settings (confirmed in `docs/superpowers/spikes/2026-10-03-phase-1a.md`):
- `Read(~/.v3-gauntlet/**)` and `Edit(~/.v3-gauntlet/**)` (Edit rules cover all file-writing tools; Write rules are not matched)
- `Bash(bash *skills/v3-review/scripts/*)`
- your project's gate commands, for example `Bash(npm test*)`, `Bash(npm run lint*)`
- optional: `Bash(gh pr view*)`, so the bar can be built from your PR description
- for `/v3-ticket` CLOSE: `Bash(git worktree*)`, `Bash(git branch*)`, `Bash(git pull*)`, `Bash(gh pr view*)`, `Bash(gh issue view*)`, `Bash(gh issue close*)`

**Exit pair safety.** `--reset` runs only when the database in `--env-file` matches `--db-pattern` and its host is local. Anything else is refused before a reset runs.

Tests: `bash tests/run.sh` (the queue client's tests run with Node, which ships with Claude Code). End-to-end: `tests/SMOKE.md`.

## Guardrails
A `PreToolUse` hook on Bash (`hooks/guard.sh`) blocks:
- **Tool attribution, always:** a `git commit` or `gh pr create`/`edit` whose message or PR text (including `-F`, `--file` and `--body-file` files and heredocs) carries a Claude co-author trailer or a "Generated with Claude Code" footer.
- **Unapproved pushes, during a ticket:** `git push` from a ticket's branch before phase `pr`, unless SHIP recorded `push_approved: yes` after your go-ahead.
- **Base-branch commits, during a ticket:** `git commit` on a ticket's `base_branch` from `approved` to `handoff`.

It fails open: unreadable input or ticket state allows the command, and every other command passes untouched. To turn it off for a session, start Claude Code with `V3_GAUNTLET_GUARD=off` in its environment (setting it inside a Bash command does nothing, because the hook runs in Claude Code's environment). Known limits: a message built at runtime (for example `-m "$(cat file)"`) is not seen, and a `-F <file>` argument of another command in the same line (for example `grep -F`) is read as a message file.

## Add a workflow

1. Create the file in the right directory with kebab-case name and `description` frontmatter.
2. Run `./scripts/validate.sh`.
3. Bump `version` in `.claude-plugin/plugin.json`. This is required for the change to reach other machines.
4. Commit (`feat:`), run `bash scripts/check-commits.sh` before pushing, then push and `git tag vX.Y.Z`.

## Rules

This repo is public. No employer names, internal hostnames, chat room or account IDs, tracker
URLs, ticket contents or project code. Project-specific values live in the work project's own
`.claude/` (a private config file), never here. List the names to keep out in that project's
`.claude/v3-gauntlet-deny.txt`; SHIP refuses a PR that contains them.

## License

MIT
