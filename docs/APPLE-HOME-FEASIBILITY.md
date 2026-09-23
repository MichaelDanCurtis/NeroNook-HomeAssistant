# Separate Apple Home integration

September 22, 2026. Home Assistant works independently of this planned integration. None of the code below belongs in NeroNook core or is required by the Home Assistant module.

Apple DTS documents that HomeKit on Mac is available through Mac Catalyst. An independent Catalyst app can read homes, rooms and accessories through HMHomeManager, then present the same generic plugin SDK contract. NeroNook stays native AppKit. Each integration retains its own identity, permission and lifecycle; do not merge accessories across providers without explicit identity mapping.

A local type-check succeeded with Xcode 27 and the installed macOS SDK, using arm64-apple-ios15.0-macabi and the iOSSupport HomeKit framework. The probe accessed HMHomeManager.homes, HMHome.rooms and HMHome.accessories. This confirms API/toolchain availability only. It did not initialize a home manager, request Home access, sign a runnable entitled app, obtain a provisioning profile or read actual homes.

Neither standard local provisioning-profile directory currently exists on this Mac. The existing Apple Development identity by itself is not evidence that a HomeKit-capable Catalyst app is provisioned. Next steps are an independently packaged Catalyst app, its explicit HomeKit entitlement and usage description, valid signing/provisioning, followed by user Home permission and read-only live inventory. The native-plugin standard-input/output lifecycle also needs actual Catalyst acceptance; compile availability does not prove that boundary works unchanged.

Content navigation stays Favorites / Rooms / Scenes; a Settings action owns authorization and provider selection. Selected light/scene control comes after read-only inventory. No unlock, door, security, arbitrary scene, or controller authority is inferred from the Home permission.

Sources: [Apple DTS: HomeKit on macOS](https://developer.apple.com/forums/thread/822517), [HomeKit](https://developer.apple.com/documentation/homekit).
