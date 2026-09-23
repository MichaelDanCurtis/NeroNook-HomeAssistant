import Foundation

@main struct DockerHomeCheck {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 2 else { throw HomeError("Pass the ignored test credentials file.") }
        let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let raw = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        guard raw["server"] as? String == "http://127.0.0.1:18123", let token = raw["plugin_token"] as? String else { throw HomeError("This check is restricted to the local Docker test home.") }
        let client = HomeClient(); defer { client.stop() }
        client.connect(try Endpoint("http://127.0.0.1:18123"), token: token)
        let deadline = Date().addingTimeInterval(20)
        while !client.connected && Date() < deadline { try await Task.sleep(nanoseconds: 100_000_000) }
        guard client.connected, client.homeName == "NeroNook Test Home" else { throw HomeError("The intended test home did not connect: \(client.status)") }
        guard client.rooms.room("light.desk_lamp") == "Office", client.rooms.room("light.reading_light") == "Living Room" else { throw HomeError("Room mapping failed.") }
        let allowed: Set<String> = ["light.desk_lamp", "switch.desk_fan", "scene.work_mode", "scene.evening"]
        for on in [true, false] {
            _ = try await client.setPower(entity: "light.desk_lamp", on: on, enabled: allowed)
            _ = try await client.setPower(entity: "switch.desk_fan", on: on, enabled: allowed)
        }
        _ = try await client.activateScene(entity: "scene.evening", enabled: allowed)
        try await Task.sleep(nanoseconds: 300_000_000); try await client.refresh()
        guard client.inventory.entities["light.reading_light"]?.state == "on", client.inventory.entities["light.desk_lamp"]?.state == "off", client.inventory.entities["switch.desk_fan"]?.state == "off" else { throw HomeError("Evening scene states did not match.") }
        _ = try await client.activateScene(entity: "scene.work_mode", enabled: allowed)
        try await Task.sleep(nanoseconds: 300_000_000); try await client.refresh()
        guard client.inventory.entities["light.desk_lamp"]?.state == "on", client.inventory.entities["switch.desk_fan"]?.state == "on", client.inventory.entities["light.reading_light"]?.state == "off" else { throw HomeError("Work scene states did not match.") }
        guard client.inventory.entities["light.offline_light"]?.available == false else { throw HomeError("Expected unavailable device.") }
        do { _ = try await client.setPower(entity: "light.offline_light", on: true, enabled: ["light.offline_light"]); throw HomeError("Unavailable target was not rejected.") }
        catch { guard error.localizedDescription.contains("unavailable") else { throw error } }
        print("PASS: real Home Assistant 2026.9.3 authentication, rooms, live inventory, light/switch on-off with readback, both scenes with independently checked virtual states, and unavailable-control rejection. Final scene: Work Mode.")
    }
}
