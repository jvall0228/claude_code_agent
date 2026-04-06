/**
 * Heartbeat HTTP request handler — extracted for testability.
 *
 * The handler receives a notifier function so the MCP server wiring
 * stays in server.ts while the logic can be tested independently.
 */

export type Notifier = (body: string) => Promise<void>

export function createFetchHandler(notifier: Notifier) {
  return async function handleRequest(req: Request): Promise<Response> {
    try {
      const url = new URL(req.url)

      if (url.pathname === '/heartbeat' && req.method === 'POST') {
        const body = await req.text()
        if (!body.trim()) {
          return new Response('empty body', { status: 400 })
        }

        try {
          await notifier(body)
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
  }
}
