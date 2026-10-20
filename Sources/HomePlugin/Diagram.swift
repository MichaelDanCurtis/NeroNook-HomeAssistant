import Foundation
import HomeCore
import NookPluginSDK

@MainActor func homeDiagram(_ model: HomeModule, page: String) -> PluginDiagram {
    let roles: [String: PluginDiagramColorRole] = ["#0C141A": .background, "#19252D": .surface, "#153A35": .elevated, "#E9F3F3": .text, "#EDF4F5": .text, "#7CF0D8": .accent, "#7F9B9D": .secondary, "#96ABAE": .secondary, "#95B1B3": .secondary]
    var e: [PluginDiagramElement] = []
    func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: String, _ r: Double = 14) { e.append(.init(.box, x: x, y: y, w: w, h: h, fill: color, radius: r, fillRole: roles[color])) }
    func text(_ value: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ font: Double = 18, _ color: String = "#E9F3F3") { e.append(.init(.text, x: x, y: y, w: w, h: h, fill: color, text: String(value.prefix(180)), font: font, fillRole: roles[color])) }
    box(0, 0, 960, 540, "#0C141A", 0)
    box(30, 27, 5, 36, "#51DAC5", 2)
    text(String(model.client.homeName.prefix(45)), 50, 24, 710, 40, 28)
    text(page.uppercased(), 34, 86, 600, 24, 13, "#7F9B9D")
    box(801, 30, 125, 29, model.client.connected ? "#173B36" : "#34312B", 14)
    text(model.client.connected ? "LIVE HOME" : "OFFLINE", 808, 31, 111, 24, 12, model.client.connected ? "#66E5CB" : "#CEB88F")
    var items: [(String, String, String, Bool)] = []
    if page == "Rooms" {
        for room in model.roomNames {
            let entities = model.entities.filter { model.client.rooms.room($0.id) == room && $0.domain != "scene" }
            let on = entities.filter { ["light", "switch"].contains($0.domain) && $0.state == "on" }.count
            items.append((room, "\(entities.count) entities", "\(on) lights / switches on", on > 0))
        }
    } else {
        let selected = model.entities.filter { page == "Scenes" ? $0.domain == "scene" : model.preferences.favorites.contains($0.id) }
        for entity in selected { items.append((entity.name, page == "Scenes" ? "Scene" : entity.display.capitalized, model.client.rooms.room(entity.id), entity.state == "on")) }
    }
    if items.isEmpty {
        // Original, passive house illustration; no external image dependency.
        box(414, 210, 132, 106, "#173331", 8)
        e.append(.init(.line, x: 398, y: 221, w: 82, h: -69, stroke: "#56DCC5", weight: 5))
        e.append(.init(.line, x: 480, y: 152, w: 82, h: 69, stroke: "#56DCC5", weight: 5))
        box(465, 262, 32, 54, "#0C141A", 3)
        box(432, 235, 20, 20, "#56DCC5", 3); box(508, 235, 20, 20, "#56DCC5", 3)
        text(model.client.connected ? page == "Favorites" ? "Your everyday favorites" : "Nothing here yet" : "Your home, close at hand", 230, 349, 510, 43, 29)
        text(model.client.connected ? "Open home to browse rooms and star devices." : "Add your Home Assistant server in Settings.", 230, 400, 530, 40, 17, "#96ABAE")
    } else {
        for (i, item) in items.prefix(6).enumerated() {
            let x = 32.0 + Double(i % 3) * 304, y = 123.0 + Double(i / 3) * 168
            box(x, y, 286, 150, item.3 ? "#153A35" : "#19252D", 16)
            e.append(.init(.ellipse, x: x + 19, y: y + 18, w: 8, h: 8, fill: item.3 ? "#60E0C6" : "#759399"))
            text(String(item.0.prefix(27)), x + 18, y + 36, 250, 36, 20)
            text(String(item.1.prefix(25)), x + 18, y + 76, 250, 36, 25, item.3 ? "#7CF0D8" : "#EDF4F5")
            text(String(item.2.prefix(40)), x + 18, y + 121, 250, 19, 13, "#95B1B3")
        }
        text(items.count > 6 ? "+\(items.count - 6) more · Open home to browse and control" : "Open home to browse and control", 33, 488, 870, 27, 15, "#7F9B9D")
    }
    return .init(id: page.lowercased(), title: page, width: 960, height: 540, summary: items.isEmpty ? "\(page). No devices to display. \(model.status)" : String(items.map { "\($0.0): \($0.1)" }.joined(separator: "; ").prefix(3900)), elements: e)
}
