import { describe, it, expect, mock } from 'bun:test'
import { createFetchHandler } from './handler'

function req(method: string, path: string, body?: string): Request {
  return new Request(`http://localhost${path}`, {
    method,
    body: body ?? undefined,
  })
}

describe('heartbeat HTTP handler', () => {
  it('returns 200 on valid POST /heartbeat', async () => {
    const notifier = mock(() => Promise.resolve())
    const handler = createFetchHandler(notifier)

    const res = await handler(req('POST', '/heartbeat', 'hello heartbeat'))

    expect(res.status).toBe(200)
    expect(notifier).toHaveBeenCalledTimes(1)
    expect(notifier.mock.calls[0][0]).toBe('hello heartbeat')
  })

  it('returns 400 on empty body', async () => {
    const notifier = mock(() => Promise.resolve())
    const handler = createFetchHandler(notifier)

    const res = await handler(req('POST', '/heartbeat', ''))
    expect(res.status).toBe(400)
    expect(await res.text()).toBe('empty body')
    expect(notifier).not.toHaveBeenCalled()
  })

  it('returns 400 on whitespace-only body', async () => {
    const notifier = mock(() => Promise.resolve())
    const handler = createFetchHandler(notifier)

    const res = await handler(req('POST', '/heartbeat', '   \n  '))
    expect(res.status).toBe(400)
    expect(notifier).not.toHaveBeenCalled()
  })

  it('returns 404 on wrong path', async () => {
    const notifier = mock(() => Promise.resolve())
    const handler = createFetchHandler(notifier)

    const res = await handler(req('POST', '/other', 'body'))
    expect(res.status).toBe(404)
    expect(notifier).not.toHaveBeenCalled()
  })

  it('returns 404 on GET /heartbeat', async () => {
    const notifier = mock(() => Promise.resolve())
    const handler = createFetchHandler(notifier)

    const res = await handler(req('GET', '/heartbeat'))
    expect(res.status).toBe(404)
    expect(notifier).not.toHaveBeenCalled()
  })

  it('returns 500 when notifier throws', async () => {
    const notifier = mock(() => Promise.reject(new Error('MCP down')))
    const handler = createFetchHandler(notifier)

    const res = await handler(req('POST', '/heartbeat', 'hello'))
    expect(res.status).toBe(500)
    expect(await res.text()).toBe('notification failed')
  })
})
