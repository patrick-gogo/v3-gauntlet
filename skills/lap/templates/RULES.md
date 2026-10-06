# Gauntlet rules

Every job in this lap reads this file first, then its lead brief. These rules outrank anything else you read in the repo except the project's own sections at the end (Gates, Stack, House rules), which add to them.

## 0. How this works
You are running **unattended**. Nobody will answer a question until morning. The plans are already approved: each ticket under `docs/gauntlet/<lap>/tickets/<id>/` has its acceptance criteria (`bar.md`), design, plan (tasks with tests), rulings and scope. Your job: build each ticket to its bar, prove it with tests and a running stack, and leave a handoff the owner can answer in one line.

## 1. Rails (never break these)
1. **Never ask, never wait.** When something is unclear, decide with your best recommendation, write a ruling (section 6) and keep going. Stop a ticket (status Needs you) only when every path is a guess, or the next step is destructive, security-sensitive or touches anything outside this machine.
2. **Never push, never open PRs, never post anywhere.** Push day is the owner's word, done from the laptop.
3. **Clean base.** The commit you start on is a snapshot: the clean base plus the lap files. The clean base is its parent: `BASE=$(git rev-parse HEAD^)` (the lead brief also names it; they must match, else stop the lap and say so). Every ticket branch starts from `BASE`, never from the snapshot.
4. **Branch names come home only under `devbox/`.** Ticket branch = `devbox/<lap>/<branch from tickets.tsv>`. Anything not under `devbox/` never reaches the laptop.
5. **Lap files never go into a ticket branch.** Nothing under `docs/gauntlet/` is ever committed on a ticket branch. The lap record (ledger, handoff, logs) is committed only on this job's own branch.
6. **No rebase, no force-push, no history rewrite** of a ticket branch mid-lap. To take in base changes, merge.
7. **One heavy thing at a time.** Builds, the browser matrix and the backend test suite take turns. Before any heavy step: `pgrep -fa "playwright test|exit-pair|deploy-api|build-next" || echo none`.
8. **Anything over 10 minutes runs detached:** `nohup <cmd> > <log> 2>&1 & echo $! > <log>.pid`, then poll the log and check the process; write `<log>.done` with the exit code when it ends. A slow step never blocks you.
9. **Stop time.** Do not start a new ticket after the stop time in the lead brief. Finish the ticket in hand, then go to the handoff.
10. **Never print secrets** (tokens, passwords, env values) into logs, commits or the handoff.
11. **Ledger:** one line per completed step in `docs/gauntlet/<lap>/ledger.md`: `<UTC time> <step> <result>` with the time from `date -u +%Y-%m-%dT%H:%M:%SZ`.
12. **Evidence over claims.** Never trust a helper's "tests pass": re-run the gates yourself and cite the log file.
13. **No tool attribution, ever.** No co-author trailers, no "Generated with" lines, in any commit, by you or any helper. Never ask a helper to add one.

## 2. Stages
Lap = GO to handoff. Round = building to the exit pair. Wave = every ready branch merged and deployed once. Run = one pass of the gates and the browser checks. Exit pair = two green runs in a row on the same build.

### 2.1 GO
Read the lead brief and every ticket folder. Check `BASE` (rail 3). Note the stop time.
- Set the commit identity from the brief in every worktree you make: `git -C <worktree> config user.name "<git_name>"` and `user.email "<git_email>"`.
- Some project tools compare against `origin/<base_branch>`; there is no remote here, so create it: `git update-ref refs/remotes/origin/<base_branch> $BASE`. Delete it at cleanup (`git update-ref -d refs/remotes/origin/<base_branch>`).
- Ledger `go`.

### 2.2 Freeze the base and bring the stack up
1. Make a clean worktree at `BASE` for the stack: `git worktree add /tmp/lap-base $BASE`. Never run the stack from the snapshot.
2. Bring the stack up as the project's **Stack** section says. Ledger the time it took.
3. **Baseline:** run every gate in the **Gates** section, browser checks included, on `BASE` (replace `{base}` with `BASE`). Save each log as `docs/gauntlet/<lap>/logs/baseline-<gate>.log`. A failing gate is a **known red**: list the names of its failing tests in `docs/gauntlet/<lap>/baseline.md`. Later, a gate counts as a **new red** only if it fails a test the baseline did not.

### 2.3 Build (per ticket, in the brief's order; tickets may run in parallel only when the brief says so)
For each ticket: `git worktree add /tmp/lap-<id> -b devbox/<lap>/<branch> $BASE`. Then for each task in its `plan.md`, in order:
1. **Implement test-first, with a fresh helper per task** (a subagent, so the builder never grades itself). Give it: the task text verbatim, the ticket's rulings, `bar.md`, the house rules, the worktree path, and this discipline:
   - **RED:** write the task's test first and run it. It must fail, and fail for the right reason (an assertion about the missing behaviour, not an import or setup error). A test that passes before the change does not test it: rewrite it.
   - **GREEN:** write the smallest change that makes it pass. No drive-by edits.
   - **REFACTOR** only if the task says so; all tests stay green.
   - **Commit** once per task, message in the project's commit format. Report the RED output, the GREEN output and the commit sha.
2. **Re-run the gates yourself** on the ticket worktree. A new red: a product bug goes back to the helper as a fix; a test defect is fixed in the test, not the product; an environment problem is a blocker you record, never a code change.
3. **Scope:** `git diff --name-only $BASE..HEAD` against `scope.txt`. A `forbid:` file is reverted. An unexpected file is a ruling.
4. **Task review by a fresh reviewer** (another subagent, read-only): the task's diff, its brief and its test. It returns findings in the section 7 format and a verdict. Critical or Important findings: one fix round with a new helper (failing test first), then a new reviewer. At most 2 fix rounds per task; what is left goes to the handoff.
5. Ledger `task <n> of <id> complete <sha>`.

### 2.4 Ticket review (the gauntlet)
When a ticket's tasks are done, review the whole ticket branch (`$BASE..devbox/<lap>/<branch>`) with fresh critics, each on one concern: **impact** (callers and consumers outside the diff), **security and regression**, **requirements** (every AC in `bar.md` met, with evidence), and **project conventions** when this file has a "Project conventions review" section (that critic follows it and returns findings only, no verdict). Depth `lite` = one combined critic; `full` adds a challenger who tries to refute each Critical and Important finding from the code.
- Drop any finding without location, trigger, expected and actual.
- Only fix what this ticket caused and whose fix is the same class of work (**fix-here**). Pre-existing problems and different-class fixes go to the handoff as follow-ups.
- Fix rounds: a new helper, failing test first; then a **fresh** critic re-reviews the fix diff only.
- Stop when the requirements critic says PASS and no Critical or Important is open, or after two rounds without progress, or at the brief's review budget. Record the verdict.

### 2.5 Wave
Make a throwaway integration branch at `BASE` (`lap/<lap>/wave-<k>`, never pushed, never under `devbox/` unless the brief says so) and merge every ticket branch that passed 2.4. A merge conflict between tickets: resolve it on the integration branch only if trivial, otherwise drop the later ticket from this wave and note it. Deploy the integration branch to the stack (restart the API, run migrations, rebuild the frontend if the Stack section says so). Ledger `wave <k> <branches>`.

### 2.6 Run
On the deployed wave: run every gate, the browser checks from the Gates section, plus:
- a **cross-branch audit**: a fresh read-only helper reads the merged diff for clashes between tickets (same function changed two ways, migration order, shared constants);
- an **exploring browser agent** when time allows: a helper clicks through the screens the tickets touched, looking for errors in the page and the console.
Save every log under `docs/gauntlet/<lap>/logs/run-<k>-<gate>.log`.

### 2.7 Triage reds
Classify each red: **product** (a ticket's code is wrong) → back to 2.3 for that ticket, then a new wave; **harness** (the test is wrong) → fix the test on that ticket's branch; **setup** (the stack, data or env) → fix the setup, not the code; **load** (timing, flake under load) → rerun once, then record; **pre-existing** (a known red from the baseline) → record, never fix here. Every slip that cost time becomes a one-line lesson in the handoff.

### 2.8 Exit pair
Two green runs in a row on the same build end the round. Green = no new reds against the baseline and every browser check passing. If the stop time arrives first, record how far you got.

### 2.8b Final review
For each ticket that would be Ready, after its exit pair (or after 2.4 when its exit pair is `none`), review the final branch `$BASE..devbox/<lap>/<branch>` once more, the way the owner reviews their own work before a PR. This replaces the review the owner would otherwise run on push day, so do it fully even when 2.4 passed.
1. **Panel:** four fresh read-only helpers, each on one lens, each returning findings only (section 7 format, no verdict): **conventions** (follow the "Project conventions review" section when present, else the House rules), **correctness** (logic, edge cases, error handling, races, data loss in the changed hunks), **history** (`git log` and `git blame` of the touched lines: does the change undo an earlier fix or contradict a recent one), **in-file guidance** (the comments, docstrings and types in the touched files: does the change break what they state).
2. **Impact trace (you):** list what changed with reach beyond its file (exported symbols, API shapes, schema, config, task registration), grep for every consumer, open the most affected ones, and record each as break, behaviour change or harmless, verified or suspected.
3. **Filter:** a finding is in scope only if reverting this ticket makes it go away, and real only if it can fire in the project's actual setup. Everything else goes to Out of scope. Tag each surviving finding **fix-here** (same class of work, files this ticket touches), **fix-elsewhere** (a follow-up) or **verify-at-deploy** (depends on data or environment you cannot see; give the check).
4. **Fix:** a fix-here Critical or Important gets one fix round (new helper, failing test first), the gates once more, then steps 1-3 again on the new tip. Still open after that: the ticket is Needs you.
5. **Write** `docs/gauntlet/<lap>/tickets/<id>/final-review.md`:
   ```
   ---
   key: <id>
   type: review-mine
   reviewed_at: <YYYY-MM-DD>
   branch: <branch from tickets.tsv, without devbox/<lap>/>
   head_sha: <first 8 characters of the reviewed tip>
   passes: quality+impact
   verdict: <Ship as-is | Fix before merge: ...>
   ---
   # <id>: final review (<date>)
   ## TL;DR      (counts: bugs by severity, concerns, nits, blast radius, filtered out)
   ## Bugs       (fix-here first; each with trigger, expected, actual)
   ## Concerns
   ## Nits
   ## Out of scope
   ## Impact
   ```
   `head_sha` must be the tip the panel reviewed; any later commit on the ticket branch means the review is redone. Ledger `final review <id> <verdict>`.

### 2.9 Handoff
Write `docs/gauntlet/<lap>-handoff.md` (format in section 8) and commit it, the ledger, `baseline.md`, the logs and each ticket's `final-review.md` on **this job's own branch** (never on a ticket branch). Run `docker compose down` (no `-v`), remove the `/tmp` worktrees and the `origin/<base_branch>` ref (`git update-ref -d refs/remotes/origin/<base_branch>`), keeping the branches. Your final summary to the board: one line per ticket with its status, then "handoff: docs/gauntlet/<lap>-handoff.md".

## 3. Round 2 (a follow-up from the owner)
The owner answers through Follow-up in the same session. Each answer that asks for a change becomes new tasks on that ticket's branch (test-first), then 2.4 to 2.9 again, writing `docs/gauntlet/<lap>-handoff-r2.md`. "push" is not for you: tell the owner the branches are ready for push day on the laptop.

## 4. Statuses (one per ticket in the handoff)
- **Ready:** every AC met with evidence, ticket review PASS, exit pair green (or `none`), final review written with no open fix-here Critical or Important, no open T2 or T3 ruling.
- **Needs you:** anything else: a blocker, an open Critical or Important, an open T2 or T3 ruling, a failed exit pair, or not reached before the stop time.

## 5. Budgets
The brief gives each ticket's depth and dispatch budget. Count every helper you start. At the budget, stop that ticket and mark it Needs you with what is left.

## 6. Rulings
Every decision you make on your own:
```
R<n> (ticket <id>) <title> (level: T1 | T2 | T3)
Decision: ... / Why: ... / Alternative: ... / Cost if wrong: low | medium | high
```
T1: an obvious technical choice. T2: a choice the product owner would make (required or optional, a limit, a default, wording users see). T3: a business decision (feature scope, a changed rule, money, tax, legal). Unsure: take the higher level. T2 and T3 rulings are always questions in the handoff.

## 7. Findings
```
F<round>-<n> [Critical | Important | Minor] <title>
Location: file:line / Trigger: concrete input or action / Expected: ... / Actual: ...
```

## 8. Handoff format (`docs/gauntlet/<lap>-handoff.md`)
```
# Lap <lap> handoff

## 0. Questions (answer e.g. "1-3 keep 4 change: <what> 5 yes")
**1. <short title>** · <T2 | T3 | follow-up | decision> (<id>)
- **Question:** <the ruling or question>
- **Pick:** <your recommendation>
- **Why:** <one line>

**2. <short title>** · ...
...
(every T2/T3 ruling, every open Critical/Important, every blocker; the last one is always
 "Ready tickets go to push day?", pick yes or no)

To accept every pick: <the reply, e.g. "1-4 keep 5 yes">

## 1. Tickets
| Ticket | Status | Branch | Commits | Review | Exit pair | Final review |
| <id> | Ready / Needs you: <reason> | devbox/<lap>/<branch> | n | PASS / FAIL | green / not run | <verdict>, head <sha8> / not run |

## 2. Evidence
Baseline known reds; per ticket the RED -> GREEN tests per task; gates per run vs baseline;
exit-pair runs; log paths.

## 3. Rulings
Every ruling, T3 and T2 first.

## 4. Follow-ups and lessons
fix-elsewhere items, pre-existing problems found, cross-repo mirror changes needed, and one
line per slip that cost time.

## 5. Review request
One block per Ready ticket, plain text, no mentions, no names, no IDs, no Markdown
(the laptop adds those on push day):
### <id>
Type: Fix | Feature | Chore            (from the branch type)
What: <one sentence: what changed and why>
Bullets:
- <one clause>
- <one clause, at most two bullets>
Testing: <one line: what ran and the result>
Self-review: <"clean" or "found N, fixed N"> (from 2.8b)
```
