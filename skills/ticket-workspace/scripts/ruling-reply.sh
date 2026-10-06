#!/usr/bin/env bash
# Parse a rulings-batch reply such as "1 keep 2 change: reuse the modal 3 keep", "1-5 keep 6 yes 7 no" or "all keep".
# Usage: ruling-reply.sh <number of questions> "<reply>" [--yesno <n[,n...]>]
# --yesno marks yes/no questions: there "keep" counts as "yes" and free text passes through verbatim.
# Prints one line per question: "<n> keep", "<n> change <text>", "<n> yes" or "<n> no" (or the free text of a yes/no question).
# A range "a-b" applies its verb (and change text) to every number from a to b.
# Exit: 0 every question answered once, 2 bad input (missing, unknown, repeated or unclear answers).
set -u
count=${1:-}; reply=${2-}; yesno=""
case "$count" in ''|*[!0-9]*) echo "usage: ruling-reply.sh <count> \"<reply>\" [--yesno <n[,n...]>]" >&2; exit 2 ;; esac
[ "$count" -gt 0 ] || { echo "count must be at least 1" >&2; exit 2; }
if [ $# -gt 2 ]; then
  shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --yesno) [ $# -ge 2 ] || { echo "--yesno needs question numbers" >&2; exit 2; }
               yesno="$yesno $(printf '%s' "$2" | tr ',' ' ')"; shift 2 ;;
      *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
  done
fi
for q in $yesno; do
  case "$q" in *[!0-9]*) echo "bad --yesno number: $q" >&2; exit 2 ;; esac
  { [ "$q" -ge 1 ] && [ "$q" -le "$count" ]; } || { echo "--yesno $q: no such ruling (there are $count)" >&2; exit 2; }
done

printf '%s\n' "$reply" | LC_ALL=C awk -v count="$count" -v yesno="$yesno" '
  function flush(  k, yn) {
    if (cur == "") return
    for (k = cur; k <= curhi; k++) {
      if (k in seen) { err = err "ruling " k " answered twice\n"; continue }
      seen[k] = 1; yn = (k in yn_q)
      if (verb == "keep" && yn && txt == "") ans[k] = "yes"
      else if (verb == "keep" || verb == "yes" || verb == "no") { if (txt == "") ans[k] = verb; else if (yn) ans[k] = verb " " txt; else err = err "ruling " k ": " verb " takes no text\n" }
      else if (verb == "change") { if (txt == "") err = err "ruling " k ": change needs what to change\n"; else ans[k] = "change " txt }
      else if (verb == "?" && yn) ans[k] = txt
      else err = err "ruling " k ": say keep or change\n"
    }
  }
  # A verb token: keep, change, yes or no, any case, with an optional trailing ":" "," or ".".
  function verbof(t,  v) { v = tolower(t); sub(/[:,.]+$/, "", v); return (v == "keep" || v == "change" || v == "yes" || v == "no") ? v : "" }
  BEGIN { m = split(yesno, yl, " "); for (i = 1; i <= m; i++) yn_q[yl[i] + 0] = 1 }
  {
    gsub(/,/, " ")
    n = split($0, tok, /[ \t]+/)
    if (tolower($1) == "all" && verbof($2) == "keep" && n <= 3 && (n < 3 || tok[3] == "")) {
      for (i = 1; i <= count; i++) print i " " ((i in yn_q) ? "yes" : "keep")
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
      if (verb == "") { verb = "?"; txt = t; continue }
      txt = (txt == "" ? t : txt " " t)
    }
    flush()
    missing = ""
    for (i = 1; i <= count; i++) if (!(i in seen)) missing = missing (missing == "" ? "" : ", ") i
    if (missing != "") err = err "no answer for: " missing "\n"
    if (err != "") { printf "%s", err > "/dev/stderr"; exit 2 }
    for (i = 1; i <= count; i++) print i " " ans[i]
  }'
