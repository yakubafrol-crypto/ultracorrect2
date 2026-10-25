import Foundation

public enum FieldKind: String, Codable, Sendable { case plain, autoPairs, enterCompletion, inlineCompletion, slowBackspace, substitutions }
public struct FieldWitness: Sendable {
    public var available: Bool
    public var latencyMs: Double
    public var beforeCursor: String
    public var selectionLength: Int
    public init(available: Bool, latencyMs: Double = 0, beforeCursor: String = "", selectionLength: Int = 0) {
        self.available = available; self.latencyMs = latencyMs; self.beforeCursor = beforeCursor; self.selectionLength = selectionLength
    }
    public func permits(expected: String, inlineCompletion: Bool) -> Bool {
        if !available || latencyMs > 20 { return !inlineCompletion }
        return selectionLength == 0 && beforeCursor.hasSuffix(expected)
    }
}
public struct VirtualField: Sendable {
    public var kind: FieldKind
    public var source: String
    public var witnessAvailable: Bool
    public var witnessLatencyMs: Double = 0
    public var completion: String
    public private(set) var cursor: Int
    public private(set) var selectionLength: Int
    public private(set) var characters: [Character]
    public private(set) var deliveredIDs: [Int] = []
    public private(set) var syntheticModifiers: [Modifiers] = []
    public private(set) var submitCount = 0
    public private(set) var lostBackspaces = 0
    private var lastSyntheticDelete: Double = -.infinity
    private var history: [([Character], Int)] = []
    public init(kind: FieldKind = .plain, text: String = "", cursor: Int? = nil, selectionLength: Int = 0,
                source: String = "ru", witnessAvailable: Bool = true, completion: String = "completion") {
        self.kind = kind; characters = Array(text); self.cursor = min(max(0, cursor ?? text.count), text.count)
        self.selectionLength = min(max(0, selectionLength), text.count-self.cursor)
        self.source = source; self.witnessAvailable = witnessAvailable; self.completion = completion
    }
    public var text: String { String(characters) }
    public var witness: FieldWitness {
        FieldWitness(available: witnessAvailable, latencyMs: witnessLatencyMs,
                     beforeCursor: String(characters.prefix(cursor)), selectionLength: selectionLength)
    }
    public mutating func select(cursor: Int, length: Int = 0) {
        self.cursor = min(max(0, cursor), characters.count); selectionLength = min(max(0, length), characters.count-self.cursor)
    }
    public mutating func account(_ event: KeyEvent) { deliveredIDs.append(event.id) }
    private mutating func insert(_ text: String) {
        let prefix = String(characters.prefix(cursor)) + text
        let suffix = String(characters.dropFirst(cursor+selectionLength))
        characters = Array(prefix+suffix); cursor = prefix.count; selectionLength = 0
    }
    private mutating func erase(backward: Bool) {
        if selectionLength > 0 { characters.removeSubrange(cursor..<(cursor+selectionLength)); selectionLength = 0 }
        else if backward && cursor > 0 { cursor -= 1; characters.remove(at: cursor) }
        else if !backward && cursor < characters.count { characters.remove(at: cursor) }
    }
    public mutating func receive(_ event: KeyEvent, account: Bool = true) {
        if account { self.account(event) }
        if event.kind == .mouse, let position = event.caretPosition { select(cursor:position) }
        if event.kind == .sourceChanged { source = event.source }
        if event.kind != .down { return }
        if event.modifiers.contains(.command) && event.text.lowercased() == "z" {
            if let previous = history.popLast() { characters = previous.0; cursor = previous.1; selectionLength = 0 }
            return
        }
        if event.modifiers.contains(.command) && event.text.lowercased() == "a" { select(cursor: 0, length: characters.count); return }
        if !event.modifiers.intersection([.command, .control, .function]).isEmpty { return }
        history.append((characters,cursor))
        switch event.key {
        case .backspace:
            if event.modifiers.contains(.option) {
                while cursor > 0 && characters[cursor-1].isWhitespace { erase(backward: true) }
                while cursor > 0 && !characters[cursor-1].isWhitespace { erase(backward: true) }
            } else if kind == .autoPairs, cursor > 0, cursor < characters.count,
                      AutoPair.closing(for: String(characters[cursor-1]), previous: nil, round: false) == String(characters[cursor]) {
                erase(backward: true); erase(backward: false)
            } else { erase(backward: true) }
        case .forwardDelete: erase(backward: false)
        case .left: cursor = max(0, cursor-1); selectionLength = 0
        case .right: cursor = min(characters.count, cursor+1); selectionLength = 0
        case .home: cursor = 0; selectionLength = 0
        case .end: cursor = characters.count; selectionLength = 0
        case .enter:
            if kind == .enterCompletion { insert(completion) }
            else { insert("\n"); submitCount += 1 }
        case .tab: break
        case .character, .space:
            var value = event.characters
            if kind == .autoPairs {
                if cursor < characters.count && value == String(characters[cursor]) && "]}\"".contains(value) { cursor += 1; break }
                if let closing = AutoPair.closing(for: value, previous: cursor > 0 ? characters[cursor-1] : nil, round: false) {
                    insert(value+closing); cursor -= 1; break
                }
            }
            if kind == .substitutions {
                if cursor == 0 || (cursor >= 2 && String(characters[(cursor-2)..<cursor]) == ". ") { value = value.uppercased() }
                if value == " " && cursor > 0 && characters[cursor-1] == " " {
                    erase(backward: true); value = ". "
                }
            }
            insert(value)
            if kind == .inlineCompletion && event.key == .character && !value.isEmpty {
                let position = cursor; insert(completion); cursor = position; selectionLength = completion.count
            }
        default: break
        }
    }
    public mutating func inject(_ operation: InjectionOperation, at time: Double) {
        syntheticModifiers.append(operation.modifiers)
        switch operation {
        case .backspace:
            if kind == .slowBackspace && time-lastSyntheticDelete < 2 { lostBackspaces += 1 }
            else { erase(backward: true) }
            lastSyntheticDelete = time
        case .forwardDelete: erase(backward: false)
        case .text(let value): insert(value)
        case .textUp: break
        case .left: cursor = max(0,cursor-1)
        case .right: cursor = min(characters.count,cursor+1)
        case .trailing(let event): receive(event, account: false)
        }
    }
}
