import { describe, it, expect, beforeEach, afterEach } from 'bun:test'
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { getBudgetStatus } from './handlers'

describe('getBudgetStatus', () => {
  let tmpDir: string

  beforeEach(async () => {
    tmpDir = await mkdtemp(join(tmpdir(), 'clawdkit-test-'))
    await mkdir(join(tmpDir, '.clawdkit'), { recursive: true })
  })

  afterEach(async () => {
    await rm(tmpDir, { recursive: true, force: true })
  })

  async function writeState(state: Record<string, unknown>) {
    await writeFile(join(tmpDir, '.clawdkit', 'state.json'), JSON.stringify(state))
  }

  it('parses a fully populated state', async () => {
    await writeState({
      budget_mode: 'normal',
      five_hour_used_pct: 18,
      five_hour_resets_at: 1775433600,
      seven_day_used_pct: 8,
      session_input_tokens: 183513,
      session_output_tokens: 75903,
      session_cost_usd: 9.7988,
      usage_updated_at: '2026-04-05T23:31:42Z',
      low_fuel_threshold_pct: 80,
      exhausted_threshold_pct: 95,
    })

    const result = await getBudgetStatus(tmpDir)
    expect(result.error).toBeUndefined()
    expect(result.lines).toBeDefined()

    const text = result.lines!.join('\n')
    expect(text).toContain('Budget mode: normal')
    expect(text).toContain('5-hour usage: 18%')
    expect(text).toContain('7-day usage: 8%')
    expect(text).toContain('183,513 in')
    expect(text).toContain('75,903 out')
    expect(text).toContain('$9.7988')
    expect(text).toContain('Thresholds: low-fuel 80%, exhausted 95%')
    expect(text).toContain('Last updated: 2026-04-05T23:31:42Z')
  })

  it('handles null rate limit fields (fresh state)', async () => {
    await writeState({
      budget_mode: 'normal',
      five_hour_used_pct: null,
      seven_day_used_pct: null,
      session_input_tokens: null,
      session_output_tokens: null,
      session_cost_usd: null,
      usage_updated_at: null,
    })

    const result = await getBudgetStatus(tmpDir)
    expect(result.error).toBeUndefined()

    const text = result.lines!.join('\n')
    expect(text).toContain('Budget mode: normal')
    expect(text).toContain('not available (status line not yet active)')
    expect(text).not.toContain('7-day usage')
    expect(text).not.toContain('Session tokens')
    expect(text).not.toContain('Session cost')
  })

  it('defaults budget_mode to unknown when missing', async () => {
    await writeState({})

    const result = await getBudgetStatus(tmpDir)
    expect(result.error).toBeUndefined()

    const text = result.lines!.join('\n')
    expect(text).toContain('Budget mode: unknown')
  })

  it('defaults thresholds to 80/95 when missing', async () => {
    await writeState({ budget_mode: 'normal' })

    const result = await getBudgetStatus(tmpDir)
    const text = result.lines!.join('\n')
    expect(text).toContain('Thresholds: low-fuel 80%, exhausted 95%')
  })

  it('handles custom thresholds', async () => {
    await writeState({
      budget_mode: 'low-fuel',
      low_fuel_threshold_pct: 70,
      exhausted_threshold_pct: 90,
    })

    const result = await getBudgetStatus(tmpDir)
    const text = result.lines!.join('\n')
    expect(text).toContain('Budget mode: low-fuel')
    expect(text).toContain('Thresholds: low-fuel 70%, exhausted 90%')
  })

  it('returns error when state.json is missing', async () => {
    await rm(join(tmpDir, '.clawdkit'), { recursive: true, force: true })

    const result = await getBudgetStatus(tmpDir)
    expect(result.error).toBeDefined()
    expect(result.error).toContain('Failed to read budget status')
  })

  it('returns error when state.json is invalid JSON', async () => {
    await writeFile(join(tmpDir, '.clawdkit', 'state.json'), 'not json')

    const result = await getBudgetStatus(tmpDir)
    expect(result.error).toBeDefined()
    expect(result.error).toContain('Failed to read budget status')
  })

  it('handles partial token data (only input)', async () => {
    await writeState({
      budget_mode: 'normal',
      session_input_tokens: 5000,
      session_output_tokens: null,
    })

    const result = await getBudgetStatus(tmpDir)
    const text = result.lines!.join('\n')
    expect(text).toContain('Session tokens: 5,000 in / 0 out')
  })
})
