**October 18 · local 0.2.2 installed:** shared glass, paired Light/Dark, independent bundled presence/particle artwork and component motion. Saved connection/settings remain scoped to this plugin. [Rollout evidence and limits](../NeroNook/reports/redesign-ember-2026-10-18/README.md). No public release.

# Home Assistant for NeroNook

**October 17 · local 0.2.1:** automatic reconnect no longer waits on a hidden
Keychain approval; explicit Connect retains the normal approval flow. The
redesigned Nook reconnects to the existing Docker test home, and Cancel plus
reviewed virtual lamp on/off pass with independent state read-back. Saved settings
and permissions are unchanged. [Qualification and limits](reports/redesign-live-2026-10-17/README.md).

Independent native macOS plugin, 0.2.1 local developer preview. Favorites, Rooms and Scenes occupy the common 16:9 Nook surface. The native home window provides search, room filtering, favorites and individually enabled controls. Connection setup and diagnostics live in Settings, never in a content tab.

## Connect

Install `build/Home Assistant Module.app` using NeroNook Settings → Modules → Install or Update Plugin. Open Plugin Settings and enter your Home Assistant server's base address. Create a long-lived access token in your Home Assistant profile → Security and paste it into the secure field. The token is stored only in this plugin's macOS Keychain service. The plugin does not extract credentials from other applications.

The first connection is read only. In Settings, individually allow the lights, switches and scenes you want to control. Native commands show a target review. Light/switch commands request an explicit on/off state and verify the state afterward. A scene response means Home Assistant accepted the scene; it does not prove all of its devices reached their targets. Locks, doors, climate and security are read only in this slice. Existing controllers and MQTT ownership are unchanged.

Favorites and permissions belong to the configured server. Switching servers resets both. Disconnect pauses the session; the saved connection reconnects on a later plugin launch. Forget removes this plugin's token and settings. Household inventory is held in memory, not written to disk.

## Build and verify

Requires macOS 14+ and Swift 6 / Xcode. No other desktop application, Python, Node, browser session, local web server or HomeKit component is needed at runtime. Home Assistant itself is the service being connected to.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
NERONOOK_SIGNING_IDENTITY='<your code-signing identity>' bash scripts/package.sh
python3 scripts/test-protocol.py
```

The tests use a loopback-only Python standard-library WebSocket fixture. Python is a development dependency only; it is not packaged. The release app includes only the Swift executable, manifest and metadata. A DEBUG-only visual fixture can be selected by the `NeroHomeFixture` bundle key with a 127.0.0.1 endpoint; it reads/writes no user settings or Keychain. That capability is absent from release builds. `--protocol-test` skips saved settings and credentials for the SDK harness.

`Vendor/NookPluginSDK` is a pinned source copy of the generic SDK from NeroNook `eaa9196b828309e01aaa798bfce820c83012181a`. This package does not build against the host checkout or another plugin. SDK public redistribution licensing, notarization and release review remain open.

## Protocol and limits

- Supported Home Assistant WebSocket API, single explicit origin, standard TLS validation; authenticated redirects are refused.
- HTTP is accepted only for explicitly selected private IPv4, localhost or `.local` addresses. Use HTTPS on untrusted networks. ATS allows the selected local HTTP transport; endpoint validation rejects public HTTP. No certificate exceptions are installed.
- Subscribe before fetching initial state, then reconcile buffered newer events. Clear inventory and disable controls when disconnected or authorization fails. Reconnect rebuilds subscriptions and inventory; it never replays a command.
- Ten-second request deadlines, keepalive checks, bounded frames/inventory and request/run limits. No optimistic device-state updates.
- Optional room registries fall back to Unassigned when unavailable to the account. Registry name/membership changes are refreshed on reconnect in this first slice.
- SDK exports: `read_status`, `set_power(server, entity, on)`, `activate_scene(server, entity)` and fresh `status`. External SDK actions receive NeroNook's per-run review and are validated again in this plugin against the configured server, allowed entity, live state and available service.

Sources: [WebSocket API](https://developers.home-assistant.io/docs/api/websocket/), [authentication](https://developers.home-assistant.io/docs/auth_api/).

A real, isolated [Docker test home](Testing/HomeAssistant/README.md) is available for development with virtual lights, sensors and scenes. Docker is a test dependency only. See [STATUS.md](STATUS.md) for verified evidence and remaining acceptance.

### Controls inside NeroNook (0.2.0)

With NeroNook 0.13.0 or later, Favorites, Rooms and Scenes are interactive native cards. Switch an allowed light/device on or off, or activate a scene; review and confirm in the same card. The module reports confirmed light/switch state or scene API acceptance in the Nook. Search and room filtering stay inside the 16:9 interface. Unavailable devices and controls not enabled in Settings remain disabled. Sensors and other unsupported domains remain read only.

The host's shared `control-cards-v1` SDK handles presentation and opaque action delivery. This package still owns the server, credentials, allowed targets, stale-state checks and actual commands. Older hosts retain the passive diagram and separate-window fallback. Each panel includes up to 64 items, further bounded by encoded message size; large inventories should use Favorites for everyday devices. No household or endpoint state is written to NeroNook.

Run `python3 scripts/test-inline-controls.py` after a debug build for production-plugin inline dispatch against a disposable loopback fixture. It never reads saved settings or Keychain credentials.
