/**
 * Session-control tool handlers — extracted for testability.
 */

import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

export interface BudgetStatus {
  lines: string[]
  error?: undefined
}

export interface BudgetError {
  lines?: undefined
  error: string
}

export async function getBudgetStatus(instanceDir: string): Promise<BudgetStatus | BudgetError> {
  const statePath = join(instanceDir, '.clawdkit', 'state.json')
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

    return { lines }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    return { error: `Failed to read budget status: ${msg}` }
  }
}
