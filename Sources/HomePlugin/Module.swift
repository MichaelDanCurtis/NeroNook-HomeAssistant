import AppKit
import SwiftUI
import HomeCore
import NookPluginSDK
import CryptoKit

let moduleID = "cafe.nero.plugin.homeassistant"
struct Preferences: Codable {
    var server = ""
    var favorites = Set<String>()
    var controls = Set<String>()
}
struct ProposedControl: Identifiable {
    let id = UUID()
    let entity: Entity
    let on: Bool?
    let server: String
    var title: String { on.map { "Turn \(entity.name) \($0 ? "on" : "off")?" } ?? "Activate \(entity.name)?" }
    var detail: String { on == nil ? "This runs the scene as configured in Home Assistant. It may affect multiple devices and cannot be automatically undone." : "Send this one command to \(entity.id). Its resulting state will be checked in Home Assistant." }
}

@MainActor final class HomeModule: NSObject, NSApplicationDelegate, ObservableObject {
    let client = HomeClient()
    @Published var preferences = Preferences()
    @Published var draftServer = ""
    @Published var draftToken = ""
    @Published var tab = "Favorites"
    @Published var room = "All rooms"
    @Published var query = ""
    @Published var settingsVisible = false
    @Published var notice = ""
    @Published var revision = 0
    @Published var busy = false
    @Published var proposed: ProposedControl?
    private var window: NSWindow?
    private var hostCards = false
    private var inlineControls: [String: ProposedControl] = [:]
    private var session: UUID?
    private var sequence: UInt64 = 0
    private let input = InputReader()
    private var timer: Timer?
    private var publishNeeded = true
    private var lastPublish = Date.distantPast
    private var nextReconnect = Date.distantFuture
    private var retryDelay: TimeInterval = 4
    private var shouldConnect = false
    private var connectionAttempt = UUID()
    private var wasConnected = false
    private var runs = Set<UUID>()
    private let testMode = CommandLine.arguments.contains("--protocol-test")
    private var storage: URL? { try? PluginStorage.directory(id: moduleID).appendingPathComponent("settings.json") }
    private var developmentFixture: Endpoint? {
        #if DEBUG
        guard let address = Bundle.main.object(forInfoDictionaryKey: "NeroHomeFixture") as? String, let endpoint = try? Endpoint(address), endpoint.base.host == "127.0.0.1" else { return nil }
        return endpoint
        #else
        return nil
        #endif
    }
    var entities: [Entity] { client.inventory.entities.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    var displayed: [Entity] {
        entities.filter { entity in
            let content = tab == "Favorites" ? preferences.favorites.contains(entity.id) : tab == "Scenes" ? entity.domain == "scene" : entity.domain != "scene" && (room == "All rooms" || client.rooms.room(entity.id) == room)
            return content && (query.isEmpty || entity.name.localizedCaseInsensitiveContains(query) || entity.id.localizedCaseInsensitiveContains(query))
        }
    }
    var roomNames: [String] { Set(entities.filter { $0.domain != "scene" }.map { client.rooms.room($0.id) }).sorted() }
    var status: String { client.connected ? "\(client.homeName) · \(entities.count) entities · live" : client.status }
    var values: [String: PluginValue] { ["server": .string(preferences.server), "connected": .boolean(client.connected), "message": .string(String(status.prefix(250)))] }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if !testMode, developmentFixture == nil, let storage, let data = try? Data(contentsOf: storage), let value = try? JSONDecoder().decode(Preferences.self, from: data) { preferences = value; draftServer = value.server }
        client.onChange = { [weak self] in
            guard let self else { return }; self.revision += 1; self.publishNeeded = true
            if self.client.connected { if !self.wasConnected { self.notice = "" }; self.wasConnected = true; self.retryDelay = 4; self.nextReconnect = .distantFuture }
            else if self.wasConnected { self.wasConnected = false; self.nextReconnect = Date().addingTimeInterval(self.retryDelay) }
            if self.client.authorizationFailed { self.shouldConnect = false; self.proposed = nil }
        }
        if CommandLine.arguments.contains("--neronook-plugin") { input.start { [weak self] message in Task { @MainActor in guard let message else { NSApp.terminate(nil); return }; self?.receive(message) } } }
        else { showWindow(); if preferences.server.isEmpty { settingsVisible = true } }
        if let fixture = developmentFixture {
            preferences = Preferences(server: fixture.id, favorites: ["light.desk", "switch.fan", "sensor.temperature"], controls: ["light.desk", "scene.evening"])
            settingsVisible = false; client.connect(fixture, token: "fixture-only")
        } else if !testMode, !preferences.server.isEmpty { shouldConnect = true; reconnect() }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in
            guard let self else { return }
            if self.shouldConnect, !self.client.connected, Date() >= self.nextReconnect { self.reconnect() }
            if self.publishNeeded || Date().timeIntervalSince(self.lastPublish) > 5 { self.publish() }
        } }
    }
    func applicationWillTerminate(_ notification: Notification) { client.stop() }
    private func save() throws {
        if developmentFixture != nil { publishNeeded = true; return }
        guard let storage else { throw HomeError("Could not open plugin settings storage.") }
        try JSONEncoder().encode(preferences).write(to: storage, options: .atomic)
        publishNeeded = true
    }
    func connectFromSettings() {
        guard developmentFixture == nil, !testMode, !busy else { return }
        let endpoint: Endpoint
        do { endpoint = try Endpoint(draftServer) } catch { notice = error.localizedDescription; return }
        let freshToken = draftToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard freshToken.count <= 8192, !freshToken.contains("\n") else { notice = "Enter a valid Home Assistant token."; return }
        busy = true; let attempt = UUID(); connectionAttempt = attempt
        shouldConnect = false; client.stop(); notice = "Opening this plugin’s Keychain…"
        Task {
            defer { if connectionAttempt == attempt { busy = false; publishNeeded = true } }
            do {
                // Keychain approval may wait for the user. Keep UI and SDK heartbeat alive.
                let token = try await Task.detached {
                    let value = freshToken.isEmpty ? try CredentialStore.token(for: endpoint.id, allowUI: true) : freshToken
                    guard let value, !value.isEmpty else { throw HomeError("Paste a Home Assistant access token into the secure field.") }
                    if !freshToken.isEmpty { try CredentialStore.save(value, for: endpoint.id) }
                    return value
                }.value
                guard connectionAttempt == attempt else { return }
                let previous = preferences
                if endpoint.id != preferences.server { preferences = Preferences(server: endpoint.id) }
                do { try save() } catch { preferences = previous; throw error }
                draftToken = ""; draftServer = endpoint.id; shouldConnect = true; nextReconnect = Date().addingTimeInterval(75)
                client.connect(endpoint, token: token); notice = "Connecting… Settings can be closed while your home loads."
            } catch { if connectionAttempt == attempt { notice = error.localizedDescription } }
        }
    }
    private func reconnect() {
        guard !testMode, !busy, !preferences.server.isEmpty else { return }
        let endpoint: Endpoint
        do { endpoint = try Endpoint(preferences.server) } catch { shouldConnect = false; notice = "Check the saved server address in Settings."; return }
        busy = true; notice = "Opening saved connection…"; publishNeeded = true; let attempt = UUID(); connectionAttempt = attempt
        nextReconnect = Date().addingTimeInterval(max(75, retryDelay)); retryDelay = min(120, retryDelay * 2)
        Task {
            defer { if connectionAttempt == attempt { busy = false; publishNeeded = true } }
            do {
                let token = try await Task.detached { try CredentialStore.token(for: endpoint.id, allowUI: false) }.value
                guard connectionAttempt == attempt else { return }
                guard let token, !token.isEmpty else { shouldConnect = false; notice = "Add a token in Settings to connect."; return }
                client.connect(endpoint, token: token)
            } catch { if connectionAttempt == attempt { shouldConnect = false; notice = "Saved connection needs attention. Open Settings and choose Connect to unlock it; leave the token field blank." } }
        }
    }
    func disconnect() {
        connectionAttempt = UUID(); busy = false; shouldConnect = false; nextReconnect = .distantFuture; client.stop(); proposed = nil
    }
    func forget() {
        guard developmentFixture == nil, !testMode, !busy else { return }
        let server = preferences.server; disconnect(); busy = true
        let attempt = UUID(); connectionAttempt = attempt
        Task {
            defer { if connectionAttempt == attempt { busy = false } }
            do {
                try await Task.detached { try CredentialStore.remove(server) }.value
                guard connectionAttempt == attempt else { return }
                draftToken = ""; preferences = Preferences(); draftServer = ""; try save(); notice = "Saved connection and token removed from this plugin."
            } catch { if connectionAttempt == attempt { notice = "Could not completely remove saved settings. Check Keychain access and try again." } }
        }
    }
    func toggleFavorite(_ id: String) {
        let before = preferences.favorites
        if !preferences.favorites.insert(id).inserted { preferences.favorites.remove(id) }
        do { try save() } catch { preferences.favorites = before; notice = error.localizedDescription }
    }
    func setAllowed(_ entity: Entity, _ allowed: Bool) {
        guard entity.supportsControl else { return }; let before = preferences.controls
        if allowed { preferences.controls.insert(entity.id) } else { preferences.controls.remove(entity.id) }
        do { try save() } catch { preferences.controls = before; notice = error.localizedDescription }
    }
    func canControl(_ entity: Entity) -> Bool {
        client.connected && !busy && entity.available && entity.supportsControl && preferences.controls.contains(entity.id)
    }
    func propose(_ entity: Entity, on: Bool? = nil) { guard canControl(entity) else { return }; proposed = .init(entity: entity, on: on, server: preferences.server) }
    func confirm(_ proposal: ProposedControl) {
        proposed = nil
        guard proposal.server == preferences.server else { notice = "The selected home changed. Choose the action again."; return }
        perform(entity: proposal.entity.id, on: proposal.on)
    }
    func refresh() {
        guard !busy else { return }
        if !client.connected { shouldConnect = true; reconnect(); return }
        busy = true; Task { defer { busy = false; publishNeeded = true }; do { try await client.refresh(); notice = "Home state refreshed." } catch { notice = error.localizedDescription } }
    }
    private func perform(entity: String, on: Bool?, request: UUID? = nil) {
        guard !busy, client.connected else { finish("Home is unavailable or a command is in progress.", request: request, failed: true); return }
        busy = true
        Task {
            defer { busy = false; publishNeeded = true }
            do {
                let message: String
                if let on { message = try await client.setPower(entity: entity, on: on, enabled: preferences.controls) }
                else { message = try await client.activateScene(entity: entity, enabled: preferences.controls) }
                finish(message, request: request)
            } catch { finish(error.localizedDescription, request: request, failed: true) }
        }
    }
    private func finish(_ message: String, request: UUID?, failed: Bool = false) {
        notice = String(message.prefix(400))
        if let request { send(.init(.update, requestID: request, update: .init(failed ? .failed : .succeeded, message: String(message.prefix(250)), values: failed ? [:] : ["message": .string(String(message.prefix(350)))]))) }
    }
    private func receive(_ m: PluginMessage) {
        guard m.pluginID == moduleID else { NSApp.terminate(nil); return }
        if session == nil {
            guard m.type == "hello" else { NSApp.terminate(nil); return }; session = m.session; PluginAppearanceStore.shared.beginSession(pluginID:moduleID,session:m.session)
            hostCards = m.features?.contains("control-cards-v1") == true
            emit("ready", features: ["appearance-v1", "actions-v1", "dashboard-v1", "panels-v1", "diagrams-v1", "control-cards-v1"])
            let target = [PluginParameter("server", .string), PluginParameter("entity", .string)]
            send(.init(.register, registration: .init(actions: [
                .init("read_status", title: "Read Home Assistant status", output: .init([.init("server", .string), .init("connected", .boolean), .init("message", .string)])),
                .init("set_power", title: "Set home light or switch", input: .init(target + [.init("on", .boolean)]), output: .init([.init("message", .string)]), effect: .externalChange, timeoutSeconds: 45),
                .init("activate_scene", title: "Activate Home Assistant scene", input: .init(target), output: .init([.init("message", .string)]), effect: .externalChange, timeoutSeconds: 30)
            ], channels: [.init("status", title: "Home Assistant status", kind: .state, schema: .init([.init("server", .string), .init("connected", .boolean), .init("message", .string)]))])))
            publish(); return
        }
        guard m.session == session else { NSApp.terminate(nil); return }; if m.type == "appearance" { _ = PluginAppearanceStore.shared.receive(m); return }
        if m.type == "action" { switch m.action { case "configure": showWindow(); settingsVisible = true; case "controls": showWindow(); case "refresh": refresh(); default:
            if let action = m.action, let proposal = inlineControls[action], canControl(proposal.entity), proposal.server == preferences.server,
               client.inventory.entities[proposal.entity.id]?.state == proposal.entity.state {
                inlineControls.removeAll()
                confirm(proposal)
                publish()
            }
        } }
        if m.type == "bus", let bus = m.bus, bus.operation == .execute { execute(bus) }
    }
    private func execute(_ b: PluginBusMessage) {
        guard b.address?.plugin == moduleID, runs.count < 4096, runs.insert(b.requestID).inserted else { finish("Duplicate or invalid action request.", request: b.requestID, failed: true); return }
        if b.address?.name == "read_status" { send(.init(.update, requestID: b.requestID, update: .init(.succeeded, values: values))); return }
        guard case .string(let server)? = b.values?["server"], server == preferences.server, !server.isEmpty, case .string(let entity)? = b.values?["entity"], Entity.validID(entity) else { finish("Choose an enabled entity on the connected server.", request: b.requestID, failed: true); return }
        if b.address?.name == "set_power", case .boolean(let on)? = b.values?["on"] { perform(entity: entity, on: on, request: b.requestID) }
        else if b.address?.name == "activate_scene" { perform(entity: entity, on: nil, request: b.requestID) }
        else { finish("Unsupported home action.", request: b.requestID, failed: true) }
    }
    func publish() {
        guard session != nil else { return }; lastPublish = Date(); publishNeeded = false
        inlineControls.removeAll()
        let panels: [PluginPanel] = ["Favorites", "Rooms", "Scenes"].map { page in
            if !hostCards { return .init(page.lowercased(), page, diagrams: [homeDiagram(self, page: page)]) }
            let selected = entities.filter { page == "Favorites" ? preferences.favorites.contains($0.id) : page == "Scenes" ? $0.domain == "scene" : $0.domain != "scene" }
            return .init(page.lowercased(), page, cards: selected.prefix(64).map { entity in
                let key = SHA256.hash(data: Data((preferences.server + "|" + entity.id).utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
                var actions: [PluginAction] = []
                if entity.supportsControl {
                    let on: Bool? = entity.domain == "scene" ? nil : entity.state != "on"
                    let id = "home_" + key + (on.map { $0 ? "_on" : "_off" } ?? "_scene")
                    let proposal = ProposedControl(entity: entity, on: on, server: preferences.server)
                    inlineControls[id] = proposal
                    actions = [.init(id, on.map { $0 ? "Turn on" : "Turn off" } ?? "Activate", enabled: canControl(entity), symbol: on == nil ? "play.fill" : "power", confirmation: String((proposal.title + " " + proposal.detail).prefix(400)))]
                }
                return PluginControlCard("entity_" + key, title: String(entity.name.prefix(80)), subtitle: String(client.rooms.room(entity.id).prefix(100)), value: String((entity.domain == "scene" ? "Scene" : entity.display.capitalized).prefix(100)), detail: entity.supportsControl && !preferences.controls.contains(entity.id) ? "Read only · enable in Settings" : String(entity.detail.prefix(300)), symbol: entity.symbol, highlighted: entity.state == "on", actions: actions)
            })
        }
        let activity = notice.isEmpty ? status : notice
        var snapshot = PluginSnapshot(title: "Home Assistant", status: String(activity.prefix(250)), activity: String(activity.prefix(100)), fields: [.init("Home", client.homeName), .init("Entities", String(entities.count))], actions: hostCards ? [] : [
            .init("controls", "Open home", symbol: "house", placement: .menu), .init("refresh", "Refresh", enabled: !busy && !preferences.server.isEmpty, symbol: "arrow.clockwise", placement: .menu)
        ], badge: busy ? "Working…" : client.connected ? "Live" : "Offline", panels: panels)
        // Text may contain multi-byte characters; bound the encoded message, not just card counts.
        var trimmed = false
        while ((try? PluginMessage(type: "snapshot", pluginID: moduleID, session: session!, snapshot: snapshot).encoded().count) ?? Int.max) > 120 * 1024 {
            guard let index = snapshot.panels?.indices.max(by: { (snapshot.panels?[$0].cards?.count ?? 0) < (snapshot.panels?[$1].cards?.count ?? 0) }),
                  snapshot.panels?[index].cards?.isEmpty == false else { return }
            snapshot.panels?[index].cards?.removeLast(); trimmed = true
        }
        if hostCards {
            let shown = snapshot.panels?.flatMap { $0.cards ?? [] }.count ?? 0
            let expected = entities.count + entities.filter { preferences.favorites.contains($0.id) }.count
            if trimmed || shown < expected { snapshot.status = "Showing a limited set of items. Use Favorites to keep your everyday devices here." }
            let advertised = Set(snapshot.displayActions.filter(\.enabled).map(\.id))
            inlineControls = inlineControls.filter { advertised.contains($0.key) }
        }
        guard (try? snapshot.validate()) != nil else { return }
        emit("snapshot", snapshot: snapshot); send(.init(.publish, address: .init(moduleID, "status"), values: values, lifetime: 10))
    }
    private func send(_ bus: PluginBusMessage) { emit("bus", bus: bus) }
    private func emit(_ type: String, features: [String]? = nil, snapshot: PluginSnapshot? = nil, bus: PluginBusMessage? = nil) {
        guard let session else { return }; if type != "ready" { sequence += 1 }
        do { try FileHandle.standardOutput.write(contentsOf: PluginMessage(type: type, pluginID: moduleID, session: session, sequence: sequence, snapshot: snapshot, features: features, bus: bus).encoded()) } catch { NSApp.terminate(nil) }
    }
    func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 650), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Home Assistant"; w.contentView = NSHostingView(rootView: HomeView(model: self).pluginThemed()); w.minSize = NSSize(width: 820, height: 570); w.isReleasedWhenClosed = false; w.center(); window = w
        }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}
private final class InputReader: @unchecked Sendable {
    private var lines = PluginLines(); private let queue = DispatchQueue(label: "HomeAssistantPlugin.input")
    func start(_ receive: @escaping @Sendable (PluginMessage?) -> Void) {
        FileHandle.standardInput.readabilityHandler = { [weak self] file in
            let data = file.availableData; guard !data.isEmpty else { receive(nil); return }
            self?.queue.async { [weak self] in guard let self else { return }; do { for message in try self.lines.append(data) { receive(message) } } catch { receive(nil) } }
        }
    }
}
