# Home Assistant module
Independent native macOS plugin. NeroNook and Apple Home are not dependencies. Only the vendored, generic SDK is shared. Build and package here without modifying the host.
Tabs are useful content: Favorites, Rooms, Scenes. Put setup, credentials and diagnostics in Settings.
Credentials belong solely in this plugin's Keychain. Never import tokens from another app. Do not log tokens or persist household state. Use the user's chosen server; standard TLS validation, no certificate bypass or authenticated redirects.
First slice: live inventory and opt-in light/switch/scene controls only. Never send generic toggles to locks, doors, security, climate or household controllers. Commands are not retried. Preserve the independent MQTT broker and existing controller authority.
Test parsers, synchronization, policy and reconnect behavior. Clearly separate local fixtures, installed UI and live household verification.
