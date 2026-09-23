import Foundation

/// Transport stays inside the independent plugin, with one exact server origin.
@MainActor public final class HomeClient {
    public private(set) var inventory = Inventory()
    public private(set) var rooms = Rooms()
    public private(set) var services = Set<String>()
    public private(set) var connected = false
    public private(set) var authenticated = false
    public private(set) var authorizationFailed = false
    public private(set) var homeName = "Home Assistant"
    public private(set) var status = "Add your Home Assistant server in Settings"
    public private(set) var registryNotice = ""
    public private(set) var lastResponse: Date?
    public var onChange: (() -> Void)?
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private let delegate = NoRedirects()
    private var generation = UUID()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<Any, Error>] = [:]
    private var deadlines: [Int: Task<Void, Never>] = [:]
    private var reader: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var token = ""
    private var initializing = false
    private var stateSubscription: Int?
    public init() {}

    public func connect(_ endpoint: Endpoint, token: String) {
        disconnect(); self.token = token; authorizationFailed = false; status = "Connecting to your home…"; initializing = true
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 86400
        config.httpShouldSetCookies = false; config.urlCache = nil; config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.session = session
        let socket = session.webSocketTask(with: endpoint.websocket); socket.maximumMessageSize = 16 * 1024 * 1024
        self.socket = socket; let current = generation; socket.resume(); onChange?()
        reader = Task { [weak self] in
            guard let self else { return }
            do {
                while !Task.isCancelled, self.generation == current {
                    let frame = try await socket.receive()
                    guard self.generation == current else { return }
                    let data: Data
                    switch frame { case .string(let s): data = Data(s.utf8); case .data(let d): data = d; @unknown default: throw HomeError("Unsupported server message.") }
                    guard let message = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw HomeError("Invalid server response.") }
                    self.lastResponse = Date(); try self.receive(message, generation: current)
                }
            } catch { if self.generation == current { self.fail("Connection lost. Controls are paused; no commands will be replayed.") } }
        }
        watchdog = Task { [weak self] in
            let until = Date().addingTimeInterval(60)
            while !Task.isCancelled, let owner = self, owner.generation == current, !owner.connected, Date() < until {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard let self, !Task.isCancelled, self.generation == current else { return }
            if !self.connected { self.fail("Home did not finish connecting. Check the server and token in Settings."); return }
            while !Task.isCancelled, self.generation == current {
                do { _ = try await self.request("ping") } catch { if self.generation == current { self.fail("Home stopped responding. Controls are paused.") }; return }
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }
    public func disconnect() {
        generation = UUID(); connected = false; authenticated = false; initializing = false; token = ""; stateSubscription = nil
        reader?.cancel(); reader = nil; watchdog?.cancel(); watchdog = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil; session?.invalidateAndCancel(); session = nil
        let waiting = pending; pending = [:]; for task in deadlines.values { task.cancel() }; deadlines = [:]
        for continuation in waiting.values { continuation.resume(throwing: HomeError("Connection ended. Command outcome may be unknown; it was not retried.")) }
        inventory = Inventory(); services = []; rooms = Rooms(); registryNotice = ""; lastResponse = nil
    }
    public func stop() { disconnect(); status = "Disconnected · open Settings to reconnect"; onChange?() }
    private func fail(_ message: String) { disconnect(); status = message; onChange?() }
    private func receive(_ m: [String: Any], generation current: UUID) throws {
        switch m["type"] as? String {
        case "auth_required":
            guard !authenticated, initializing, !token.isEmpty else { throw HomeError("Unexpected authentication request.") }
            let credential = token; token = ""
            Task { do { guard generation == current else { return }; try await transmit(["type": "auth", "access_token": credential]) } catch { if generation == current { fail("Could not authenticate with the selected server.") } } }
        case "auth_invalid":
            authorizationFailed = true; fail("Authorization rejected. Replace the token in Settings.")
        case "auth_ok":
            guard !authenticated, initializing else { throw HomeError("Unexpected authentication response.") }
            authenticated = true; status = "Reading rooms and devices…"; onChange?()
            Task { do { try await initialize(current) } catch { if generation == current { fail("Could not read your home. Check the account’s access and reconnect.") } } }
        case "result", "pong":
            guard let id = m["id"] as? Int, let continuation = pending.removeValue(forKey: id) else { return }
            deadlines.removeValue(forKey: id)?.cancel()
            if m["type"] as? String == "pong" || m["success"] as? Bool == true { continuation.resume(returning: m["result"] ?? NSNull()) }
            else { continuation.resume(throwing: HomeError("Home Assistant declined the request. Check permissions and device availability.")) }
        case "event":
            guard m["id"] as? Int == stateSubscription, let event = m["event"] as? [String: Any], event["event_type"] as? String == "state_changed", let data = event["data"] as? [String: Any], let id = data["entity_id"] as? String else { return }
            let entity: Entity?
            if data["new_state"] is NSNull { entity = nil }
            else { guard let raw = data["new_state"] as? [String: Any], let value = Entity(raw) else { throw HomeError("Invalid device state.") }; entity = value }
            try inventory.apply(id: id, entity: entity); onChange?()
        default: break
        }
    }
    private func initialize(_ current: UUID) async throws {
        inventory.begin()
        stateSubscription = nextID + 1
        _ = try await request("subscribe_events", fields: ["event_type": "state_changed"])
        let states = try await request("get_states")
        guard generation == current else { return }; try inventory.complete(states)
        let serviceData = try await request("get_services")
        guard generation == current, let domains = serviceData as? [String: [String: Any]] else { throw HomeError("Invalid service inventory.") }
        services = Set(domains.flatMap { domain, values in values.keys.map { "\(domain).\($0)" } })
        if let config = try? await request("get_config") as? [String: Any], generation == current { homeName = String((config["location_name"] as? String ?? "Home Assistant").prefix(100)) }
        // Registries are optional for restricted users; raw entity state still works.
        do {
            let a = try await request("config/area_registry/list") as? [[String: Any]] ?? []
            let d = try await request("config/device_registry/list") as? [[String: Any]] ?? []
            let e = try await request("config/entity_registry/list") as? [[String: Any]] ?? []
            guard generation == current else { return }; rooms = Rooms(areas: a, devices: d, entities: e)
        } catch { guard generation == current else { return }; registryNotice = "Room information is unavailable to this account. Devices are shown as Unassigned." }
        guard generation == current else { return }
        connected = true; initializing = false; status = "Live · \(inventory.entities.count) entities"; onChange?()
    }
    public func refresh() async throws {
        guard connected else { throw HomeError("Home is disconnected.") }
        let current = generation; inventory.begin()
        do { let data = try await request("get_states"); guard generation == current else { throw HomeError("Connection changed.") }; try inventory.complete(data); onChange?() }
        catch { if generation == current { fail("Could not refresh home state. Reconnect before using controls.") }; throw error }
    }
    public func setPower(entity id: String, on: Bool, enabled: Set<String>) async throws -> String {
        guard let entity = inventory.entities[id] else { throw HomeError("Device no longer exists.") }
        let service = on ? "turn_on" : "turn_off"
        _ = try Control.validate(entity: entity, enabled: enabled, domain: entity.domain, service: service, services: services, connected: connected)
        guard ["light", "switch"].contains(entity.domain) else { throw HomeError("Power controls support lights and switches only.") }
        let current = generation
        _ = try await request("call_service", fields: ["domain": entity.domain, "service": service, "target": ["entity_id": id], "service_data": [:]])
        for attempt in 0..<5 {
            guard generation == current else { throw HomeError("Connection changed after sending. Outcome unknown; no retry was sent.") }
            if attempt > 0 { try await Task.sleep(nanoseconds: 700_000_000) }
            guard generation == current else { throw HomeError("Connection changed after sending. Outcome unknown; no retry was sent.") }
            try await refresh()
            guard generation == current else { throw HomeError("Connection changed during verification. Outcome unknown; no retry was sent.") }
            if inventory.entities[id]?.state == (on ? "on" : "off") { return "\(entity.name) is \(on ? "on" : "off") · confirmed by Home Assistant." }
        }
        throw HomeError("Home Assistant accepted the command, but the requested state was not confirmed. No retry was sent.")
    }
    public func activateScene(entity id: String, enabled: Set<String>) async throws -> String {
        let entity = try Control.validate(entity: inventory.entities[id], enabled: enabled, domain: "scene", service: "turn_on", services: services, connected: connected)
        _ = try await request("call_service", fields: ["domain": "scene", "service": "turn_on", "target": ["entity_id": id], "service_data": [:]])
        return "Home Assistant accepted \(entity.name). The scene’s individual device outcomes are not verified."
    }
    private func transmit(_ payload: [String: Any]) async throws {
        guard let socket else { throw HomeError("Home is disconnected.") }
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let string = String(data: data, encoding: .utf8) else { throw HomeError("Invalid request.") }
        try await socket.send(.string(string))
    }
    private func request(_ type: String, fields: [String: Any] = [:]) async throws -> Any {
        guard authenticated, pending.count < 32 else { throw HomeError("Connection unavailable or busy.") }
        nextID += 1; let id = nextID; let current = generation
        var payload = fields; payload["id"] = id; payload["type"] = type
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            deadlines[id] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled, let self, self.generation == current else { return }
                self.deadlines[id] = nil
                self.pending.removeValue(forKey: id)?.resume(throwing: HomeError("Server request timed out. A sent command is not retried."))
            }
            Task { do { guard generation == current else { return }; try await transmit(payload) } catch { guard generation == current else { return }; deadlines.removeValue(forKey: id)?.cancel(); pending.removeValue(forKey: id)?.resume(throwing: HomeError("Could not send the request. No retry was sent.")) } }
        }
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
