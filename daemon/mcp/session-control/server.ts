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

import { readFile, writeFile } from 'node:fs/promises'
import { join } from 'node:path'

const AGENT_NAME = process.env.CLAWDKIT_AGENT_NAME ?? 'clawdkit'
const SESSION_NAME = `clawdkit-${AGENT_NAME}`
const SCRIPTS_PATH = process.env.CLAWDKIT_SCRIPTS_PATH ?? ''
const INSTANCE_DIR = process.env.CLAWDKIT_INSTANCE_DIR ?? ''

/** Send keystrokes to our own tmux session. */
async function tmuxSendKeys(keys: string): Promise<void> {
  // Send command text with -l (literal) to avoid tmux interpreting
  // characters like (, ), C-, M- as key names.
  const textProc = Bun.spawn(['tmux', 'send-keys', '-t', SESSION_NAME, '-l', keys], {
    stdout: 'pipe',
    stderr: 'pipe',
  })
  const textExit = await textProc.exited
  if (textExit !== 0) {
    const stderr = await new Response(textProc.stderr).text()
    throw new Error(`tmux send-keys (text) failed (exit ${textExit}): ${stderr.trim()}`)
  }

  // Send Enter separately as a key name (not literal).
  const enterProc = Bun.spawn(['tmux', 'send-keys', '-t', SESSION_NAME, 'Enter'], {
    stdout: 'pipe',
    stderr: 'pipe',
  })
  const enterExit = await enterProc.exited
  if (enterExit !== 0) {
    const stderr = await new Response(enterProc.stderr).text()
    throw new Error(`tmux send-keys (Enter) failed (exit ${enterExit}): ${stderr.trim()}`)
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
    {
      name: 'restart_daemon',
      description:
        'Restart the daemon process. Writes restart reason to state.json, then ' +
        'spawns a detached process that restarts the daemon after a short delay. ' +
        'Use for self-healing, applying config changes, or clean resets.',
      inputSchema: {
        type: 'object' as const,
        properties: {
          reason: {
            type: 'string',
            description: 'Optional reason for the restart (logged to state.json).',
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
    case 'restart_daemon': {
      if (!SCRIPTS_PATH) {
        return {
          content: [{ type: 'text', text: 'Error: CLAWDKIT_SCRIPTS_PATH not set — cannot locate clawdkit.sh.' }],
          isError: true,
        }
      }
      if (!INSTANCE_DIR) {
        return {
          content: [{ type: 'text', text: 'Error: CLAWDKIT_INSTANCE_DIR not set — cannot write state.' }],
          isError: true,
        }
      }

      const reason = (args as Record<string, unknown>)?.reason as string
      const stateFile = join(INSTANCE_DIR, '.clawdkit', 'state.json')

      // Write pending_restart to state.json so the new session knows why it restarted.
      try {
        const raw = await readFile(stateFile, 'utf-8')
        const state = JSON.parse(raw)
        state.pending_restart = reason ?? 'no reason provided'
        state.restart_requested_at = new Date().toISOString()
        await writeFile(stateFile, JSON.stringify(state, null, 2) + '\n')
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err)
        return {
          content: [{ type: 'text', text: `Error: failed to update state.json: ${msg}` }],
          isError: true,
        }
      }

      // Spawn a detached process that waits then restarts the daemon.
      // The delay gives the MCP response time to be delivered before the session dies.
      const clawdkitSh = join(SCRIPTS_PATH, 'clawdkit.sh')
      try {
        Bun.spawn(['sh', '-c', `sleep 2 && "${clawdkitSh}" --instance "${AGENT_NAME}" restart`], {
          stdout: 'ignore',
          stderr: 'ignore',
          stdin: 'ignore',
        })
        // Not awaited — the process outlives us.
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err)
        process.stderr.write(`clawdkit-session-control: restart spawn failed: ${msg}\n`)
        return {
          content: [{ type: 'text', text: `Error: failed to spawn restart process: ${msg}` }],
          isError: true,
        }
      }

      process.stderr.write(`clawdkit-session-control: restart_daemon fired (reason: ${reason ?? 'none'})\n`)

      return {
        content: [{ type: 'text', text: `Daemon restart scheduled (2s delay). Reason: ${reason ?? 'none'}` }],
      }
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
