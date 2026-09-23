# Real Home Assistant Docker test home

Requested September 22, 2026. Home Assistant **2026.9.3**, pinned to official image digest `sha256:d8922685169707fd91e8b9729902d975f06157d005e422874d201e0261dda196`.

This is a real Home Assistant server containing only virtual devices. It is separate from the production plugin and creates no dependency on Docker for plugin users. Existing Docker containers, physical household devices and MQTT brokers are untouched.

The server has only an internal Docker network and no published port. A tiny fixed-destination TCP relay exposes its API on **127.0.0.1:18123**. Docker 29 did not publish a port on an internal-only network, so the relay supplies Mac access while the Home Assistant container retains no outbound route. Neither container is privileged; there are no device, Docker-socket or host-network mounts. The relay uses the same cached official image with Python as its entrypoint; no third-party relay image is required. Local-only test traffic uses HTTP.

## Run and stop

From this repository:

```sh
bash Testing/HomeAssistant/start.sh
python3 Testing/HomeAssistant/connect-plugin.py
```

Restart Home Assistant under NeroNook Settings → Modules. macOS may ask the user to approve its new Keychain item. The development credential helper assigns the new test item to the installed plugin; it does not change other Keychain entries. Its legacy macOS Keychain access-list APIs emit deprecation warnings. It is a setup helper only, never packaged into the app.

The server is at http://127.0.0.1:18123. Disposable browser login is in `build/test-home/login.txt` (mode 0600). The account/token file and Home Assistant runtime configuration stay under ignored `build/test-home/`; do not commit or share them. The plugin token has a 30-day lifespan. The helper refuses to replace a different configured home. Re-running bootstrap after the token expires requires fresh local test authorization.

```sh
# Stop both test containers; preserve configuration and login.
docker compose -f Testing/HomeAssistant/compose.yaml stop
# Resume the test home.
docker compose -f Testing/HomeAssistant/compose.yaml start
```

The containers use no automatic restart policy. Data persists in the dedicated bind mount. Stopping them does not delete test data.

## Virtual inventory

- Office: Desk Lamp, Desk Fan, temperature and humidity.
- Living Room: Reading Light and an intentionally unavailable Offline Light.
- Scenes: Work Mode and Evening, affecting only the three virtual light/switch helpers.
- Home Assistant also exposes helper/internal entities. Six useful device cards are selected as Nook favorites.

## Verification

```sh
xcrun swiftc -parse-as-library Sources/HomeCore/Models.swift Sources/HomeCore/Client.swift \
  Testing/HomeAssistant/Check.swift -o build/test-home/check
build/test-home/check build/test-home/credentials.json
```

Verified against the real Docker server: authentication, room mapping, live inventory, light and switch on/off with readback, both scene outcomes independently read back, and unavailable-target rejection. Final test scene is Work Mode. Docker inspection confirms Mac-loopback publishing, unprivileged containers and an internal Home Assistant network; a direct outbound connection attempt from that container failed.

The installed plugin is configured with the test address, allowed virtual controls and favorites. Its native UI was waiting for the user's macOS Keychain approval at this checkpoint; installed interactive control and reconnect acceptance remain pending. Direct API/client tests are not a substitute for that UI/Keychain check or for physical-device acceptance.

Sources: [official Container installation](https://www.home-assistant.io/installation/linux), [template virtual entities](https://www.home-assistant.io/integrations/template), and the onboarding API implementation inside the pinned official image. No authentication is bypassed; the disposable user is created through Home Assistant's onboarding endpoint.
