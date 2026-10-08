---
description: Run the Queued tickets as an unattended gauntlet lap on the devbox, then bring the results home, answer, and push on your word
argument-hint: "[ticket ids] | result [lap] | resume [lap] [ids] | answer [lap] \"<reply>\" | lessons [lap] \"<reply>\" | learn [lap] \"<reply>\" | push [lap] [ids]"
---

Follow the `v3-gauntlet:lap` skill.

Arguments: $ARGUMENTS
- Empty, or ticket IDs only: start a lap (skill section "/v3-lap (start)").
- `result [lap]`: bring the lap home (section "/v3-lap result").
- `resume [lap] [ids]`: continue a lost lap in a new one, keeping the finished work (section "/v3-lap resume").
- `answer [lap] "<reply>"`: answer the handoff's questions (section "/v3-lap answer").
- `lessons [lap] "<reply>"`: keep or drop the handoff's lap lessons; kept ones go into every later lap (section "/v3-lap lessons").
- `learn [lap] "<reply>"`: keep or skip the handoff's proposed learnings (section "/v3-lap learn").
- `push [lap] [ids]`: push day, only because the user asked for it (section "/v3-lap push").
