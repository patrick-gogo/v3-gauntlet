# Lap final review, ticket records and review-request fields Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make push day only "open the PR": the lap ends with a full self-review per ticket, PLAN creates the project's own ticket records, the lead drafts the review-request fields, and push day checks master drift and re-authored commits by itself. Also fix the 0.4.0 deep-review findings.

**Architecture:** Every project-specific detail stays in the private project config (`.claude/v3-gauntlet.md`) as new free-text sections, the same way `## Intake` and `## Push day` work today. The plugin (a public repo) only names the sections and when to follow them. The lap gets one new stage (2.8b final review) and one new handoff section; `/v3-lap result` and `push` learn to use them.

**Tech Stack:** Markdown skills, bash scripts tested with `tests/run.sh` (macOS bash 3.2 compatible), Node scripts tested with `node --test tests/node`.

**Spec:** the v3-gauntlet to-do page for 2026-10-06 (sections 1 and 2) and the 2026-10-06 push day of the second lap ticket, which was done by hand and showed every step this plan automates.

## Global Constraints

- The repo is public: no company values (room IDs, account IDs, domains, people, vault paths) in any plugin file. They live only in the private project config.
- No tool attribution in any commit or generated text.
- Every new config section is optional; without it the stages behave as in 0.4.0.
- Scripts stay bash 3.2 compatible and quote every path (folders may hold spaces).
- Version bump to 0.5.0 in `.claude-plugin/plugin.json` in the last task.

## Review Focus

1. A lap whose ticket is Needs you: no final review is run, and push day skips it as today.
2. Commits re-authored at push day change the sha: the final review's `head_sha` must still be accepted when the tree is identical, and refused when the code changed.
3. A project without `## Ticket records` or `## Review request`: PLAN and push day must behave exactly as 0.4.0.
4. Master moved since the lap's base: push day must report the drift and stop the ticket on a real conflict, never push it.
5. The lead's review-request fields must never carry IDs or mentions; the laptop adds those from the config.

---

### Task 1: Lap stage 2.8b, the final review

**Files:**
- Modify: `skills/lap/templates/RULES.md` (new 2.8b, handoff section 1 gets a Final review column, section 8 format)
- Modify: `skills/lap/templates/lead-brief.md` ("Done means" lists the review files)
- Test: `tests/scripts/lap-pack.test.sh` (RULES still carries every section heading)

Content of 2.8b: after the exit pair, for each Ready ticket, a panel of fresh read-only helpers on `$BASE..<ticket branch>`: conventions (the "Project conventions review" section when present), correctness, history (blame and log of the touched lines), in-file guidance (comments, docstrings, types). Then an impact trace of changed symbols, contracts and schema. Filters: in scope (the revert test) and reachable; each finding tagged fix-here, fix-elsewhere or verify-at-deploy. A fix-here Critical or Important gets one fix round (failing test first) and the gates once more; the review is then redone on the new tip. Write `docs/gauntlet/<lap>/tickets/<id>/final-review.md` with frontmatter `key`, `type: review-mine`, `reviewed_at` (date), `branch` (the ticket's branch name without the `devbox/<lap>/` prefix), `head_sha` (8 chars of the reviewed tip), `passes: quality+impact`, `verdict`; body sections TL;DR (counts), Bugs, Concerns, Nits, Out of scope, Impact. A ticket whose final review leaves an open fix-here Critical or Important becomes Needs you.

- [ ] Step 1: extend `lap-pack.test.sh` to assert the packed RULES.md contains `### 2.8b Final review` and `final-review.md`; run, expect FAIL.
- [ ] Step 2: write 2.8b, the handoff column and the brief line.
- [ ] Step 3: run `bash tests/run.sh`, expect PASS.
- [ ] Step 4: commit `feat: end each lap with a final self-review per ready ticket`.

### Task 2: /v3-lap result copies the final review; push day accepts re-authored commits

**Files:**
- Modify: `skills/lap/SKILL.md` (result step 3b; push step 2 and a new step 4b)
- Create: `skills/lap/scripts/review-head.sh`
- Test: `tests/scripts/review-head.test.sh`
- Modify: `skills/ticket-workspace/SKILL.md` (config: `## Review copy`)

`review-head.sh <review file> <branch>`: prints `ok` when the file's `head_sha` (or `rereviewed_head`) is the branch tip; prints `same-tree <new8>` when the review names a commit whose tree equals the tip's tree (re-authored, code identical); else exit 1 with `stale`. Missing file or no `head_sha`: exit 2.

Result: after saving the handoff, for each ticket `git show "refs/remotes/<job_branch>:docs/gauntlet/<lap>/tickets/<id>/final-review.md"` into `WS/final-review.md`, put it on the card (`$Q page --child "Final review <lap>"`), and when `CFG` has `## Review copy`, copy it where that section says (free text with `{id}` and `{date}`; e.g. a notes folder). Missing file: one line.

Push: after the local branch exists (and after a re-author), run `review-head.sh` on the copied review. `same-tree <sha>` → append `rereviewed_head: <sha>` to the review's frontmatter in every copy. `stale` or missing → say so and run the project's review command named in `## Review copy` (or `v3-gauntlet:v3-review`) before pushing.

- [ ] Step 1: write `review-head.test.sh` (git fixture: tip match, re-authored same tree, changed code, missing file); run, expect FAIL.
- [ ] Step 2: implement `review-head.sh`; run, expect PASS.
- [ ] Step 3: edit the lap skill and the config docs.
- [ ] Step 4: commit `feat: bring the final review home and accept re-authored commits at push day`.

### Task 3: Push day drift check

**Files:**
- Modify: `skills/lap/SKILL.md` (push new step 1b)
- Create: `skills/lap/scripts/drift.sh`
- Test: `tests/scripts/drift.test.sh`

`drift.sh <branch> <base_branch>`: `git fetch origin <base_branch> -q`; prints `behind <n> overlap <files...>` (files changed on both sides since the merge base) and `conflict yes|no` from `git merge-tree --write-tree --name-only origin/<base_branch> <branch>`; exit 0 clean, 1 conflict, 2 bad input. Push step 1b: conflict → skip the ticket and say which files; behind with overlap → show the overlap and continue (the review panel weighs it); with `CFG` `push_merge_base: yes` merge `origin/<base_branch>` in the push worktree before pushing (never rebase).

- [ ] Step 1: `drift.test.sh` with a fixture repo (clean, behind with overlap, conflict); run, expect FAIL.
- [ ] Step 2: implement; run, expect PASS.
- [ ] Step 3: edit push day; add `push_merge_base` to the config docs.
- [ ] Step 4: commit `feat: check master drift and conflicts before push day pushes`.

### Task 4: PLAN creates the project's ticket records

**Files:**
- Modify: `skills/ticket-plan/SKILL.md` (intake step 2.6)
- Modify: `skills/ticket-workspace/SKILL.md` (config: `## Ticket records`)

Step 2.6: if `CFG` has `## Ticket records`, follow it once the ticket text and translation are saved (free text: the project's own notes, caches or pages a later review or guard needs). Each failure is one ledger line; PLAN continues. Resume skips it when `state` has `records: done`.

- [ ] Step 1: edit both skills; `bash tests/run.sh` (validate.test.sh checks skill frontmatter), expect PASS.
- [ ] Step 2: commit `feat: let PLAN create the project's own ticket records`.

### Task 5: The lead drafts the review-request fields

**Files:**
- Modify: `skills/lap/templates/RULES.md` (handoff section 5)
- Modify: `skills/lap/SKILL.md` (push step 5b)
- Modify: `skills/ticket-workspace/SKILL.md` (config: `## Review request`)

Handoff section 5, one block per Ready ticket: `Type:` (Fix, Feature or Chore, from the branch type), `What:` one sentence, `Bullets:` at most two one-clause lines, `Testing:` one line, `Self-review:` a count line ("clean" or "found N, fixed N"). Plain text, no mentions, no IDs, no Markdown. Push step 5b: when `CFG` has `## Review request`, render the message from that section's template with these fields plus `{pr_url}` and `{ticket_url}`, and deliver it where the section says (draft only). Without the section, show the fields in the reply.

- [ ] Step 1: edit; extend `lap-pack.test.sh` to assert RULES has `## 5. Review request`; run, PASS after the edit (FAIL first).
- [ ] Step 2: commit `feat: have the lead draft the review-request fields for push day`.

### Task 6: 0.4.0 deferred minors and deep-review findings

The six listed on the to-do page, plus the deep review's Critical and Important findings (added below when the review returns). Each script fix gets a failing test first.

- [ ] "all keep" on the yes/no push question: `ruling-reply.sh` maps keep to yes for a question marked yes/no (test first).
- [ ] Re-author amend uses `--no-verify`; a failed re-author deletes the local branch it created.
- [ ] `guard.sh`: check every refspec on a detached push; `push origin HEAD` resolves HEAD's branch (tests first).
- [ ] PLAN sets `card: done` only when the upsert returned 0; one wording rule: any non-zero exit is one line, continue.
- [ ] `stop-time.mjs`: tomorrow by calendar date, not +24h; missing zone argument exits 2 (tests first).
- [ ] Round 2 handoff page title `Handoff <lap> r2`.

Deep review of 0.4.0 (2026-10-06): 0 Critical, 8 Important, 14 Minor. The Important ones, each with a test first where a script changes:
- [ ] I1 SHIP push from a detached temp worktree uses `HEAD:<branch>`, which git rejects on a first push: push `<branch>` by name (or from the ticket worktree).
- [ ] I2 `lap-check.sh` fails on tool attribution in any commit message `base..branch` (same patterns as `scripts/check-commits.sh`).
- [ ] I3 push day skips a ticket with a `change` answer or while the lap is in round 2, unless the owner names it.
- [ ] I4 guard judges a push by the destination branch in the refspec, attached or detached; current branch only without a refspec.
- [ ] I5 guard anchors the push parse on the git command, so an unquoted `push-<id>` path cannot fail open.
- [ ] I6 public repo: replace the real tracker key with a placeholder, the devbox user with `<user>@devbox.local`, restore the commit-email caveat (the owner decides on a noreply address).
- [ ] I7 laps default to `push_skip_hooks: yes`; SHIP in worktree mode pushes from the ticket worktree; document that a temp push worktree needs dependencies.
- [ ] I8 re-author exec adds `--no-verify --no-gpg-sign`; TMP defined before use; `git ls-remote` proves the branch is unpublished first.
Minors M1-M14 stay in the review report for a later pass unless one is a one-line fix in a file this plan already edits.

- [ ] Commit per fix, `fix: ...`.

### Task 7: Docs and release 0.5.0

**Files:** `README.md`, `docs/*` flow notes, `.claude-plugin/plugin.json`.

- [ ] Describe the final review, ticket records, review request and drift check; bump to 0.5.0; `bash tests/run.sh` and `node --test tests/node` PASS.
- [ ] Commit `docs: describe the lap final review and push-day checks, release 0.5.0`.
