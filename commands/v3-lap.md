---
description: Run the Queued tickets as an unattended gauntlet lap on the devbox, then bring the results home, answer, and push on your word
argument-hint: "[ticket ids] | result [lap] | answer [lap] \"<reply>\" | push [lap] [ids]"
---

Follow the `v3-gauntlet:lap` skill.

Arguments: $ARGUMENTS
- Empty, or ticket IDs only: start a lap (skill section "/v3-lap (start)").
- `result [lap]`: bring the lap home (section "/v3-lap result").
- `answer [lap] "<reply>"`: answer the handoff's questions (section "/v3-lap answer").
- `push [lap] [ids]`: push day, only because the user asked for it (section "/v3-lap push").
