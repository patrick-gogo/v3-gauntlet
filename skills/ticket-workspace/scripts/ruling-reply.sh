#!/usr/bin/env bash
# Parse a rulings-batch reply such as "1 keep 2 change: reuse the modal 3 keep", "1-5 keep 6 yes 7 no" or "all keep".
# Usage: ruling-reply.sh <number of questions> "<reply>"
# Prints one line per question: "<n> keep", "<n> change <text>", "<n> yes" or "<n> no".
# A range "a-b" applies its verb (and change text) to every number from a to b.
# Exit: 0 every question answered once, 2 bad input (missing, unknown, repeated or unclear answers).
set -u
count=${1:-}; reply=${2-}
case "$count" in ''|*[!0-9]*) echo "usage: ruling-reply.sh <count> \"<reply>\"" >&2; exit 2 ;; esac
[ "$count" -gt 0 ] || { echo "count must be at least 1" >&2; exit 2; }

printf '%s\n' "$reply" | LC_ALL=C awk -v count="$count" '
  function flush(  k) {
    if (cur == "") return
    for (k = cur; k <= curhi; k++) {
      if (k in seen) { err = err "ruling " k " answered twice\n"; continue }
      seen[k] = 1
      if (verb == "keep" || verb == "yes" || verb == "no") { if (txt != "") err = err "ruling " k ": " verb " takes no text\n"; else ans[k] = verb }
      else if (verb == "change") { if (txt == "") err = err "ruling " k ": change needs what to change\n"; else ans[k] = "change " txt }
      else err = err "ruling " k ": say keep or change\n"
    }
  }
  # A verb token: keep, change, yes or no, any case, with an optional trailing ":" "," or ".".
  function verbof(t,  v) { v = tolower(t); sub(/[:,.]+$/, "", v); return (v == "keep" || v == "change" || v == "yes" || v == "no") ? v : "" }
  {
    gsub(/,/, " ")
    n = split($0, tok, /[ \t]+/)
    if (tolower($1) == "all" && verbof($2) == "keep" && n <= 3 && (n < 3 || tok[3] == "")) {
      for (i = 1; i <= count; i++) print i " keep"
      exit 0
    }
    cur = ""; curhi = ""; verb = ""; txt = ""; err = ""
    for (i = 1; i <= n; i++) {
      t = tok[i]; if (t == "") continue
      num = t; sub(/\.$/, "", num)
      isnum = (num ~ /^[0-9]+$/); isrange = (num ~ /^[0-9]+-[0-9]+$/)
      # Inside change text a number or range starts a new answer only when a verb follows it, so
      # "use 2 columns" stays text. After a verb that takes no text any number is a new answer.
      if ((isnum || isrange) && (cur == "" || verb == "keep" || verb == "yes" || verb == "no" || verbof(tok[i + 1]) != "")) {
        flush()
        if (isrange) { split(num, rg, "-"); lo = rg[1] + 0; hi = rg[2] + 0 } else { lo = num + 0; hi = lo }
        cur = lo; curhi = hi; verb = ""; txt = ""
        if (lo > hi) { err = err "bad range " num "\n"; cur = "" }
        else if (lo < 1) { err = err "no ruling " lo " (there are " count ")\n"; cur = "" }
        else if (hi > count) { err = err "no ruling " (lo > count ? lo : count + 1) " (there are " count ")\n"; cur = "" }
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
