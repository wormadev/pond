# Tasks

## v1 (Tailscale)
- [x] Tailscale serve route to Pond on the Mac
- [x] Connect screen, token in shared Keychain
- [x] Library grid with paging, sort, pull to refresh
- [x] Sidebar: All, Uncategorized, Untagged, Trash, smart folders, folders, tags, sources
- [x] Search: keywords and meaning
- [x] Detail: media pager, zoom, video, caption
- [x] Edit: tags, folders, rating, note, trash, restore
- [x] Share extension with offline queue
- [ ] Run on the physical iPhone
- [ ] Video playback against a Save whose video has finished downloading (none in the library yet)
- [ ] Offline queue: share while the Mac is unreachable, then flush
- [x] App icon
- [ ] Share extension sheet polish

## Later
- [x] Redesign to R1-B (tabs, collection covers, tile grids); simulator only
- [ ] Ship the redesign to TestFlight and check on the iPhone

## Connect (login, no Tailscale) - relay inside a Cloudflare Worker
- [x] Account service and relay at ponds.worma.dev (`apps/connect`), deployed
- [x] iOS: sign in, pick a Mac
- [x] Mac connector (`apps/connect/client/connector.ts`), run by hand for now
- [ ] Sign in to the real account in Pond desktop's Settings > Account (replaces the launchd connector)
- [x] Connector and Account section inside Pond desktop (`apps/desktop/src/main/connect`); sign-in dialog and signed-out state not yet seen on screen
- [ ] Replace the installed Pond with the fork build
- [ ] `/api/v2/app/info` through the relay includes the local MCP command path (the connector calls from loopback)
- [ ] Fork build signs with a different team: Safari and Share extensions use the upstream app group and won't load
- [x] Tests for the account service (`bunx vitest run` in `apps/connect`)
- [ ] Password reset and email verification
