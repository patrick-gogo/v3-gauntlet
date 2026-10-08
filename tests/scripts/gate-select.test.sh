#!/usr/bin/env bash
# gate-select.sh picks the gates a task runs: the task_gates list, minus gates whose paths the change does not touch.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
S="$ROOT/skills/v3-review/scripts/gate-select.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
r="$tmp/repo"; mkdir -p "$r/backend" "$r/frontend"; cd "$r" || exit 1
git init -q .; git config user.email t@example.com; git config user.name t
echo a > backend/a.py; echo b > frontend/b.ts; git add -A; git commit -qm base; BASE=$(git rev-parse HEAD)
echo a2 > backend/a.py; git commit -qam backend

cfg="$tmp/cfg.md"
cat > "$cfg" <<'EOF'
queue: notion
task_gates: backend-tests ruff frontend-tests
gate_paths.backend-tests: backend/
gate_paths.ruff: backend/
gate_paths.frontend-tests: frontend/

## Gates
backend-tests: pytest {tests}
ruff: ruff check
frontend-tests: npm test
e2e-smoke: npx playwright test

## Stack
not: a gate
EOF

assert_eq "backend-tests
ruff" "$(bash "$S" --task "$cfg" "$BASE" HEAD)" "a backend-only task runs the backend gates in task_gates"
assert_eq "backend-tests
ruff
e2e-smoke" "$(bash "$S" "$cfg" "$BASE" HEAD)" "the full set keeps e2e and drops untouched path gates"
assert_eq "backend-tests
ruff
frontend-tests
e2e-smoke" "$(bash "$S" --all "$cfg" "$BASE" HEAD)" "--all lists every gate in order"

# No keys: every gate, as before.
printf '## Gates\none: a\ntwo: b\n' > "$tmp/plain.md"
assert_eq "one
two" "$(bash "$S" --task "$tmp/plain.md" "$BASE" HEAD)" "without task_gates or gate_paths, every gate runs"

# No Gates section: exit 3 so the caller falls back to its own recorded gates.
printf 'queue: notion\n' > "$tmp/nogates.md"
out=$(bash "$S" --task "$tmp/nogates.md" "$BASE" HEAD 2>&1); assert_eq 3 $? "a config without a Gates section exits 3"
assert_contains "$out" "no ## Gates section" "and says why"
assert_eq "backend-tests
ruff" "$(cd backend && bash "$S" --task "$cfg" "$BASE" HEAD)" "path filters work from a subfolder"

bash "$S" "$tmp/none.md" "$BASE" HEAD 2>/dev/null; assert_eq 2 $? "missing config refused"
bash "$S" "$cfg" nope HEAD 2>/dev/null; assert_eq 2 $? "unknown base refused"
finish
