#!/usr/bin/env bun
/**
 * Heartbeat MCP server for ClawdKit.
 *
 * Receives POST /heartbeat with a prompt body, pushes a
 * notifications/claude/channel notification to Claude Code, then returns 200.
 * Also exposes pause/resume tools so the agent can control its own heartbeat schedule.
 */

import { existsSync, writeFileSync, unlinkSync } from 'node:fs'
import { join } from 'node:path'
import { Server } from '@modelcontextprotocol/sdk/server/index.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js'
import { createFetchHandler } from './handler.js'

const AGENT_NAME = process.env.CLAWDKIT_AGENT_NAME ?? 'clawdkit'
const INSTANCE_DIR = process.env.CLAWDKIT_INSTANCE_DIR ?? join(process.env.HOME ?? '', '.clawdcode', AGENT_NAME)
const PAUSE_FILE = join(INSTANCE_DIR, '.clawdkit', 'paused')

const _rawPort = Number(process.env.CLAWDKIT_HEARTBEAT_PORT ?? 7749)
if (!Number.isFinite(_rawPort) || _rawPort < 1 || _rawPort > 65535) {
  process.stderr.write(`clawdkit-heartbeat: invalid port: ${process.env.CLAWDKIT_HEARTBEAT_PORT}\n`)
  process.exit(1)
}
const PORT = _rawPort

const mcp = new Server(
  { name: 'clawdkit-heartbeat', version: '1.0.0' },
  {
    capabilities: { tools: {}, experimental: { 'claude/channel': {} } },
    instructions:
      'You will receive heartbeat notifications from the ClawdKit daemon. ' +
      'Each notification carries a heartbeat prompt (typically a HEARTBEAT.md task list). ' +
      'Process the tasks described in the notification content. ' +
      'Use pause_heartbeats / resume_heartbeats to control the heartbeat schedule.',
  },
)

mcp.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: 'pause_heartbeats',
      description:
        'Pause scheduled heartbeats. The heartbeat scheduler will skip firing until resumed. ' +
        'Use when you need uninterrupted focus on a long task, or when budget is exhausted.',
      inputSchema: { type: 'object' as const, properties: {} },
    },
    {
      name: 'resume_heartbeats',
      description:
        'Resume scheduled heartbeats after a pause.',
      inputSchema: { type: 'object' as const, properties: {} },
    },
  ],
}))

mcp.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name } = request.params

  switch (name) {
    case 'pause_heartbeats': {
      if (existsSync(PAUSE_FILE)) {
        return { content: [{ type: 'text', text: 'Heartbeats already paused.' }] }
      }
      writeFileSync(PAUSE_FILE, new Date().toISOString() + '\n')
      return { content: [{ type: 'text', text: 'Heartbeats paused.' }] }
    }
    case 'resume_heartbeats': {
      if (!existsSync(PAUSE_FILE)) {
        return { content: [{ type: 'text', text: 'Heartbeats not paused.' }] }
      }
      unlinkSync(PAUSE_FILE)
      return { content: [{ type: 'text', text: 'Heartbeats resumed.' }] }
    }
    default:
      throw new Error(`Unknown tool: ${name}`)
  }
})

// Start HTTP server and stdio handshake in parallel so a blocking stdio
// handshake doesn't prevent the HTTP health endpoint from coming up.
const notifier = async (body: string) => {
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
}

const httpServer = (() => {
  try {
    return Bun.serve({
      port: PORT,
      hostname: '127.0.0.1',
      fetch: createFetchHandler(notifier),
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
