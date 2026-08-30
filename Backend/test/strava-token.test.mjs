import assert from 'node:assert/strict'
import test from 'node:test'
import handler from '../api/strava-token.mjs'

function recorder() {
  return {
    statusCode: 200,
    headers: {},
    payload: undefined,
    setHeader(name, value) { this.headers[name] = value },
    status(code) { this.statusCode = code; return this },
    json(value) { this.payload = value; return this },
  }
}

test('rejects non-POST requests', async () => {
  const response = recorder()
  await handler({ method: 'GET' }, response)
  assert.equal(response.statusCode, 405)
})

test('keeps client credentials server-side during code exchange', async () => {
  process.env.STRAVA_CLIENT_ID = '12345'
  process.env.STRAVA_CLIENT_SECRET = 'server-only-secret'
  const originalFetch = globalThis.fetch
  let upstreamBody
  globalThis.fetch = async (_url, options) => {
    upstreamBody = options.body
    return new Response(JSON.stringify({
      access_token: 'access',
      refresh_token: 'refresh',
      expires_at: 1_900_000_000,
    }), { status: 200, headers: { 'Content-Type': 'application/json' } })
  }
  try {
    const response = recorder()
    await handler({
      method: 'POST',
      body: {
        grant_type: 'authorization_code',
        code: 'one-time-code',
        redirect_uri: 'routelatch://routelatch.app/strava-auth',
      },
    }, response)
    assert.equal(response.statusCode, 200)
    assert.equal(upstreamBody.get('client_secret'), 'server-only-secret')
    assert.equal(response.payload.client_secret, undefined)
  } finally {
    globalThis.fetch = originalFetch
    delete process.env.STRAVA_CLIENT_ID
    delete process.env.STRAVA_CLIENT_SECRET
  }
})
