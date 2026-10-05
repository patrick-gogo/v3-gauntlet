---
name: ticket-ship
description: SHIP stage of /v3-ticket - writes one report with numbered questions, takes the user's answers, runs round 2 if they ask for changes, and opens a draft PR only on their explicit go-ahead after a secrets scan.
---

# SHIP

Read `v3-gauntlet:ticket-workspace` first. `S` = `bash "$SKILL_DIR/../ticket-workspace/scripts/state.sh" <WS>/state.md`.

## 0. Every entry
`git branch --show-current` must equal `branch`; if not and the tree is clean, `git switch <branch>`; if dirty, stop and tell the user. Never push any other branch.

## 1. Write the report (`WS/handoff.md`), in this order
1. **Outcome:** `READY` or `BLOCKED: <reason>`; depth; tasks done / total; dispatches used / budgets. The PR title type is the `type` state key (absent in workspaces from before v0.4.0: `fix` when the branch starts with `fix/`, else `feat`).
2. **Needs your decision:** numbered questions, each with your recommendation, answerable in a few words ("1 keep 2 change: ... 3 yes"). Include deferred Importants, out-of-scope files, unreproduced findings that need a call, blockers, and base drift. The last question is always "Open the draft PR? (yes / no)".
3. **Unreproduced findings** (security first). Then **Refuted by the challenger** (depth full): copy that section of `v3-review/report.md` (and `v3-review-r2/report.md`), Criticals first; each refuted Critical is also a question under "Needs your decision" ("Reopen F1-n? recommended: <keep closed | reopen>"). A reopened finding becomes an Important or Critical for round 2.
4. **Severity downgrades.**
5. **What changed:** `git diff --stat <base>..HEAD`, `git log --oneline <base>..HEAD`, scope classes from the last scope check.
6. **Evidence:** gates vs baseline (known reds called out); red→green per task from `reports/task-N.md`; review-loop verdicts per round, graded scores per round and the exit-pair result from `v3-review/` (and `v3-review-r2/` after a round 2).
7. **Rulings:** every entry of `rulings.md`, with cost if wrong.
8. **Base drift:** if a remote exists, `git fetch origin <base_branch> -q` then `git rev-list --count <base>..origin/<base_branch>`. Non-zero → "Base moved by N commits; merge it in before the PR?" is one of the questions.
9. **Draft PR:** title `<type>(<id>): <title>`; body in `WS/pr-body.md` with Summary, Changes, How it was tested (the evidence), and the ticket reference. No tool attribution of any kind.

`S phase handoff`. Show sections 1–2 in chat with the path to `handoff.md`, then wait for the answers.

## 2. Answers
- Record each answer as a ruling with `source: user`.
- An answer that asks for a code change: append the needed tasks to `plan.md` under `## Round 2` (in the plan's task format, with tests, numbered from `tasks_total` + 1 so they are never mistaken for finished round-1 tasks), `S set round2 yes`, add their count to `tasks_total`, `S set budget_impl_max` to `budget_impl_used` + 4 × new tasks (2 × for lite), `S set preflight no`, `S phase round2`, and invoke `v3-gauntlet:ticket-build`. Its review loop gets a fresh `--budget` and runs its bars on the whole branch.
- "Merge the base in": `git merge --no-edit origin/<base_branch>` (never rebase: the branch's history stays as reviewed). On conflict: `git merge --abort` and ask the user how to proceed. After a clean merge, `S set base $(git merge-base HEAD origin/<base_branch>)` (now the base tip) so every later diff covers only this branch's own changes, rerun the gates once, note in the report that the baseline predates the merge, and say so in the PR body.

## 3. Open the PR (only after an explicit yes)
1. Secrets: `git diff <base>..HEAD | bash "$SKILL_DIR/../ticket-workspace/scripts/secret-scan.sh" [--deny-file .claude/v3-gauntlet-deny.txt] - "<WS>/pr-body.md"`; pass `--deny-file` only when the project has that file. Any hit → show the rule and location (never the value) and stop: this is security-sensitive and the user decides.
2. Show the final PR title and body.
3. `S set push_approved yes` (the guard hook blocks a ticket's push without it), then push, then `gh pr create --draft --base <pr_target> --title "<title>" --body-file "<WS>/pr-body.md"`. Never let a push run hooks in the main checkout (the project's pre-push hook may run a full build there, where another agent may be working). Read `push_skip_hooks` from `CFG`:
   - `yes`: `git push --no-verify -u origin <branch>`. Add one line to `pr-body.md` before creating the PR: "Pushed with --no-verify: the project's gates ran in BUILD (see evidence above)."
   - otherwise (default): `TMP="<CFG lap_worktree_dir, else <parent of the main checkout>/<repo> worktrees>/push-<id>"` (quote it: the folder may hold a space); `git worktree add "$TMP" <branch>` (if the branch is still checked out in the ticket's worktree, use `git worktree add --detach "$TMP" <branch>` and push `HEAD:<branch>` instead); `git -C "$TMP" push -u origin <branch>` so the hooks run there; then always `git worktree remove --force "$TMP"`, also when the push failed. If the hook fails there for setup reasons (dependencies missing), report it and stop; never retry the push in the main checkout.
4. `S set pr_url <url>`, `S phase pr`. Give the user the URL and say that after the PR is merged they should run `/v3-ticket <id>` once more to mark the ticket done and clean up.
