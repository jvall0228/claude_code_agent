---
status: pending
priority: p2
issue_id: "004"
tags: [testing, quality]
dependencies: []
---

# Add unit testing

## Problem Statement

No test coverage exists for the shell scripts, MCP servers, or CLI. Changes are validated manually by running the daemon and checking tmux output.

## Findings

- Shell scripts: `clawdkit.sh`, `start-agent.sh`, `bootstrap.sh`, `heartbeat.sh`, hook scripts
- MCP servers: `heartbeat/server.ts`, `session-control/server.ts` (Bun/TS)
- CLI: `bin/clawdkit` (shell)
- No test framework or test files exist

## Technical Details

**Potential approach:**
- Shell scripts: `bats` (Bash Automated Testing System) or similar
- MCP servers: `bun:test` (built into Bun)
- Integration tests: spin up a test instance, verify lifecycle

## Acceptance Criteria

- [ ] MCP servers have unit tests (tool handlers, HTTP endpoints)
- [ ] Shell scripts have basic smoke tests (argument parsing, validation)
- [ ] CLI commands tested
- [ ] CI pipeline runs tests on PR
