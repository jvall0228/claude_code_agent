---
status: pending
priority: p2
issue_id: "002"
tags: [daemon, architecture, threads, tos, ux]
dependencies: []
assignee: jarvis
---

# Multiple conversation threads per daemon

## Problem Statement

Currently each daemon instance is one conversation thread. Heartbeats interrupt whatever the agent is doing. Ideally the agent would support a Slack-like experience — organizable, granular threads that are non-blocking.

## Vision

Think Slack channels/threads for an agent:
- Each concern gets its own thread (heartbeat, chat, code review, etc.)
- Threads are non-blocking — work in one doesn't interrupt another
- Threads are organizable and navigable (not just a single linear conversation)
- Each thread would be a separate Claude Code instance (tmux session)

## Findings

- Current architecture: one tmux session → one claude process → one conversation
- `claude remote-control --spawn worktree` supports multiple concurrent sessions from a server
- Anthropic ToS prohibits non-1P methods of automation for Claude Code
- Interactive vs non-interactive usage is the key distinction — must stay within bounds
- One Claude Code instance per thread means each thread has its own context window

## Technical Details

**Key constraint:** Must use Claude Code's own mechanisms (interactive sessions, remote control, channels) rather than wrapping the API directly or scripting non-interactive automation.

**Architecture sketch:**
- Thread manager spawns/manages multiple tmux sessions per agent
- Each session is a full Claude Code instance with shared persona (same brain)
- Shared state layer so threads can reference each other's context
- UI layer (future: native app) presents threads like Slack channels

**Open questions:**
- How does the agent coordinate across threads? Shared filesystem? MCP?
- Resource limits — how many concurrent Claude Code instances are practical?
- How does remote control work with multiple sessions per agent?
- Thread lifecycle — when to spawn, when to tear down?

## Acceptance Criteria

- [ ] Heartbeats don't interrupt active work
- [ ] Agent can handle multiple concerns in parallel threads
- [ ] Threads are navigable and organizable
- [ ] Approach confirmed compliant with Anthropic ToS
- [ ] No non-1P automation methods used

## Notes

- This is a significant architectural change — likely the biggest evolution of ClawdKit
- Gray area with ToS — needs careful evaluation of what constitutes 1P automation
- Interactive usage is key — each thread must be interactively driven
- Future native app UI would make the Slack-like experience tangible
