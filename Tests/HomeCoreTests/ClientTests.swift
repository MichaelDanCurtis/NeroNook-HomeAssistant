import XCTest
@testable import HomeCore

private final class Fixture {
    let process = Process()
    let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let endpoint: Endpoint
    init(_ mode: String = "normal") throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [root.appendingPathComponent("scripts/fixture-server.py").path, mode, log.path]
        let output = Pipe(); process.standardOutput = output; process.standardError = Pipe(); try process.run()
        var bytes = Data()
        while let data = try output.fileHandleForReading.read(upToCount: 1), !data.isEmpty { if data[0] == 10 { break }; bytes.append(data) }
        let port = String(data: bytes, encoding: .utf8) ?? ""
        endpoint = try Endpoint("http://127.0.0.1:\(port)")
    }
    var requests: [String] { ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }
    deinit { if process.isRunning { process.terminate(); process.waitUntilExit() }; try? FileManager.default.removeItem(at: log) }
}
final class ClientTests: XCTestCase {
    @MainActor private func wait(_ condition: () -> Bool, seconds: TimeInterval = 5) async throws {
        let end = Date().addingTimeInterval(seconds)
        while !condition(), Date() < end { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(condition(), "Condition did not arrive before deadline")
    }
    @MainActor func testLiveSubscriptionReadbackAndSceneAcceptance() async throws {
        let fixture = try Fixture(); let client = HomeClient(); defer { client.stop() }
        client.connect(fixture.endpoint, token: "fixture-only"); try await wait { client.connected }
        XCTAssertEqual(client.inventory.entities["light.desk"]?.state, "on")
        XCTAssertEqual(client.rooms.room("light.desk"), "Office")
        let result = try await client.setPower(entity: "light.desk", on: false, enabled: ["light.desk"])
        XCTAssertTrue(result.contains("confirmed")); XCTAssertEqual(client.inventory.entities["light.desk"]?.state, "off")
        let scene = try await client.activateScene(entity: "scene.evening", enabled: ["scene.evening"])
        XCTAssertTrue(scene.contains("not verified")); XCTAssertEqual(fixture.requests.filter { $0 == "call_service" }.count, 2)
    }
    @MainActor func testUnknownWriteOutcomeIsNotReplayedOnReconnect() async throws {
        let fixture = try Fixture("disconnect_after_write"); let client = HomeClient(); defer { client.stop() }
        client.connect(fixture.endpoint, token: "fixture-only"); try await wait { client.connected }
        do { _ = try await client.setPower(entity: "light.desk", on: false, enabled: ["light.desk"]); XCTFail("Expected unknown outcome") } catch {}
        XCTAssertFalse(client.connected); XCTAssertTrue(client.inventory.entities.isEmpty)
        client.connect(fixture.endpoint, token: "fixture-only"); try await wait { client.connected }
        XCTAssertEqual(fixture.requests.filter { $0 == "call_service" }.count, 1)
        XCTAssertEqual(fixture.requests.filter { $0 == "subscribe_events" }.count, 2)
    }
    @MainActor func testAcknowledgmentDoesNotClaimStateChange() async throws {
        let fixture = try Fixture("unchanged"); let client = HomeClient(); defer { client.stop() }
        client.connect(fixture.endpoint, token: "fixture-only"); try await wait { client.connected }
        do { _ = try await client.setPower(entity: "light.desk", on: false, enabled: ["light.desk"]); XCTFail("An acknowledgment is not state readback") }
        catch { XCTAssertTrue(error.localizedDescription.contains("not confirmed")) }
        XCTAssertEqual(fixture.requests.filter { $0 == "call_service" }.count, 1)
    }
    @MainActor func testAuthorizationFailureClearsDataAndRoomDenialStillShowsInventory() async throws {
        let denied = try Fixture("auth_rejected"); let client = HomeClient(); defer { client.stop() }
        client.connect(denied.endpoint, token: "fixture-only"); try await wait { client.authorizationFailed }
        XCTAssertFalse(client.connected); XCTAssertTrue(client.inventory.entities.isEmpty); XCTAssertFalse(denied.requests.contains("get_states"))
        let limited = try Fixture("rooms_denied"); client.connect(limited.endpoint, token: "fixture-only"); try await wait { client.connected }
        XCTAssertFalse(client.inventory.entities.isEmpty); XCTAssertFalse(client.registryNotice.isEmpty); XCTAssertEqual(client.rooms.room("light.desk"), "Unassigned")
    }
    @MainActor func testRedirectDoesNotAuthenticate() async throws {
        let fixture = try Fixture("redirect"); let client = HomeClient(); defer { client.stop() }
        client.connect(fixture.endpoint, token: "fixture-only")
        try await wait { client.status.contains("lost") }
        XCTAssertFalse(client.authenticated); XCTAssertTrue(fixture.requests.isEmpty)
    }
}
