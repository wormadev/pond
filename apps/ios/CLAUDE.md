# Ripple

iPhone client for Pond, living in this fork at `apps/ios`. Upstream: https://github.com/raphaelsalaja/pond, a local-first web archive that runs on the Mac. SwiftUI, iOS 18+, iPhone only. iPad and Android may come later.

## How it reaches Pond

- Pond's HTTP API listens on loopback only (`127.0.0.1:41610/api/v2`). The Mac exposes it to the tailnet with `tailscale serve --bg --https=41610 http://127.0.0.1:41610`.
- The app stores the address in the App Group defaults and a scoped Pond token (Search Saves, Add and Edit Saves; Export Files for image tools; Manage Library for Libraries, Tags, Sources, Inbox and Assistant, which go through `/operations`) in the shared Keychain group. Never hardcode either.
- Only works while the Mac is on, Pond is open, and the phone is on Tailscale. Planned next: account login in Pond desktop plus a Cloudflare Tunnel from the Mac (decision T-1), so Tailscale isn't needed. The account service stores accounts and Mac links only, never Saves or media.
- API reference: `docs/api.md` in the Pond repo. Only the scoped-token routes are used; `/session` is off limits.

## Known API limits

- `/saves/file` has no byte ranges, so videos are downloaded to Caches before playing.
- There is no file listing. `PondAPI.files(of:)` reads the headers of each index. Post media is named `media-N.*`; `poster-N`, `*_thumbnail.webp` and `avatar.*` are extras.
- Query results often have no width or height, so cards learn their aspect ratio from the thumbnail.

## Layout

- `Shared/`: API client, models, connection storage, pending-save queue. Compiled into the app and the share extension.
- `Ripple/`: the app, by feature (`Connect`, `Home`, `Library`, `Detail`, `Downloads`).
- `RippleShare/`: share extension. Saves the shared link, or queues it when the Mac is unreachable.
- `project.yml` is the source of truth. Run `xcodegen generate`; the `.xcodeproj`, Info.plists and entitlements are generated and ignored.

## Design (fixed, add no new values)

Pond's default dark theme. Layout R1-B: tabs for Library, Collections (home), Downloads and Search. Home shows recent Saves, then tags and folders as covers. Grids are three columns of 4:5 tiles with no text.

- Colors: background `#0A0A0A`, foreground `#EEEEEE`, accent `#008FFF`. Muted, surface and border are foreground at 55%, 7% and 12%.
- Font: Inter Variable (bundled). Four sizes: 12, 14, 16, 26.
- Radius: 6 cards and chips, 8 controls. No shadows, borders at 0.5pt.
- Spacing unit: 4pt (`Theme.unit`).
- Icons: SF Symbols. Dark mode only.

## TestFlight

- App Store Connect app id `6835056666`, internal group `Internal`
- Export the ipa with `PATH=/usr/bin:/bin:/usr/sbin:/sbin`: Homebrew rsync breaks `xcodebuild -exportArchive` ("Copy failed")
- Bump `CURRENT_PROJECT_VERSION` in `project.yml` for every upload, then `asc builds upload --app 6835056666 --ipa build/export/Ripple.ipa`

## UI gate

UI work follows the build-ui skill (github.com/mshll/skills). Shared parts live in `Ripple/App/Components.swift`; use them before writing a local row, header, empty state or skeleton.

- `RippleTests` renders every screen in every state (full, worst case, empty, failed, loading) from `Fixtures.swift`, at 3 widths and 3 text sizes
- Run it with `TEST_RUNNER_SNAPSHOT_DIR=<dir outside /Volumes> xcodebuild test -project Ripple.xcodeproj -scheme Ripple -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:RippleTests`, then read each `sheet.png`
- The simulator cannot write to the external volume, so the output directory must be on the internal disk

## Pond Connect

Decision: the phone reaches the Mac through a relay inside a Cloudflare Worker at `ponds.worma.dev` (`apps/connect`), not a tunnel per Mac. The Mac keeps one WebSocket open to the relay; nothing is stored there but accounts and Mac links.

- The password never leaves the device: clients send a PBKDF2-SHA256 key (600,000 rounds, salt `pond-connect:<lowercase email>`). iOS and the connector must derive it the same way
- A signed-in connection is `https://ponds.worma.dev/m/<machine id>` with the session token as the bearer; the Mac adds Pond's own token locally
- The address and token form stays as a fallback
- Pond desktop holds the Mac side (Settings > Account). Its socket sends the session token as the `bearer.<token>` WebSocket subprotocol, and it reaches the local API with its own scoped token named "Pond Connect", never the Local API Token
- Desktop toolchain: node 24 and pnpm 11.27.0 live in `~/.cache/pond-toolchain/node/bin`; put it first on PATH. `apps/connect` is excluded from the pnpm workspace and uses bun
