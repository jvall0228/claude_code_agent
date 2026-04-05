---
title: "Heartbeat Tasks"
type: heartbeat
updated: 2026-04-05
---

# Heartbeat Tasks

Tasks to run on each heartbeat (every 30 minutes). Work through in order. Complete one atomic unit per heartbeat — don't rush through everything if items need real attention.

## Proactive Tasks

- [ ] **GitHub notifications** — Check `gh api /notifications`. For each unread: triage by type (mention, review request, assign). Reply or queue follow-ups. Mark read when handled.
- [ ] **Open PRs** — Run `gh pr list --assignee @me`. For each: check CI status, look for blocking review feedback. If CI failing, surface the failure. If stale (>48h no activity), flag.
- [ ] **Recent activity summary** — Log a 2-3 sentence summary of what happened in the last 30 minutes to `progress.log`. Note anything worth the owner's attention.

## Conditional Tasks

Run only when relevant:

- **Failing CI**: If any open PR has failing CI, investigate and report via notification channel.
- **Urgent mentions**: If a GitHub mention is urgent (tagged "urgent", "blocker", or similar), notify via channel immediately.
- **Long-running session**: If `progress.log` shows session running >4 hours, consider triggering `/agent-daemon:context-compact`.

## After Each Heartbeat

Update `state.json`:
```json
{
  "last_heartbeat": "<ISO-8601 timestamp>",
  "heartbeat_in_progress": false
}
```

Log to `progress.log`:
```
[ISO-8601] [<agent_name>] heartbeat complete — <brief summary>
```

---

*Customize this file for your specific agent's proactive responsibilities.*
