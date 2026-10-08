#!/usr/bin/env bash
# The lap templates carry the stages and handoff sections the laptop side relies on.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
R="$ROOT/skills/lap/templates/RULES.md"
B="$ROOT/skills/lap/templates/lead-brief.md"

rules=$(cat "$R"); brief=$(cat "$B")
assert_contains "$rules" "### 2.8b Final review" "RULES has the final review stage"
assert_contains "$rules" "docs/gauntlet/<lap>/tickets/<id>/final-review.md" "RULES names the final review file"
assert_contains "$rules" "type: review-mine" "the final review uses the review-mine frontmatter"
assert_contains "$rules" "head_sha: <first 8 characters of the reviewed tip>" "the final review records the reviewed tip"
assert_contains "$rules" "| Final review |" "the handoff ticket table has a final review column"
assert_contains "$brief" "final-review.md" "the brief's done-means lists the final review"
assert_contains "$rules" "## 5. Review request" "the handoff has a review request section"
assert_contains "$rules" "Self-review:" "the review request carries the self-review line"
assert_contains "$rules" "docs/gauntlet/<lap>/tickets/<id>/prior-art/" "GO reads each ticket's prior art"
assert_contains "$rules" "## 6. Proposed learnings" "the handoff has a proposed learnings section"
assert_contains "$rules" "components:" "a proposed learning carries its components"
assert_contains "$brief" "prior-art" "the brief lists the prior-art folder"
# Resume, checkpoints and rounds.
assert_contains "$rules" "docs/gauntlet/<lap>/resume/resume.tsv" "GO fetches resume bundles"
assert_contains "$rules" "Checkpoint" "the lead commits its record as it goes"
assert_contains "$rules" "docs/gauntlet/<lap>-handoff-r<k>.md" "each round writes its own handoff"
assert_contains "$brief" "{resume_note}" "the brief carries the resume note"
# The backend gate is scoped and the stack is the lap's own.
assert_contains "$rules" "/tmp/stack-<lap>" "the stack folder, and so its compose project, is the lap's own"
assert_not_contains "$rules" "/tmp/lap-base" "no shared stack folder name across laps"
assert_contains "$rules" "switch --detach <ticket tip>" "container gates run on the ticket's code"
assert_contains "$rules" '$G/<lap>/tools/scoped-tests.sh' "gates replace {tests} with the scoped list"
assert_contains "$rules" '$G/<lap>/tools/gate-select.sh --task $G/RULES.md <task base> <ticket tip>' "per-task gates come from gate-select"
assert_contains "$rules" "git add -f" "logs are committed past a .gitignore"
# Cost.
assert_contains "$brief" "{helper_model}" "the brief names the helper model"
assert_contains "$brief" "{critic_model}" "the brief names the critic model"
assert_contains "$rules" "reuse the 2.4 panel" "the final review reuses the ticket review when the tip is unchanged"
assert_contains "$rules" 'G="$(pwd)/docs/gauntlet"' "GO fixes the absolute lap folder"
assert_contains "$brief" "this round's handoff" "done-means follows the round"
# Lap lessons travel both ways.
assert_contains "$rules" '$G/<lap>/lap-lessons.md' "GO reads the kept lap lessons"
assert_contains "$rules" "## 7. Lap lessons" "the handoff proposes lap lessons"
# The laptop side.
skill=$(cat "$ROOT/skills/lap/SKILL.md")
assert_contains "$skill" "## /v3-lap lessons" "the skill keeps lessons on the user's word"
assert_contains "$skill" "lap-lessons.sh" "kept lessons go through lap-lessons.sh"
assert_contains "$skill" "--lessons" "start packs the lessons"
assert_contains "$skill" "answers-r<k>.md" "answers are saved per round"
assert_contains "$skill" "## Answer copy" "answers are copied where the config says"
finish
