#!/usr/bin/env bash
# scoped-tests.sh lists only the test files that exist and touch the change, so a gate never runs the whole suite.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
S="$ROOT/skills/v3-review/scripts/scoped-tests.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
r="$tmp/repo"; mkdir -p "$r"; cd "$r" || exit 1
git init -q .; git config user.email t@example.com; git config user.name t
mkdir -p backend/app/services backend/app/models backend/tests/services backend/tests/models backend/tests/api
echo "x = 1" > backend/app/services/pricing.py
echo "y = 1" > backend/app/models/order.py
echo "z = 1" > backend/app/services/other.py
echo "from app.services.pricing import x" > backend/tests/services/test_uses_pricing.py
echo "from app.services import pricing" > backend/tests/api/test_imports_package_form.py
echo "import app.services.other" > backend/tests/services/test_other.py
echo "def test(): pass" > backend/tests/services/test_pricing_rules.py
echo "from app.models.order import y" > backend/tests/models/test_order.py
echo "# not a test" > backend/tests/services/helpers.py
git add -A; git commit -qm base; BASE=$(git rev-parse HEAD)

# A change to pricing.py: importers in both forms, the test named after it, nothing else.
echo "x = 2" > backend/app/services/pricing.py
git commit -qam change
out=$(bash "$S" --root backend "$BASE" HEAD); code=$?
assert_eq 0 "$code" "finds tests for a changed module"
assert_eq "tests/api/test_imports_package_form.py
tests/services/test_pricing_rules.py
tests/services/test_uses_pricing.py" "$out" "importers and the name match, relative to the root, sorted"

# A changed or new test file is listed itself; one deleted at head is not.
echo "def test_new(): pass" > backend/tests/services/test_new_thing.py
git rm -q backend/tests/models/test_order.py
git add -A; git commit -qm tests
out=$(bash "$S" --root backend "$BASE" HEAD)
assert_contains "$out" "tests/services/test_new_thing.py" "a new test file is listed"
assert_not_contains "$out" "tests/models/test_order.py" "a deleted test file is never listed"
assert_not_contains "$out" "helpers.py" "a non-test file under tests is not listed"

# --scope adds the planned files, so a baseline at the base can be scoped before any change exists.
printf 'allow: backend/app/models/order.py\nallow: backend/tests/services/test_*_rules.py\nforbid: backend/app/services/other.py\n' > "$tmp/scope.txt"
out=$(bash "$S" --root backend --scope "$tmp/scope.txt" "$BASE" "$BASE")
assert_eq "tests/models/test_order.py
tests/services/test_pricing_rules.py" "$out" "planned module and planned test glob, forbid ignored"

# --exist-at keeps only files present at that commit (pytest aborts on a missing path).
out=$(bash "$S" --root backend --exist-at "$BASE" "$BASE" HEAD)
assert_not_contains "$out" "test_new_thing.py" "a test new on the branch is dropped for the base run"
assert_contains "$out" "tests/services/test_uses_pricing.py" "existing tests stay for the base run"

# Nothing touches tests: exit 1, empty output.
git checkout -q -b docs "$BASE"; echo "readme" > README.md; git add -A; git commit -qm docs
out=$(bash "$S" --root backend "$BASE" HEAD 2>/dev/null); code=$?
assert_eq 1 "$code" "no test touches the change: exit 1"
assert_eq "" "$out" "and prints nothing"

# A changed conftest.py brings its whole folder.
echo "import pytest" > backend/tests/services/conftest.py; git add -A; git commit -qm conftest
out=$(bash "$S" --root backend "$BASE" HEAD)
assert_eq "tests/services" "$out" "a conftest change lists its folder"

# A hub module (imported by more tests than --hub-max) lists none of its importers and says so.
git checkout -q -b hub "$BASE"
for i in 1 2 3; do echo "from app.services.other import z" > "backend/tests/api/test_hub_$i.py"; done
git add -A; git commit -qm hubtests; HB=$(git rev-parse HEAD)
echo "z = 2" > backend/app/services/other.py; git commit -qam hubchange
out=$(bash "$S" --root backend --hub-max 3 "$HB" HEAD 2>"$tmp/err")
assert_eq "tests/services/test_other.py" "$out" "only the name match is left"
assert_contains "$(cat "$tmp/err")" "app.services.other: 4 importing tests, skipped (hub module)" "the skip is named on stderr"
out=$(bash "$S" --root backend --hub-max 4 "$HB" HEAD 2>/dev/null)
assert_contains "$out" "tests/api/test_hub_1.py" "at the cap the importers are listed"

# Run from a subfolder, paths still resolve from the repo root; a folder with a space is kept whole.
git checkout -q -b space "$BASE"
mkdir -p "backend/tests/sp ace"; echo "from app.services.pricing import x" > "backend/tests/sp ace/test_s.py"
git add -A; git commit -qm space; SB=$(git rev-parse HEAD)
echo "x = 3" > backend/app/services/pricing.py; git commit -qam again
out=$(cd backend/app && bash "$S" --root backend "$SB" HEAD)
assert_contains "$out" "tests/sp ace/test_s.py" "a path with a space is listed whole, run from a subfolder"

bash "$S" --root backend 2>/dev/null; assert_eq 2 $? "base is required"
bash "$S" --root backend nope HEAD 2>/dev/null; assert_eq 2 $? "unknown base refused"
bash "$S" --root backend --scope "$tmp/none.txt" "$BASE" HEAD 2>/dev/null; assert_eq 2 $? "missing scope file refused"
finish
