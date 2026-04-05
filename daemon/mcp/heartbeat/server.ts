#!/usr/bin/env bun
/**
 * Heartbeat MCP server for ClawdKit.
 *
 * Receives POST /heartbeat with a prompt body, pushes a
 * notifications/claude/channel notification to Claude Code, then returns 200.
 * No tools, no auth, one-way push only.
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'

const PORT = 7749

const mcp = new Server(
  { name: 'clawdkit-heartbeat', version: '1.0.0' },
  {
    capabilities: { experimental: { 'claude/channel': {} } },
    instructions:
      'You will receive heartbeat notifications from the ClawdKit daemon. ' +
      'Each notification carries a heartbeat prompt (typically a HEARTBEAT.md task list). ' +
      'Process the tasks described in the notification content.',
  },
)

await mcp.connect(new StdioServerTransport())

Bun.serve({
  port: PORT,
  hostname: '127.0.0.1',
  async fetch(req) {
    const url = new URL(req.url)

    if (url.pathname === '/heartbeat' && req.method === 'POST') {
      const body = await req.text()
      if (!body.trim()) {
        return new Response('empty body', { status: 400 })
      }

      void mcp.notification({
        method: 'notifications/claude/channel',
        params: {
          content: body,
          meta: {
            source: 'heartbeat',
            ts: new Date().toISOString(),
          },
        },
      })

      return new Response(null, { status: 200 })
    }

    return new Response('not found', { status: 404 })
  },
})

process.stderr.write(`clawdkit-heartbeat: listening on 127.0.0.1:${PORT}\n`)

process.on('unhandledRejection', (reason) => {
  process.stderr.write(`clawdkit-heartbeat: unhandled rejection: ${reason}\n`)
})

process.on('uncaughtException', (err) => {
  process.stderr.write(`clawdkit-heartbeat: uncaught exception: ${err.message}\n`)
  process.exit(1)
})
