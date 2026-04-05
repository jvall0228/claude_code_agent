#!/usr/bin/env bun
/**
 * Session Control MCP server for ClawdKit.
 *
 * Provides tools for the daemon agent to manage its own Claude Code session
 * (clear context, compact context) via tmux send-keys.
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js'

const AGENT_NAME = process.env.CLAWDKIT_AGENT_NAME ?? 'clawdkit'
const SESSION_NAME = `clawdkit-${AGENT_NAME}`

/** Send keystrokes to our own tmux session. */
async function tmuxSendKeys(keys: string): Promise<void> {
  const proc = Bun.spawn(['tmux', 'send-keys', '-t', SESSION_NAME, keys, 'Enter'], {
    stdout: 'pipe',
    stderr: 'pipe',
  })
  const exitCode = await proc.exited
  if (exitCode !== 0) {
    const stderr = await new Response(proc.stderr).text()
    throw new Error(`tmux send-keys failed (exit ${exitCode}): ${stderr.trim()}`)
  }
}

const mcp = new Server(
  { name: 'clawdkit-session-control', version: '1.0.0' },
  {
    capabilities: { tools: {} },
    instructions:
      'Session control tools for managing your own Claude Code context window. ' +
      'Use clear_context for a full reset, compact_context to summarize and shrink.',
  },
)

mcp.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: 'clear_context',
      description:
        'Clear your own context window by sending /clear to the terminal. ' +
        'Use when your context is getting full or you need a fresh start.',
      inputSchema: { type: 'object' as const, properties: {} },
    },
    {
      name: 'compact_context',
      description:
        'Compact your context window by sending /compact to the terminal. ' +
        'Optionally provide instructions to guide what to preserve during compaction.',
      inputSchema: {
        type: 'object' as const,
        properties: {
          instructions: {
            type: 'string',
            description: 'Optional instructions for what to preserve during compaction.',
          },
        },
      },
    },
  ],
}))

mcp.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params

  switch (name) {
    case 'clear_context': {
      await tmuxSendKeys('/clear')
      return { content: [{ type: 'text', text: 'Context window cleared.' }] }
    }
    case 'compact_context': {
      const instructions = (args as Record<string, unknown>)?.instructions
      const cmd = instructions ? `/compact ${instructions}` : '/compact'
      await tmuxSendKeys(cmd)
      return { content: [{ type: 'text', text: 'Context compaction triggered.' }] }
    }
    default:
      throw new Error(`Unknown tool: ${name}`)
  }
})

await mcp.connect(new StdioServerTransport())

process.on('unhandledRejection', (reason) => {
  const msg = reason instanceof Error ? reason.message : String(reason)
  process.stderr.write(`clawdkit-session-control: unhandled rejection: ${msg}\n`)
  process.exit(1)
})

process.on('uncaughtException', (err) => {
  process.stderr.write(`clawdkit-session-control: uncaught exception: ${err.message}\n`)
  process.exit(1)
})
