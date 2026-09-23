# Home Assistant module status

September 22, 2026 · 0.2.0 · local developer preview

| Milestone | Evidence |
| --- | --- |
| Independent package | Swift app and generic vendored SDK; no host implementation changes or other desktop app dependency. |
| New navigation pattern | Favorites / Rooms / Scenes; connection and diagnostics are in Settings. |
| Live-state and control logic | Nine tests pass: exact-origin validation, newer-event reconciliation/removal, room fallback/overrides, control allowlist, subscription/readback, scene acknowledgment, lost-response reconnect without command replay, rejected authentication, denied registries and redirects. Uses loopback test home only. |
| SDK | Handshake, 16:9 diagrams, one-line status, content-only panels and unavailable/unsafe action rejection pass. |
| Native visual check | DEBUG-only Fixture Home: three favorite cards fit; Rooms lists read-only lock and unavailable light; Scenes lists Evening. Native reviewed Desk lamp off changed the fixture state and showed confirmed readback. No household commands sent. |
| Installed module | Signed release installed through NeroNook's package review; Running and enabled on Odyssey Ark and Built-in Retina Display. Native Settings layout inspected. |
| Final update | Final hardening build updated through NeroNook package review. Running on both displays with placement retained. Actual Nook Favorites / Rooms / Scenes surface, 16:9 diagram and side selector visually checked on Odyssey Ark. |
| Real Docker server | Home Assistant 2026.9.3 at http://127.0.0.1:18123, isolated network and virtual devices only. Actual authentication, rooms, inventory, light/switch readback, both scene results and unavailable-target rejection pass using the production HomeCore client. |
| Installed test connection | Connected to the loopback server with six favorites and allowed virtual controls. Nook lamp on/off and Cancel, both scenes and server-side state checks passed. Final package reconnect after Keychain access observed. |
| Physical household | The owner does not have a Home Assistant installation. This Docker environment is explicitly for testing; no physical-household integration is claimed. |

Remaining: prolonged Keychain/reconnect behavior, sleep/wake and prolonged outage acceptance; registry update subscriptions; brightness/color/climate semantics; native HomeKit/Catalyst plugin (SDK type-check passed; provisioning and actual access are not verified); public distribution license/notarization. Scene execution only confirms API acceptance, not each underlying device. A token's account permissions are the server-side boundary; local allowed-controls settings narrow this plugin's own execution.

Reproducible test environment and start/stop instructions: [Testing/HomeAssistant](Testing/HomeAssistant/README.md). Docker test data and credentials are ignored under build/test-home and are not part of the plugin package.

## 0.2.0 — interactive Nook controls

- Replaced the passive Nook diagrams with generic native cards on hosts advertising `control-cards-v1`. Favorites / Rooms / Scenes include search, room filtering, light/switch on-off buttons and scene activation. Review, cancellation and outcome stay in the Nook.
- Plugin validates the currently advertised action, exact saved server, current entity state and allowed controls before dispatch. Busy/unavailable/disabled, unknown and stale actions cannot issue a command. The original window remains available for Settings; older hosts retain the previous presentation.
- Production-plugin protocol test against a disposable fixture passes: light off/on with confirmed readback, scene acceptance, and disabled/unknown/stale-action rejection. All nine HomeCore tests pass; legacy and card-capability protocol handshakes pass.
- Host 0.13.0 and plugin 0.2.0 installed through the existing independent-package update flow; both display placements retained. Actual populated Nook layout visually inspected on Odyssey Ark. Lamp on/off and Cancel worked inside the card; both Work Mode and Evening scenes were activated there and all three virtual device states were independently checked on the real Docker server. The final package reconnected after saved-token access. Evening restored the test devices to their initial state. No physical devices were controlled.
