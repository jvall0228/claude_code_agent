#!/usr/bin/env bun
/**
 * Session Control MCP server for ClawdKit.
 *
 * Provides tools for the daemon agent to manage its own Claude Code session
 * (clear context, compact context) via tmux send-keys.
 */

import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { Server } from '@modelcontextprotocol/sdk/server/index.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js'

const AGENT_NAME = process.env.CLAWDKIT_AGENT_NAME ?? 'clawdkit'
const SESSION_NAME = `clawdkit-${AGENT_NAME}`
const INSTANCE_DIR = process.env.CLAWDKIT_INSTANCE_DIR ?? join(process.env.HOME ?? '', '.clawdcode', AGENT_NAME)
const SCRIPTS_DIR = join(import.meta.dir, '..', '..', 'scripts')

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
      'Use clear_context for a full reset, compact_context to summarize and shrink. ' +
      'Use restart_daemon to restart the entire daemon session (preserves state via state.json).',
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
      name: 'get_budget_status',
      description:
        'Query current daily token budget status. Returns budget mode, token estimate, ' +
        'max daily tokens, percentage used, and reset date. Read-only — does not modify state.',
      inputSchema: { type: 'object' as const, properties: {} },
    },
    {
      name: 'restart_daemon',
      description:
        'Restart the daemon session. Kills the current tmux session and starts a fresh one. ' +
        'State is preserved via state.json. Use for applying config changes, self-healing, or ' +
        'resetting after errors. The restart happens asynchronously — this tool returns immediately.',
      inputSchema: {
        type: 'object' as const,
        properties: {
          reason: {
            type: 'string',
            description: 'Why the restart is being triggered (logged to progress.log).',
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
    case 'get_budget_status': {
      const statePath = join(INSTANCE_DIR, '.clawdkit', 'state.json')
      try {
        const raw = await readFile(statePath, 'utf-8')
        const state = JSON.parse(raw) as Record<string, unknown>

        const mode = (state.budget_mode as string) ?? 'unknown'
        const fiveHourPct = state.five_hour_used_pct as number | null
        const fiveHourResets = state.five_hour_resets_at as number | null
        const sevenDayPct = state.seven_day_used_pct as number | null
        const inputTokens = state.session_input_tokens as number | null
        const outputTokens = state.session_output_tokens as number | null
        const costUsd = state.session_cost_usd as number | null
        const updatedAt = (state.usage_updated_at as string) ?? null
        const lowFuel = (state.low_fuel_threshold_pct as number) ?? 80
        const exhausted = (state.exhausted_threshold_pct as number) ?? 95

        const lines = [`Budget mode: ${mode}`]

        if (fiveHourPct != null) {
          const resetStr = fiveHourResets
            ? new Date(fiveHourResets * 1000).toISOString()
            : 'unknown'
          lines.push(`5-hour usage: ${fiveHourPct}% (resets ${resetStr})`)
        } else {
          lines.push('5-hour usage: not available (status line not yet active)')
        }

        if (sevenDayPct != null) {
          lines.push(`7-day usage: ${sevenDayPct}%`)
        }

        if (inputTokens != null || outputTokens != null) {
          lines.push(`Session tokens: ${(inputTokens ?? 0).toLocaleString()} in / ${(outputTokens ?? 0).toLocaleString()} out`)
        }

        if (costUsd != null) {
          lines.push(`Session cost: $${costUsd.toFixed(4)}`)
        }

        lines.push(`Thresholds: low-fuel ${lowFuel}%, exhausted ${exhausted}%`)

        if (updatedAt) {
          lines.push(`Last updated: ${updatedAt}`)
        }

        return { content: [{ type: 'text', text: lines.join('\n') }] }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err)
        return {
          isError: true,
          content: [{ type: 'text', text: `Failed to read budget status: ${msg}` }],
        }
      }
    }
    case 'restart_daemon': {
      const reason = ((args as Record<string, unknown>)?.reason as string) ?? 'no reason given'
      const clawdkitSh = join(SCRIPTS_DIR, 'clawdkit.sh')
      const logFile = join(INSTANCE_DIR, '.clawdkit', 'progress.log')
      const ts = new Date().toISOString().replace(/\.\d+Z$/, 'Z')

      // Log the restart reason before we die
      const logLine = `[${ts}] [${AGENT_NAME}] restart_daemon triggered — ${reason}\n`
      try {
        const { appendFileSync } = await import('node:fs')
        appendFileSync(logFile, logLine)
      } catch { /* best effort */ }

      // Spawn a fully detached process that waits 2s then restarts.
      // The delay gives the MCP response time to reach the agent.
      // nohup + setsid ensure the process survives the tmux session kill.
      const restartCmd = `sleep 2 && "${clawdkitSh}" --instance "${AGENT_NAME}" restart`
      Bun.spawn(['nohup', 'sh', '-c', restartCmd], {
        stdout: 'ignore',
        stderr: 'ignore',
        stdin: 'ignore',
      }).unref()

      return {
        content: [{ type: 'text', text: `Restart scheduled in 2 seconds. Reason: ${reason}` }],
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
