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
finish
