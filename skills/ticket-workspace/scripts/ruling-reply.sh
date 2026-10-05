#!/usr/bin/env bash
# Parse a rulings-batch reply such as "1 keep 2 change: reuse the modal 3 keep" or "all keep".
# Usage: ruling-reply.sh <number of rulings> "<reply>"
# Prints one line per ruling: "<n> keep" or "<n> change <text>".
# Exit: 0 every ruling answered once, 2 bad input (missing, unknown, repeated or unclear answers).
set -u
count=${1:-}; reply=${2-}
case "$count" in ''|*[!0-9]*) echo "usage: ruling-reply.sh <count> \"<reply>\"" >&2; exit 2 ;; esac
[ "$count" -gt 0 ] || { echo "count must be at least 1" >&2; exit 2; }

printf '%s\n' "$reply" | LC_ALL=C awk -v count="$count" '
  function flush() {
    if (cur == "") return
    if (cur in seen) { err = err "ruling " cur " answered twice\n"; return }
    seen[cur] = 1
    if (verb == "keep") { if (txt != "") err = err "ruling " cur ": keep takes no text\n"; else ans[cur] = "keep" }
    else if (verb == "change") { if (txt == "") err = err "ruling " cur ": change needs what to change\n"; else ans[cur] = "change " txt }
    else err = err "ruling " cur ": say keep or change\n"
  }
  # A verb token: keep or change, any case, with an optional trailing ":" "," or ".".
  function verbof(t,  v) { v = tolower(t); sub(/[:,.]+$/, "", v); return (v == "keep" || v == "change") ? v : "" }
  {
    gsub(/,/, " ")
    n = split($0, tok, /[ \t]+/)
    if (tolower($1) == "all" && verbof($2) == "keep" && n <= 3 && (n < 3 || tok[3] == "")) {
      for (i = 1; i <= count; i++) print i " keep"
      exit 0
    }
    cur = ""; verb = ""; txt = ""; err = ""
    for (i = 1; i <= n; i++) {
      t = tok[i]; if (t == "") continue
      num = t; sub(/\.$/, "", num)
      # Inside change text a number starts a new answer only when a verb follows it, so
      # "use 2 columns" stays text. After keep (which takes no text) any number is a new answer.
      if (num ~ /^[0-9]+$/ && (cur == "" || verb == "keep" || verbof(tok[i + 1]) != "")) {
        flush()
        cur = num + 0; verb = ""; txt = ""
        if (cur < 1 || cur > count) { err = err "no ruling " cur " (there are " count ")\n"; cur = "" }
        continue
      }
      if (cur == "") continue
      if (verb == "" && verbof(t) != "") { verb = verbof(t); continue }
      if (verb == "") { verb = "?"; continue }
      txt = (txt == "" ? t : txt " " t)
    }
    flush()
    missing = ""
    for (i = 1; i <= count; i++) if (!(i in seen)) missing = missing (missing == "" ? "" : ", ") i
    if (missing != "") err = err "no answer for: " missing "\n"
    if (err != "") { printf "%s", err > "/dev/stderr"; exit 2 }
    for (i = 1; i <= count; i++) print i " " ans[i]
  }'
