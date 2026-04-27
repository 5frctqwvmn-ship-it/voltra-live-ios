# voltra-trace-relay

Cloudflare Worker that accepts JSON traces from VOLTRA Live iOS Demo Mode and
opens a GitHub issue on the `voltra-live-ios` repo with the trace inline.

The Worker exists so that **no GitHub credentials ship in the iOS binary**.
TestFlight binaries can be unpacked and any embedded PAT extracted; the
Worker keeps the PAT in encrypted environment variables and gates access
behind a shared secret that's only useful for spam prevention.

## One-time setup

1. Create a fine-grained GitHub PAT
   - Resource owner: your account
   - Repo access: only `voltra-live-ios`
   - Permissions: **Issues — Read and write**
2. Install Wrangler if needed: `npm install -g wrangler`
3. Authenticate: `wrangler login`
4. From this directory:
   ```
   wrangler deploy
   wrangler secret put GITHUB_PAT       # paste the PAT
   wrangler secret put GITHUB_REPO      # e.g. 5frctqwvmn-ship-it/voltra-live-ios
   wrangler secret put APP_SHARED_TOKEN # any random string, also goes into the iOS Info.plist
   ```
5. Note the deployed URL (e.g. `https://voltra-trace-relay.<subdomain>.workers.dev`).
6. In `release.yml`, populate `DemoTraceEndpoint` and `DemoTraceSharedToken`
   in Info.plist at build time. (See SIGNING-SETUP.md for the pattern.)

## Health check

```
curl https://voltra-trace-relay.<subdomain>.workers.dev/
# {"ok":true,"service":"voltra-trace-relay"}
```

## Posting a trace (smoke test)

```
curl -X POST https://voltra-trace-relay.<subdomain>.workers.dev/trace \
  -H "Content-Type: application/json" \
  -H "X-Voltra-Trace-Token: <APP_SHARED_TOKEN>" \
  -d '{"header":{"appShort":"0.4.6.3","appBuild":"26","entrySource":"prePair","startedAtIso":"2026-04-27T15:00:00Z","device":"iOS","osVersion":"18.0","traceVersion":1},"records":[],"userNote":"smoke test"}'
```
