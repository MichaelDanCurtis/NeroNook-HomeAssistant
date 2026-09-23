import Foundation

public struct HomeError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// A single explicit origin. Credentials never follow a redirect or enter a URL.
public struct Endpoint: Equatable {
    public let base: URL
    public var id: String { base.absoluteString }
    public var encrypted: Bool { base.scheme == "https" }
    public var websocket: URL { var c = URLComponents(url: base, resolvingAgainstBaseURL: false)!; c.scheme = encrypted ? "wss" : "ws"; c.path = "/api/websocket"; return c.url! }
    public init(_ input: String) throws {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var c = URLComponents(string: text), ["http", "https"].contains(c.scheme?.lowercased() ?? ""), let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil, c.path.isEmpty || c.path == "/",
              c.port == nil || (1...65535).contains(c.port!) else { throw HomeError("Enter the server’s http:// or https:// address, without a login, path or query.") }
        c.scheme = c.scheme!.lowercased(); c.host = host.lowercased(); c.path = ""
        if c.scheme == "http", !Self.isLocal(host) { throw HomeError("Use HTTPS for an internet server. HTTP is available only for an explicitly selected local address.") }
        if (c.scheme == "http" && c.port == 80) || (c.scheme == "https" && c.port == 443) { c.port = nil }
        guard let url = c.url else { throw HomeError("Invalid server address.") }; base = url
    }
    public static func isLocal(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h.hasSuffix(".local") || h == "[::1]" || h == "::1" { return true }
        let p = h.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4, p.allSatisfy({ (0...255).contains($0) }), h.split(separator: ".").count == 4 else { return false }
        return p[0] == 10 || p[0] == 127 || (p[0] == 192 && p[1] == 168) || (p[0] == 172 && (16...31).contains(p[1]))
    }
}

public struct Entity: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let state: String
    public let unit: String
    public let deviceClass: String
    public let detail: String
    public let updated: String
    public var domain: String { String(id.split(separator: ".").first ?? "") }
    public var available: Bool { state != "unavailable" && (state != "unknown" || domain == "scene") }
    public var display: String { available ? String((state + (unit.isEmpty ? "" : " " + unit)).prefix(60)) : "Unavailable" }
    public var supportsControl: Bool { ["light", "switch", "scene"].contains(domain) }
    public var symbol: String {
        switch domain {
        case "light": return "lightbulb.fill"
        case "switch": return "powerplug.fill"
        case "scene": return "sparkles"
        case "climate": return "thermometer.medium"
        case "lock": return "lock.fill"
        case "cover": return "window.shade.closed"
        case "binary_sensor": return deviceClass == "motion" ? "figure.walk" : "sensor.fill"
        case "sensor": return deviceClass == "temperature" ? "thermometer.medium" : deviceClass == "humidity" ? "humidity.fill" : "waveform.path"
        default: return "house.fill"
        }
    }
    public init?(_ raw: [String: Any]) {
        guard let id = raw["entity_id"] as? String, Self.validID(id), let state = raw["state"] as? String else { return nil }
        let a = raw["attributes"] as? [String: Any] ?? [:]
        self.id = id; self.state = String(state.prefix(250)); name = String((a["friendly_name"] as? String ?? id).prefix(160))
        unit = String((a["unit_of_measurement"] as? String ?? "").prefix(20)); deviceClass = a["device_class"] as? String ?? ""
        updated = raw["last_updated"] as? String ?? ""
        if id.hasPrefix("climate.") {
            let now = (a["current_temperature"] as? NSNumber)?.stringValue ?? "—"
            let target = (a["temperature"] as? NSNumber)?.stringValue ?? "—"
            detail = "Current \(now) · Target \(target) · \(a["hvac_action"] as? String ?? state)"
        } else if id.hasPrefix("light."), let brightness = a["brightness"] as? Double, state == "on" { detail = "Brightness \(Int((brightness / 255 * 100).rounded()))%" }
        else { detail = String(id.split(separator: ".")[0]).replacingOccurrences(of: "_", with: " ").capitalized }
    }
    public static func validID(_ id: String) -> Bool { id.count <= 180 && id.range(of: "^[a-z_]+\\.[a-z0-9_]+$", options: .regularExpression) != nil }
}

/// Buffer subscribed updates while reading inventory, so newer events win.
public struct Inventory {
    public private(set) var entities: [String: Entity] = [:]
    private var buffering = false
    private var changes: [(String, Entity?)] = []
    public init() {}
    public mutating func begin() { buffering = true; changes = [] }
    public mutating func apply(id: String, entity: Entity?) throws {
        guard Entity.validID(id), entity == nil || entity?.id == id else { throw HomeError("Malformed state update.") }
        if buffering { guard changes.count < 20000 else { throw HomeError("Too many queued state updates; reconnect to refresh.") }; changes.append((id, entity)) }
        else { guard entity == nil || entities[id] != nil || entities.count < 20000 else { throw HomeError("Home inventory exceeded its limit.") }; entities[id] = entity }
    }
    public mutating func complete(_ raw: Any) throws {
        guard let list = raw as? [[String: Any]], list.count <= 20000 else { throw HomeError("Invalid or oversized home inventory.") }
        var fresh: [String: Entity] = [:]
        for value in list { if let e = Entity(value) { fresh[e.id] = e } }
        for (id, e) in changes { fresh[id] = e }
        entities = fresh; changes = []; buffering = false
    }
}

public struct Rooms {
    public var names: [String: String] = [:]
    public var entityRooms: [String: String] = [:]
    public init(areas: [[String: Any]] = [], devices: [[String: Any]] = [], entities: [[String: Any]] = []) {
        var deviceRooms: [String: String] = [:]
        for area in areas { if let id = area["area_id"] as? String, let name = area["name"] as? String { names[id] = String(name.prefix(100)) } }
        for device in devices { if let id = device["id"] as? String, let area = device["area_id"] as? String { deviceRooms[id] = area } }
        for entity in entities { if let id = entity["entity_id"] as? String, let area = entity["area_id"] as? String ?? (entity["device_id"] as? String).flatMap({ deviceRooms[$0] }) { entityRooms[id] = area } }
    }
    public func room(_ id: String) -> String { entityRooms[id].flatMap { names[$0] } ?? "Unassigned" }
}

public enum Control {
    public static func validate(entity: Entity?, enabled: Set<String>, domain: String, service: String, services: Set<String>, connected: Bool) throws -> Entity {
        guard connected, let entity, entity.available else { throw HomeError("The device is unavailable. Reconnect before sending a command.") }
        guard enabled.contains(entity.id), entity.domain == domain,
              (["light", "switch"].contains(domain) && ["turn_on", "turn_off"].contains(service)) || (domain == "scene" && service == "turn_on"),
              services.contains("\(domain).\(service)") else { throw HomeError("This target or command is not enabled. Choose controls in Settings.") }
        return entity
    }
}
