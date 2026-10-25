import Foundation

public struct LayoutEntry: Codable, Sendable, Equatable {
    public var keyCode: Int
    public var modifiers: Int
    public var text: String
    public var dead: Bool
    public init(keyCode: Int, modifiers: Int, text: String, dead: Bool) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.text = text; self.dead = dead
    }
}
public struct LayoutTable: Codable, Sendable {
    public var id: String
    public var systemID: String
    public var enabled: Bool
    public var keyboardType: Int
    public var entries: [LayoutEntry]
    public init(id: String, systemID: String, enabled: Bool, keyboardType: Int, entries: [LayoutEntry]) {
        self.id = id; self.systemID = systemID; self.enabled = enabled; self.keyboardType = keyboardType; self.entries = entries
    }
}
public protocol KeyLayoutMap: Sendable {
    func character(keyCode: Int, modifiers: Modifiers, source: String) -> String?
}
public struct FixtureLayoutMap: KeyLayoutMap, Sendable {
    public let tables: [LayoutTable]
    private let index: [String: [Int: String]]
    public init(tables: [LayoutTable]) {
        self.tables = tables
        index = Dictionary(tables.map { table in
            (table.id, Dictionary(table.entries.filter { !$0.dead && !$0.text.isEmpty }.map {
                ($0.keyCode * 64 + $0.modifiers, $0.text)
            }, uniquingKeysWith: { first, _ in first }))
        }, uniquingKeysWith: { first, _ in first })
    }
    public init(directory: URL) throws {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let tables = try urls.map { try JSONDecoder().decode(LayoutTable.self, from: Data(contentsOf: $0)) }
        guard !tables.isEmpty else { throw CoreError.missingLayout }
        self.init(tables: tables)
    }
    public func character(keyCode: Int, modifiers: Modifiers, source: String) -> String? {
        let flags = modifiers.intersection([.shift, .option]).rawValue
        guard let value = index[source]?[keyCode * 64 + flags] else { return nil }
        return modifiers.contains(.capsLock) ? value.uppercased() : value
    }
    public func stroke(for character: String, source: String) -> LayoutEntry? {
        tables.first { $0.id == source }?.entries.filter { !$0.dead && $0.text == character }
            .sorted { ($0.modifiers, $0.keyCode) < ($1.modifiers, $1.keyCode) }.first
    }
}
public struct LayoutConverter: Sendable {
    public let map: any KeyLayoutMap
    public init(map: any KeyLayoutMap) { self.map = map }
    public func convert(_ strokes: [Stroke], to source: String) -> String? {
        var result = ""
        for stroke in strokes {
            if stroke.text == " " || stroke.text == "\n" { result += stroke.text; continue }
            guard let key = stroke.keyCode, let text = map.character(keyCode: key, modifiers: stroke.modifiers, source: source), !text.isEmpty else { return nil }
            result += text
        }
        return result
    }
    public func rebase(_ event: KeyEvent, to source: String) -> KeyEvent? {
        guard [.down, .up, .flags].contains(event.kind) else { return event }
        var result = event; result.source = source
        if event.kind == .down && event.key == .character {
            guard let key = event.keyCode, let text = map.character(keyCode: key, modifiers: event.modifiers, source: source) else { return nil }
            result.text = text
        }
        return result
    }
}
