#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
GUARD="$ROOT/hooks/guard.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export TICKETS_HOME="$tmp/tickets"
# hook <cwd> <command>: run the guard on hook JSON shaped like the real one (spike); sets code and err.
hook() {
  err=$(perl -MJSON::PP -e 'print encode_json({session_id=>"s",cwd=>$ARGV[0],hook_event_name=>"PreToolUse",tool_name=>"Bash",tool_input=>{command=>$ARGV[1],description=>"d"}})' "$1" "$2" | bash "$GUARD" 2>&1 >/dev/null); code=$?
}
mkdir -p "$tmp/plain"
CO="Co-""Authored-By"   # split so validate.sh's attribution scan does not match this file
GW="Generated ""with"
T="$CO: Claude Opus <noreply@anthropic.com>"

hook "$tmp/plain" 'git commit -m "feat: add x"'; assert_eq 0 "$code" "clean commit allowed"; assert_eq "" "$err" "allow prints nothing"
hook "$tmp/plain" "git commit -m \"feat: x

$T\""; assert_eq 2 "$code" "trailer in -m blocked"
assert_contains "$err" "v3-gauntlet guard: " "block reason prefix"
hook "$tmp/plain" "cd a && git commit -F - <<'EOF'
feat: x

$T
EOF"; assert_eq 2 "$code" "trailer in heredoc blocked"
printf 'feat: x\n\n%s\n' "$T" > "$tmp/plain/msg.txt"
hook "$tmp/plain" 'git commit -F msg.txt'; assert_eq 2 "$code" "trailer in -F file blocked"
hook "$tmp/plain" 'git commit --file=msg.txt'; assert_eq 2 "$code" "trailer in --file= blocked"
hook "$tmp/plain" "gh pr create --draft --title t --body \"Adds x. $GW [Claude Code](https://claude.com/claude-code)\""; assert_eq 2 "$code" "footer in PR body blocked"
printf 'Body\n\n%s Claude Code\n' "$GW" > "$tmp/plain/body.md"
hook "$tmp/plain" 'gh pr edit 3 --body-file body.md'; assert_eq 2 "$code" "footer in --body-file blocked"
hook "$tmp/plain" "git -C /x commit -m \"x

co-authored-by: claude <n@a.com>\""; assert_eq 2 "$code" "case-insensitive, git -C form"
hook "$tmp/plain" 'git commit -m "say \"hi\" to C:\\temp"'; assert_eq 0 "$code" "escaped quotes and backslashes parse"
hook "$tmp/plain" "git commit -m \"x

Co-Authored-By: Jane <j@x.org>\""; assert_eq 0 "$code" "human co-author allowed"
hook "$tmp/plain" "git log --grep \"$T\""; assert_eq 0 "$code" "searching history allowed"
hook "$tmp/plain" "echo git commit \"$T\""; assert_eq 0 "$code" "echo of the words allowed"
hook "$tmp/plain" 'git commit -m "x" -m "Co-Authored""-By: Claude <n@a.com>"'; assert_eq 2 "$code" "trailer split by adjacent quotes blocked"
hook "$tmp/plain" "git commit -m 'x' -m 'Co-Author'ed-By:\\ Claude"; assert_eq 2 "$code" "trailer split by quotes and backslash blocked"
hook "$tmp/plain" 'ls -la'; assert_eq 0 "$code" "unrelated command allowed"

out=$(printf '' | bash "$GUARD" 2>&1); assert_eq "0:" "$?:$out" "empty stdin allowed silently"
out=$(printf '{not json' | bash "$GUARD" 2>&1); assert_eq "0:" "$?:$out" "invalid JSON allowed silently"
out=$(perl -MJSON::PP -e 'print encode_json({cwd=>"/x",tool_input=>{command=>"git commit -m \"x\n\n$ARGV[0]: Claude <a\@b>\""}})' "$CO" | V3_GAUNTLET_GUARD=off bash "$GUARD" 2>&1); assert_eq "0:" "$?:$out" "V3_GAUNTLET_GUARD=off disables"

hj=$(cat "$ROOT/hooks/hooks.json")
assert_contains "$hj" '"PreToolUse"' "hook event registered"
assert_contains "$hj" '"matcher": "Bash"' "Bash matcher"
assert_contains "$hj" '${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh' "runs the guard from the plugin root"
# A repo with tickets. Workspaces live under $TICKETS_HOME/<repo-slug>/<id>/state.md.
R="$tmp/demo"; mkdir -p "$R"
( cd "$R" && git init -q -b main && git remote add origin https://example.com/me/demo.git \
  && git -c user.name=t -c user.email=t@x commit -q --allow-empty -m init && git branch feat/t-1 )
ticket() { mkdir -p "$TICKETS_HOME/demo/$1"; printf 'ticket: %s\nphase: %s\nbranch: %s\nbase_branch: main\n%s' "$1" "$2" "$3" "${4:-}" > "$TICKETS_HOME/demo/$1/state.md"; }

hook "$R" 'git push -u origin main'; assert_eq 0 "$code" "push with no tickets allowed"
ticket T-1 implementing feat/t-1
git -C "$R" switch -q feat/t-1
hook "$R" 'git push -u origin feat/t-1'; assert_eq 2 "$code" "push before approval blocked"
ticket T-1 in-lap feat/t-1
hook "$R" 'git push -u origin feat/t-1'; assert_eq 2 "$code" "push of a ticket in a lap blocked until push day approves it"
assert_contains "$err" "T-1" "push block names the ticket"
ticket T-1 handoff feat/t-1 'push_approved: yes
'
hook "$R" 'git push -u origin feat/t-1'; assert_eq 0 "$code" "approved push allowed"
ticket T-1 pr feat/t-1
hook "$R" 'git push'; assert_eq 0 "$code" "push after the PR phase allowed"
ticket T-1 implementing feat/t-1
git -C "$R" switch -q main
hook "$R" 'git push origin main'; assert_eq 0 "$code" "push of another branch allowed"

hook "$R" 'git commit -m "fix: y"'; assert_eq 2 "$code" "commit on the base branch during a ticket blocked"
assert_contains "$err" "feat/t-1" "base block names the ticket branch"
for ph in intake designed planned pr closed; do
  ticket T-1 "$ph" feat/t-1
  hook "$R" 'git commit -m "fix: y"'; assert_eq 0 "$code" "commit on base allowed in phase $ph"
done
for ph in approved in-lap round2 handoff blocked; do
  ticket T-1 "$ph" feat/t-1
  hook "$R" 'git commit -m "fix: y"'; assert_eq 2 "$code" "commit on base blocked in phase $ph"
done
git -C "$R" switch -q feat/t-1
ticket T-1 implementing feat/t-1
hook "$R" 'git commit -m "feat: z"'; assert_eq 0 "$code" "commit on the ticket branch allowed"

rm "$TICKETS_HOME/demo/T-1/state.md"
git -C "$R" switch -q main
hook "$R" 'git commit -m "fix: y"'; assert_eq 0 "$code" "missing state.md fails open"
hook "$tmp/plain" 'git push'; assert_eq 0 "$code" "not a repo fails open"
assert_eq "" "$err" "fail open prints nothing"
# Quoted text and heredoc bodies are data, not commands (final review I1).
ticket T-2 implementing feat/t-1
git -C "$R" switch -q feat/t-1
hook "$R" 'grep -rn "commit\|git push origin" skills/'; assert_eq 0 "$code" "quoted pattern is not a push"
hook "$R" 'git commit -m "docs: then run; git push origin x"'; assert_eq 0 "$code" "push words inside a commit message"
hook "$R" "git commit -F - <<'EOF'
docs: steps
git push origin feat/t-1
EOF"; assert_eq 0 "$code" "push line inside a heredoc message"
hook "$R" "cat > notes.md <<EOF
git push -u origin feat/t-1
EOF"; assert_eq 0 "$code" "push line inside a heredoc file"
hook "$R" 'git status && git push'; assert_eq 2 "$code" "a real push after && still blocked"
# Cleanup round: more push forms, cd/-C targets, and mentions of the trailer text.
hook "$R" 'git --no-pager push'; assert_eq 2 "$code" "git --no-pager push detected"
hook "$R" 'env GIT_TRACE=0 git push'; assert_eq 2 "$code" "env-prefixed push detected"
hook "$R" "$(printf '\tgit push')"; assert_eq 2 "$code" "tab before git detected"
hook "$tmp/plain" "git -C \"$R\" push"; assert_eq 2 "$code" "quoted git -C path is the repo checked"
hook "$tmp/plain" "cd \"$R\" && git push"; assert_eq 2 "$code" "cd X && uses X for ticket lookup"
hook "$tmp/plain" "git commit -m \"docs: explain why $CO: Claude trailers are blocked\""; assert_eq 0 "$code" "mentioning the trailer mid-line is allowed"
# Push from a temporary worktree (-C "<path with a space>"): attached, and detached with a refspec.
rm -rf "$TICKETS_HOME/demo/T-2"
git -C "$R" switch -q main
ticket T-1 handoff feat/t-1
git -C "$R" worktree add -q "$tmp/push wt" feat/t-1
hook "$tmp/plain" "git -C \"$tmp/push wt\" push -u origin feat/t-1"; assert_eq 2 "$code" "attached worktree push blocked when not approved"
ticket T-1 handoff feat/t-1 'push_approved: yes
'
hook "$tmp/plain" "git -C \"$tmp/push wt\" push -u origin feat/t-1"; assert_eq 0 "$code" "attached worktree push allowed when approved"
git -C "$R" worktree remove --force "$tmp/push wt"
git -C "$R" worktree add -q --detach "$tmp/push wt" feat/t-1
ticket T-1 handoff feat/t-1
hook "$tmp/plain" "git -C \"$tmp/push wt\" push -u origin HEAD:feat/t-1"; assert_eq 2 "$code" "detached push HEAD:branch blocked when not approved"
hook "$tmp/plain" "git -C \"$tmp/push wt\" push -u origin HEAD:refs/heads/feat/t-1"; assert_eq 2 "$code" "detached push to refs/heads/ blocked when not approved"
hook "$tmp/plain" "git -C \"$tmp/push wt\" push -u origin HEAD:other"; assert_eq 0 "$code" "detached push to another branch allowed"
hook "$tmp/plain" "git -C \"$tmp/push wt\" push"; assert_eq 0 "$code" "detached push with no refspec fails open"
ticket T-1 handoff feat/t-1 'push_approved: yes
'
hook "$tmp/plain" "git -C \"$tmp/push wt\" push -u origin HEAD:feat/t-1"; assert_eq 0 "$code" "detached push HEAD:branch allowed when approved"
git -C "$R" worktree remove --force "$tmp/push wt"

# Destination-based push judgement: the branch pushed decides, wherever the checkout is.
git -C "$R" switch -q main
ticket T-1 approved feat/t-1
hook "$R" 'git push --no-verify -u origin feat/t-1'; assert_eq 2 "$code" "push options skipped: unapproved push from main blocked"
assert_contains "$err" "T-1" "names the ticket"
ticket T-1 approved feat/t-1 'push_approved: yes
'
hook "$R" 'git push --no-verify -u origin feat/t-1'; assert_eq 0 "$code" "push options skipped: approved push from main allowed"
ticket T-1 approved feat/t-1
for opt in '-o ci.skip' '--push-option=x' '--force-with-lease' '-u' '--no-verify'; do
  hook "$R" "git push $opt origin feat/t-1"; assert_eq 2 "$code" "option [$opt] does not hide the branch"
done
hook "$R" 'git push origin main:feat/t-1'; assert_eq 2 "$code" "src:dst judged by dst when unapproved"
hook "$R" 'git push origin feat/t-1:main'; assert_eq 0 "$code" "src:dst with an unrelated dst allowed"
hook "$R" 'git push origin main feat/t-1'; assert_eq 2 "$code" "every refspec is checked"
hook "$R" 'git push origin +feat/t-1'; assert_eq 2 "$code" "forced refspec judged by its branch"
hook "$R" 'git push origin :feat/t-1'; assert_eq 2 "$code" "delete refspec judged by its branch"
hook "$R" 'git -C /tmp/x/push-T-1 push -u origin HEAD:feat/t-1'; assert_eq 2 "$code" "unquoted path holding the word push cannot fail open"
hook "$R" 'git -c core.x=y push origin feat/t-1'; assert_eq 2 "$code" "git -c k=v before push"
git -C "$R" switch -q feat/t-1
hook "$R" 'git push origin HEAD'; assert_eq 2 "$code" "HEAD resolves to the current branch"
git -C "$R" switch -q main
hook "$R" 'git push origin HEAD'; assert_eq 0 "$code" "HEAD on main is main"
# Another ticket is current; the pushed branch's ticket is the one named.
git -C "$R" branch -q feat/t-5
ticket T-5 implementing feat/t-5
git -C "$R" switch -q feat/t-5
hook "$R" 'git push origin feat/t-1'; assert_eq 2 "$code" "push of an unapproved branch from another ticket's checkout blocked"
assert_contains "$err" "T-1" "names the pushed ticket"
assert_not_contains "$err" "T-5" "does not name the checked-out ticket"
ticket T-1 approved feat/t-1 'push_approved: yes
'
hook "$R" 'git push origin feat/t-1'; assert_eq 0 "$code" "approved pushed branch allowed although the checkout's ticket is not"
hook "$R" 'git push'; assert_eq 2 "$code" "no refspec falls back to the current branch"
assert_contains "$err" "T-5" "fallback names the current ticket"
git -C "$R" switch -q main
rm -rf "$TICKETS_HOME/demo/T-5"
finish
