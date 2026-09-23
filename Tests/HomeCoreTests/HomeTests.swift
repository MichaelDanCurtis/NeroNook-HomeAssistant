import XCTest
@testable import HomeCore

final class HomeTests: XCTestCase {
    func testExactOriginAndLocalHTTPPolicy() throws {
        XCTAssertEqual(try Endpoint(" HTTP://homeassistant.local:8123/ ").id, "http://homeassistant.local:8123")
        XCTAssertEqual(try Endpoint("https://home.example:443").websocket.absoluteString, "wss://home.example/api/websocket")
        for address in ["http://example.com", "https://name:token@host.local", "https://host/path", "https://host?token=secret", "https://host#fragment", "ftp://host", "http://192.168.1.300", "https://host:99999"] { XCTAssertThrowsError(try Endpoint(address), address) }
        XCTAssertNoThrow(try Endpoint("http://192.168.1.40:8123"))
    }
    func testNewerEventsAndRemovalWinOverInitialInventory() throws {
        var inventory = Inventory(); inventory.begin()
        let raw: [String: Any] = ["entity_id": "light.desk", "state": "off"]
        let newer = Entity(["entity_id": "light.desk", "state": "on"])!
        try inventory.apply(id: newer.id, entity: newer)
        try inventory.apply(id: "sensor.removed", entity: nil)
        try inventory.complete([raw, ["entity_id": "sensor.removed", "state": "20"]])
        XCTAssertEqual(inventory.entities["light.desk"]?.state, "on"); XCTAssertNil(inventory.entities["sensor.removed"])
        XCTAssertThrowsError(try inventory.apply(id: "light.other", entity: newer))
    }
    func testRoomOverrideAndDeviceFallback() {
        let rooms = Rooms(areas: [["area_id": "k", "name": "Kitchen"], ["area_id": "b", "name": "Bedroom"]], devices: [["id": "device", "area_id": "k"]], entities: [["entity_id": "light.one", "device_id": "device"], ["entity_id": "light.two", "device_id": "device", "area_id": "b"]])
        XCTAssertEqual(rooms.room("light.one"), "Kitchen"); XCTAssertEqual(rooms.room("light.two"), "Bedroom"); XCTAssertEqual(rooms.room("sensor.none"), "Unassigned")
    }
    func testControlsRequireExactEnabledAvailableTargetAndSupportedService() throws {
        let light = Entity(["entity_id": "light.desk", "state": "off"])!
        let enabled: Set<String> = [light.id]
        let services: Set<String> = ["light.turn_on"]
        XCTAssertNoThrow(try Control.validate(entity: light, enabled: enabled, domain: "light", service: "turn_on", services: services, connected: true))
        XCTAssertThrowsError(try Control.validate(entity: light, enabled: [], domain: "light", service: "turn_on", services: services, connected: true))
        XCTAssertThrowsError(try Control.validate(entity: light, enabled: enabled, domain: "light", service: "turn_on", services: services, connected: false))
        XCTAssertThrowsError(try Control.validate(entity: light, enabled: enabled, domain: "light", service: "turn_off", services: services, connected: true))
        let lock = Entity(["entity_id": "lock.front", "state": "locked"])!
        XCTAssertThrowsError(try Control.validate(entity: lock, enabled: [lock.id], domain: "lock", service: "unlock", services: ["lock.unlock"], connected: true))
        let unavailable = Entity(["entity_id": "light.desk", "state": "unavailable"])!
        XCTAssertThrowsError(try Control.validate(entity: unavailable, enabled: enabled, domain: "light", service: "turn_on", services: services, connected: true))
        // An unactivated scene has state "unknown" and is still callable in HA.
        let scene = Entity(["entity_id": "scene.evening", "state": "unknown"])!
        XCTAssertNoThrow(try Control.validate(entity: scene, enabled: [scene.id], domain: "scene", service: "turn_on", services: ["scene.turn_on"], connected: true))
    }
}
