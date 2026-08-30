const STRAVA_TOKEN_URL = 'https://www.strava.com/oauth/token'
const STRAVA_REVOKE_URL = 'https://www.strava.com/oauth/revoke'

export default async function handler(request, response) {
  response.setHeader('Cache-Control', 'no-store')
  if (request.method !== 'POST') {
    response.setHeader('Allow', 'POST')
    return response.status(405).json({ message: 'Method not allowed' })
  }

  const clientId = process.env.STRAVA_CLIENT_ID
  const clientSecret = process.env.STRAVA_CLIENT_SECRET
  if (!clientId || !clientSecret) {
    return response.status(503).json({ message: 'Strava credentials are not configured' })
  }

  try {
    const body = typeof request.body === 'string' ? JSON.parse(request.body) : request.body ?? {}
    if (body.action === 'revoke') {
      if (typeof body.token !== 'string' || body.token.length < 8) {
        return response.status(400).json({ message: 'A token is required' })
      }
      const basicCredentials = Buffer.from(`${clientId}:${clientSecret}`).toString('base64')
      const revokeResponse = await fetch(STRAVA_REVOKE_URL, {
        method: 'POST',
        headers: {
          Authorization: `Basic ${basicCredentials}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({ token: body.token, token_type_hint: 'refresh_token' }),
      })
      if (!revokeResponse.ok) return forwardError(revokeResponse, response)
      return response.status(200).json({ ok: true })
    }

    if (body.grant_type !== 'authorization_code' && body.grant_type !== 'refresh_token') {
      return response.status(400).json({ message: 'Unsupported grant type' })
    }
    const parameters = new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      grant_type: body.grant_type,
    })
    if (body.grant_type === 'authorization_code') {
      if (typeof body.code !== 'string' || typeof body.redirect_uri !== 'string') {
        return response.status(400).json({ message: 'Code and redirect URI are required' })
      }
      parameters.set('code', body.code)
      parameters.set('redirect_uri', body.redirect_uri)
    } else {
      if (typeof body.refresh_token !== 'string') {
        return response.status(400).json({ message: 'Refresh token is required' })
      }
      parameters.set('refresh_token', body.refresh_token)
    }

    const tokenResponse = await fetch(STRAVA_TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: parameters,
    })
    if (!tokenResponse.ok) return forwardError(tokenResponse, response)
    return response.status(200).json(await tokenResponse.json())
  } catch (error) {
    console.error('Strava token broker failed', error)
    return response.status(500).json({ message: 'Token broker request failed' })
  }
}

async function forwardError(upstream, response) {
  const text = await upstream.text()
  let payload
  try { payload = JSON.parse(text) } catch { payload = { message: text || `Strava HTTP ${upstream.status}` } }
  return response.status(upstream.status).json(payload)
}
