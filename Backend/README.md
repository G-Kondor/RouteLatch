# RouteLatch Strava token broker

This function keeps the Strava client secret out of the iOS application. It exchanges OAuth authorization codes, refreshes short-lived access tokens, and revokes tokens. Activity files are uploaded directly from RouteLatch to Strava and never pass through this service.

## Configure

1. Create an API application at <https://www.strava.com/settings/api>.
2. Set its callback domain to `routelatch.app`; the mobile redirect used by the app is `routelatch://routelatch.app/strava-auth`.
3. Deploy this function to the `route-latch` Vercel project. The production endpoint is <https://route-latch.vercel.app/api/strava-token>.
4. Add `STRAVA_CLIENT_ID` and `STRAVA_CLIENT_SECRET` as Production environment variables; keep the secret encrypted.
5. Set the iOS target build settings:
   - `STRAVA_CLIENT_ID` to the same numeric client ID.
   - `STRAVA_TOKEN_BROKER_URL` to `https://route-latch.vercel.app/api/strava-token`.

Never commit `.env` files, the client secret, access tokens, or refresh tokens.
