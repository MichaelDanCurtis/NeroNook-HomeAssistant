import SwiftUI
import HomeCore

private let homeAccent = Color(red: 0.32, green: 0.85, blue: 0.77)
private let homeBackground = Color(red: 0.045, green: 0.072, blue: 0.09)

struct HomeView: View {
    @ObservedObject var model: HomeModule
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "house.fill").font(.system(size: 24)).foregroundStyle(homeAccent).padding(13).background(homeAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.client.homeName).font(.system(size: 25, weight: .semibold))
                    HStack(spacing: 6) { Circle().fill(model.client.connected ? homeAccent : .orange).frame(width: 6, height: 6); Text(model.client.connected ? "Live home state" : "Home offline").font(.callout).foregroundStyle(.secondary) }
                }
                Spacer()
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh home state").disabled(model.busy || model.preferences.server.isEmpty)
                Button { model.settingsVisible = true } label: { Label("Settings", systemImage: "gearshape") }
            }.padding(24)
            HStack {
                Picker("View", selection: $model.tab) { ForEach(["Favorites", "Rooms", "Scenes"], id: \.self) { Text($0) } }.pickerStyle(.segmented).frame(width: 310)
                if model.tab == "Rooms" { Picker("Room", selection: $model.room) { Text("All rooms").tag("All rooms"); ForEach(model.roomNames, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(maxWidth: 210) }
                Spacer()
                TextField("Find a device or scene", text: $model.query).textFieldStyle(.roundedBorder).frame(width: 220)
            }.padding(.horizontal, 24).padding(.bottom, 18)
            if model.displayed.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: model.tab == "Favorites" ? "star" : "house").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(homeAccent)
                    Text(emptyTitle).font(.title2.weight(.medium))
                    Text(emptyDetail).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
                    if !model.client.connected { Button("Open Settings") { model.settingsVisible = true }.buttonStyle(.borderedProminent).tint(homeAccent).foregroundStyle(.black) }
                    else if model.tab == "Favorites" { Button("Browse rooms") { model.tab = "Rooms" } }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 245, maximum: 400), spacing: 14)], spacing: 14) {
                        ForEach(model.displayed) { entity in EntityCard(model: model, entity: entity) }
                    }.padding(.horizontal, 24).padding(.bottom, 20)
                }
            }
            HStack(spacing: 10) {
                Image(systemName: model.notice.isEmpty ? "dot.radiowaves.left.and.right" : "info.circle").foregroundStyle(homeAccent)
                Text(model.notice.isEmpty ? model.status : model.notice).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Text("\(model.entities.count) entities").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.vertical, 14).background(.white.opacity(0.025))
        }
        .background(homeBackground).preferredColorScheme(.dark).tint(homeAccent)
        .sheet(isPresented: $model.settingsVisible) { HomeSettings(model: model) }
        .alert(item: $model.proposed) { proposal in Alert(title: Text(proposal.title), message: Text(proposal.detail), primaryButton: .default(Text("Send command")) { model.confirm(proposal) }, secondaryButton: .cancel()) }
    }
    var emptyTitle: String { !model.client.connected ? "Bring your home into the Nook" : !model.query.isEmpty ? "No matching devices" : model.tab == "Favorites" ? "Your everyday favorites" : model.tab == "Scenes" ? "No scenes found" : "No devices in this room" }
    var emptyDetail: String { !model.client.connected ? "Connect Home Assistant in Settings. Your rooms, devices and scenes will appear here." : model.tab == "Favorites" ? "Browse Rooms and star the devices you want close at hand. Favorites also appear in your Nook." : "Try another room or search. Scenes are defined in Home Assistant." }
}

struct EntityCard: View {
    @ObservedObject var model: HomeModule
    let entity: Entity
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: entity.symbol).font(.system(size: 23)).foregroundStyle(entity.available ? homeAccent : .secondary).frame(width: 35, height: 35)
                Spacer()
                Button { model.toggleFavorite(entity.id) } label: { Image(systemName: model.preferences.favorites.contains(entity.id) ? "star.fill" : "star").foregroundStyle(model.preferences.favorites.contains(entity.id) ? .yellow : .secondary) }.buttonStyle(.plain).help("Favorite \(entity.name)")
            }
            Text(entity.name).font(.system(size: 16, weight: .semibold)).lineLimit(2).frame(height: 38, alignment: .topLeading)
            Text(model.client.rooms.room(entity.id)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(alignment: .firstTextBaseline) {
                Text(entity.domain == "scene" ? "Scene" : entity.display.capitalized).font(.system(size: 24, weight: .medium, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                Spacer()
                if entity.domain == "scene" { Button("Activate") { model.propose(entity) }.disabled(!model.canControl(entity)) }
                else if ["light", "switch"].contains(entity.domain) {
                    Button(entity.state == "on" ? "Turn off" : "Turn on") { model.propose(entity, on: entity.state != "on") }.disabled(!model.canControl(entity))
                }
            }
            Text(entity.supportsControl && !model.preferences.controls.contains(entity.id) ? "Read only · enable control in Settings" : entity.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(entity.id)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(entity.state == "on" ? homeAccent.opacity(0.10) : .white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.07)))
    }
}

struct HomeSettings: View {
    @ObservedObject var model: HomeModule
    @State private var filter = ""
    @State private var forgetReview = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Home Assistant settings").font(.title2.weight(.semibold)); Spacer(); Button("Done") { model.settingsVisible = false }.keyboardShortcut(.defaultAction) }
            VStack(alignment: .leading, spacing: 12) {
                Text("Your server").font(.headline)
                TextField("http://homeassistant.local:8123", text: $model.draftServer).textFieldStyle(.roundedBorder).accessibilityLabel("Home Assistant address")
                SecureField("Access token — leave blank to use the saved token", text: $model.draftToken).textFieldStyle(.roundedBorder).accessibilityLabel("Home Assistant access token")
                Text("Create a long-lived access token in Home Assistant’s profile → Security. It stays in this plugin’s Keychain. Local HTTP sends it unencrypted on your network; use HTTPS where available.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Connect") { model.connectFromSettings() }.buttonStyle(.borderedProminent).disabled(model.busy)
                    if !model.preferences.server.isEmpty { Button("Disconnect") { model.disconnect() }.disabled(model.busy); Button("Forget…", role: .destructive) { forgetReview = true }.disabled(model.busy) }
                    Spacer()
                    Link("Token help", destination: URL(string: "https://www.home-assistant.io/docs/authentication/#your-account-profile")!)
                }
                Text(model.client.connected ? "Connected · \(model.client.homeName)" : model.client.status).font(.callout).foregroundStyle(model.client.connected ? homeAccent : .secondary).fixedSize(horizontal: false, vertical: true)
                if !model.notice.isEmpty { Text(model.notice).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                if !model.client.registryNotice.isEmpty { Text(model.client.registryNotice).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            }.padding(16).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            HStack { VStack(alignment: .leading, spacing: 4) { Text("Allowed controls").font(.headline); Text("Choose individual lights, switches and scenes. Everything else stays read only.").font(.caption).foregroundStyle(.secondary) }; Spacer() }
            TextField("Find a light, switch or scene", text: $filter).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.entities.filter { $0.supportsControl && (filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) || $0.id.localizedCaseInsensitiveContains(filter)) }) { entity in
                        Toggle(isOn: Binding(get: { model.preferences.controls.contains(entity.id) }, set: { model.setAllowed(entity, $0) })) {
                            HStack { Image(systemName: entity.symbol).foregroundStyle(homeAccent).frame(width: 25); VStack(alignment: .leading) { Text(entity.name); Text(entity.id).font(.caption).foregroundStyle(.secondary) } }
                        }.toggleStyle(.switch).padding(.vertical, 9)
                        Divider().opacity(0.25)
                    }
                    if model.entities.isEmpty { Text("Connect your home to choose devices.").foregroundStyle(.secondary).padding(20) }
                }
            }.frame(minHeight: 90)
        }.padding(24).frame(width: 690, height: 660).background(homeBackground).preferredColorScheme(.dark).tint(homeAccent)
        .confirmationDialog("Remove this plugin’s saved connection and token?", isPresented: $forgetReview) { Button("Forget connection", role: .destructive) { model.forget() } } message: { Text("Home Assistant itself and your other apps will be unchanged.") }
    }
}
