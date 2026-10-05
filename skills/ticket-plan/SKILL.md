---
name: ticket-plan
description: PLAN stage of /v3-ticket - read the ticket, settle acceptance criteria, brainstorm the design and write the plan without stopping, deciding every open question itself as a numbered ruling, then show one rulings batch for the user to answer ("1 keep 2 change ..."). Ends at Planned (phase approved) and adds the ticket to the queue; it never starts BUILD.
---

# PLAN

Read `v3-gauntlet:ticket-workspace` first, including **Project config** and **Rulings**. `S` = `bash "$SKILL_DIR/../ticket-workspace/scripts/state.sh" <WS>/state.md`. `CFG` = the project config, if the project has one.

## Rules for this stage
- **Do not ask the user anything until step 8.** Every open question (a spec gap, a design choice, scope, depth, a default) is decided by you with your recommendation and recorded as a ruling (`source: planner`, with its level). The user reviews them all at once in step 8. The only earlier stops: no ticket text can be found (step 2), or the ticket ID cannot be worked out (step 1).
- Do not switch branches, create branches, commit, or run the project's gates. PLAN only reads the code and writes to the workspace. BUILD creates the branch later, wherever it runs.
- Ledger: one line per completed step in `WS/ledger.md`.

## 1. Identify the ticket
- An ID (`ABC-123`, `#42`): that is the ID. A URL: extract the ID from it (the issue key in Jira-style URLs, `#42` for `.../issues/42`) and keep the URL for intake; never use the URL itself as the ID. Pasted text with no ID: ask for a short ID (suggest `T-<yyyymmdd>-<two words>`).
- `WS=$(bash "$SKILL_DIR/../ticket-workspace/scripts/ticket-ws.sh" path <id>)`. If it exists, resume at the first missing step according to `phase` (`planned` with a `## Batch` section in `rulings.md` resumes at step 8). Otherwise `bash ".../ticket-ws.sh" init <id>`, then `S set ticket <id>` and `S phase intake`.

## 2. Intake
1. Read the ticket. If `CFG` has an `## Intake` section, follow it (for example a tracker's MCP tool). Otherwise use what the machine offers: `gh issue view <url or n> --json title,body,comments,url` for GitHub (pass a GitHub issue URL as the URL, never as the bare number); a tracker MCP tool if one is available. Nothing works → ask the user to paste it (the one allowed stop).
2. Save it verbatim to `WS/ticket.md`, including comments. `S set title "<title>"`. GitHub issue: `S set issue_url <url>` (CLOSE closes the issue by this URL only).
3. **Translation:** if the ticket contains Japanese (or any language other than English) and `CFG` does not say `translate: no`, append `## English translation` to `WS/ticket.md` with a faithful translation of the title, body and comments. Never change the original text. Use the translation for every later step; quote the original when wording matters (labels, messages).

## 3. Acceptance criteria
Extract them into `WS/bar.md` as `AC1`, `AC2`, ... followed by a `Deferred:` line. When the ticket has none, or they are vague, write them yourself from the ticket's intent and record a ruling for each one you inferred ("AC3 inferred: ..."). Never wait for the user here.

## 4. Branch name and base (recorded, not created)
1. Type: `fix` for a bug ticket, else `feat`. Unclear → ruling. `S set type <feat|fix>`.
2. Name: `BR=$(bash "$SKILL_DIR/../ticket-workspace/scripts/branch-name.sh" [--prefix <p>] [--keep-id-case] <type> <id> <title>)`, with `--prefix` from `CFG`'s `branch_prefix.<type>` and `--keep-id-case` when `CFG` says `branch_keep_id_case: yes`. `S set branch <BR>`.
3. Base: `CFG`'s `base_branch`, else the default branch (`git symbolic-ref --short refs/remotes/origin/HEAD` minus `origin/`; else local `main`). If a remote exists, `git fetch origin <base> -q`; `S set base $(git rev-parse origin/<base>)` (or `<base>` with no remote), `S set base_branch <base>`, `S set pr_target <base>`, `S set checkout main`.

## 5. Context and design
1. **Code context:** if `CFG` names a `context_agent`, dispatch it (read-only) with the ticket and ask how the touched code works today, what depends on it, sibling features, existing tests and open PRs on the same files. Save its answer to `WS/context.md`. Otherwise read the relevant code yourself and write `WS/context.md` the same way.
2. **Design:** invoke `superpowers:brainstorming` with these overrides from the user, which outrank the skill: this runs **unattended**. Wherever the skill would ask the user a question, answer it yourself with the option you would recommend and record a ruling instead. Do not offer the visual companion. Save the design to `WS/design.md` (not `docs/`), do not commit it, and do not invoke writing-plans: return here. `S phase designed`.

## 6. Plan
Dispatch `v3-gauntlet:ticket-planner` (model opus) with `TICKET=WS/ticket.md`, `DESIGN=WS/design.md`, `BAR=WS/bar.md`, `RULINGS=WS/rulings.md`, `CONTEXT=WS/context.md` and `OUT=WS/plan.md`. When `CFG` has a `## Gates` section, pass it as `GATES`. When `CFG` names a `planner_agent`, pass that agent's definition file as `CONVENTIONS` (`.claude/agents/<name>.md` in the project, else `~/.claude/agents/<name>.md`): its conventions apply, the plan format and test commands stay the plugin's. If it could not save the plan, run `superpowers:writing-plans` here with the same overrides. Do not show the plan for approval yet. `S set tasks_total <n>`, `S set tasks_done 0`, `S set round2 no`, `S phase planned`.

## 7. Autonomy brief (all decided by you)
Each item is a ruling unless it follows mechanically from the rule given.
1. **Gates:** `CFG`'s `## Gates` section when present (one `<name>: <command>` per line). Otherwise detect as `v3-review` does (package.json `test`/`lint`/`typecheck`; Makefile `test`/`lint`; pyproject pytest/ruff; Cargo; go.mod). `S set gate.<name> <command>`; `S set gate_timeout 900`.
2. **Scope:** from the planner's `SCOPE-SUGGESTION`, plus `forbid:` lines for paths the plan has no reason to touch (ruling). Write `WS/scope.txt`.
3. **Depth:** `lite` if the plan has at most 2 tasks and no path matches auth, security, crypto, payment, billing, session, token, password or permission; `full` when a path matches that list and the plan has more than 5 tasks; else `standard`. `S set depth <depth>`.
4. **Budget:** `S set budget_impl_max` = 2 × tasks (lite) or 4 × tasks (standard, full); `S set budget_review_max` 3 (lite), 10 (standard) or 16 (full); `S set budget_impl_used 0`.
5. **Parallel tasks:** `bash "$SKILL_DIR/../ticket-workspace/scripts/waves.sh" WS/plan.md`. `parallel: on` unless `lite`, or the gates need a fixed port or a shared database (then `off`, ruling). `S set parallel on|off`. Exit 2 → send the plan back to the planner to fix its `Depends on:` lines first.
6. **Exit pair and graded bar:** `S set exit_pair none` and leave `graded` unset unless `CFG` gives defaults for them (ruling either way, level T1).

## 8. Rulings batch (the one stop)
1. Append a `## Batch <k>` section to `WS/rulings.md` listing the rulings to review (batch 1: all of them), numbered from 1 in this batch, with a pointer to each ruling's `R` number. Then show the user, in this order:
   ```
   <id> <title>: planned, waiting for your answers (<n> rulings)

   Plan: <tasks_total> tasks, depth <depth>, waves <summary>, gates <names>
   AC: AC1 ..., AC2 ...                     (one line each)

   Rulings (reply e.g. "1 keep 2 change: <what> 3 keep", or "all keep")
   1. [T2] <decision> | why: <one line> | alt: <the main alternative> | cost if wrong: <low|medium|high>
   2. [T1] ...
   ```
   Put T3 and T2 rulings first, then T1. Keep each to one or two lines. Give the workspace path for the full plan and design.
2. Parse the answer with `bash "$SKILL_DIR/../ticket-workspace/scripts/ruling-reply.sh" <n> "<reply>"`. Exit 2 → show its message and ask again (only the unanswered or unclear numbers).
3. For each `keep`: set that ruling's `source: user`. For each `change <text>`: update the ruling (`Decision` per the user's text, `source: user`), then apply it to whatever it governs (`bar.md`, `design.md`, `plan.md`, `scope.txt`, state keys). A change that alters tasks re-dispatches the planner with the updated rulings; then repeat step 7 for anything the new plan affects.
4. If any answer was `change`, start a new batch containing only the rulings that changed and any new ones the changes produced, and go back to 8.1. When a batch comes back all `keep`, go on.

## 9. Planned
1. `S phase approved` (this is "Planned" on the queue board). Ledger: `planned <tasks_total> tasks, <n> rulings, <changes> changed by user`.
2. **Queue:** if `CFG` says `queue: notion`, run `node "$SKILL_DIR/../ticket-workspace/scripts/notion-queue.mjs" upsert --key <id> --title "<title>" --status Planned --branch <branch>` (add `--repo <CFG repo_label>` when set). Exit 3 (could not run) → say so in one line and tell the user to add the card by hand; it never fails PLAN.
3. Tell the user: the ticket is Planned; to run it, drag the card to **Queued** on the board (set its Order). Print the allow rules a build needs, once, for the project's `.claude/settings.local.json` (never edit settings yourself): `Read(~/.v3-gauntlet/**)`, `Edit(~/.v3-gauntlet/**)`, `Bash(bash *skills/*/scripts/*)`, `Bash(node *skills/*/scripts/*)`, each gate command, and the git commands BUILD uses (`git add`, `commit`, `diff`, `log`, `status`, `switch`, `rev-parse`; with parallel on also `reset`, `cherry-pick`, `worktree`, `branch`).
4. Stop. Do **not** invoke `v3-gauntlet:ticket-build`. A local build happens only when the user runs `/v3-ticket <id> build`.
