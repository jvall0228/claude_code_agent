---
status: done
priority: p0
issue_id: "014"
tags: [bug, mcp, session-control, tmux]
dependencies: []
assignee: jarvis
---

# BUG: session-control MCP compact_context doesn't submit Enter key

## Problem

`tmux send-keys` without the `-l` (literal) flag interprets certain characters in the command string as tmux key names. When `/compact` is called with instruction text containing special characters (parentheses, colons, etc.), tmux may misinterpret parts of the string, causing the command to be malformed or the trailing `Enter` to never fire.

Observed: `/compact` command appeared in the terminal but was never submitted — the daemon wrote the text but didn't "hit enter."

## Root Cause

In `daemon/mcp/session-control/server.ts` line 21:

```typescript
Bun.spawn(['tmux', 'send-keys', '-t', SESSION_NAME, keys, 'Enter'])
```

Two issues:
1. **No `-l` flag** — `send-keys` without `-l` interprets the `keys` argument for tmux key table lookups. Characters like `(`, `)`, `C-`, `M-` can be misinterpreted.
2. **Single invocation** — Mixing literal text and the special `Enter` key in one call is fragile. If tmux misparses any part of the keys argument, the `Enter` may not fire.

## Fix

Split into two calls: first send the command text literally (`-l`), then send `Enter` separately:

```typescript
async function tmuxSendKeys(keys: string): Promise<void> {
  // Send command text literally (no key-name interpretation)
  const textProc = Bun.spawn(['tmux', 'send-keys', '-t', SESSION_NAME, '-l', keys], { ... })
  // Then send Enter as a key name
  const enterProc = Bun.spawn(['tmux', 'send-keys', '-t', SESSION_NAME, 'Enter'], { ... })
}
```

## Acceptance Criteria

- [ ] `tmuxSendKeys` uses `-l` flag for command text
- [ ] `Enter` is sent as a separate `send-keys` invocation
- [ ] Both `clear_context` and `compact_context` work with arbitrary instruction text
- [ ] Tested with instruction text containing parentheses, colons, quotes
