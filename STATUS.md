# Home Assistant module status

September 22, 2026 · 0.1.0 · local developer preview

| Milestone | Evidence |
| --- | --- |
| Independent package | Swift app and generic vendored SDK; no host implementation changes or other desktop app dependency. |
| New navigation pattern | Favorites / Rooms / Scenes; connection and diagnostics are in Settings. |
| Live-state and control logic | Nine tests pass: exact-origin validation, newer-event reconciliation/removal, room fallback/overrides, control allowlist, subscription/readback, scene acknowledgment, lost-response reconnect without command replay, rejected authentication, denied registries and redirects. Uses loopback test home only. |
| SDK | Handshake, 16:9 diagrams, one-line status, content-only panels and unavailable/unsafe action rejection pass. |
| Native visual check | DEBUG-only Fixture Home: three favorite cards fit; Rooms lists read-only lock and unavailable light; Scenes lists Evening. Native reviewed Desk lamp off changed the fixture state and showed confirmed readback. No household commands sent. |
| Installed module | Signed release installed through NeroNook's package review; Running and enabled on Odyssey Ark and Built-in Retina Display. Native Settings layout inspected. |
| Final update | Final hardening build updated through NeroNook package review. Running on both displays with placement retained. Actual Nook Favorites / Rooms / Scenes surface, 16:9 diagram and side selector visually checked on Odyssey Ark. |
| Actual household | Pending the owner's server address, user-entered access token and a chosen safe live target. No live connectivity or physical device behavior claimed. |

Remaining: live auth/state agreement, Keychain reconnect/update behavior, sleep/wake and prolonged outage acceptance; registry update subscriptions; brightness/color/climate semantics; native HomeKit/Catalyst plugin (SDK type-check passed; provisioning and actual access are not verified); public distribution license/notarization. Scene execution only confirms API acceptance, not each underlying device. A token's account permissions are the server-side boundary; local allowed-controls settings narrow this plugin's own execution.
