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

const _rawPort = Number(process.env.CLAWDKIT_HEARTBEAT_PORT ?? 7749)
if (!Number.isFinite(_rawPort) || _rawPort < 1 || _rawPort > 65535) {
  process.stderr.write(`clawdkit-heartbeat: invalid port: ${process.env.CLAWDKIT_HEARTBEAT_PORT}\n`)
  process.exit(1)
}
const PORT = _rawPort

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

// Start HTTP server and stdio handshake in parallel so a blocking stdio
// handshake doesn't prevent the HTTP health endpoint from coming up.
const httpServer = (() => {
  try {
    return Bun.serve({
      port: PORT,
      hostname: '127.0.0.1',
      async fetch(req) {
        try {
          const url = new URL(req.url)

          if (url.pathname === '/heartbeat' && req.method === 'POST') {
            const body = await req.text()
            if (!body.trim()) {
              return new Response('empty body', { status: 400 })
            }

            try {
              await mcp.notification({
                method: 'notifications/claude/channel',
                params: {
                  content: body,
                  meta: {
                    source: 'heartbeat',
                    ts: new Date().toISOString(),
                  },
                },
              })
            } catch (err) {
              const msg = err instanceof Error ? err.message : String(err)
              process.stderr.write(`clawdkit-heartbeat: notification failed: ${msg}\n`)
              return new Response('notification failed', { status: 500 })
            }

            return new Response(null, { status: 200 })
          }

          return new Response('not found', { status: 404 })
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err)
          process.stderr.write(`clawdkit-heartbeat: request handler error: ${msg}\n`)
          return new Response('internal server error', { status: 500 })
        }
      },
    })
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    process.stderr.write(`clawdkit-heartbeat: failed to start HTTP server: ${msg}\n`)
    process.exit(1)
  }
})()

process.stderr.write(`clawdkit-heartbeat: listening on 127.0.0.1:${PORT}\n`)

// Connect stdio transport after HTTP is up — if this blocks, health endpoint still works
await mcp.connect(new StdioServerTransport())

process.on('unhandledRejection', (reason) => {
  const msg = reason instanceof Error ? reason.message : String(reason)
  process.stderr.write(`clawdkit-heartbeat: unhandled rejection: ${msg}\n`)
  process.exit(1)
})

process.on('uncaughtException', (err) => {
  process.stderr.write(`clawdkit-heartbeat: uncaught exception: ${err.message}\n`)
  process.exit(1)
})
