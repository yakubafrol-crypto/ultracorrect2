import Foundation

public struct Modifiers: OptionSet, Codable, Sendable, Hashable {
    public var rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let shift = Self(rawValue: 1)
    public static let option = Self(rawValue: 2)
    public static let command = Self(rawValue: 4)
    public static let control = Self(rawValue: 8)
    public static let function = Self(rawValue: 16)
    public static let capsLock = Self(rawValue: 32)
}
public enum EventKind: String, Codable, Sendable {
    case down, up, flags, mouse, focus, secureInput, sourceChanged, tapDisabled
}
public enum Key: String, Codable, Sendable {
    case character, space, enter, tab, backspace, forwardDelete, left, right, up, down, home, end, pageUp, pageDown, escape, globe, shift
}
public struct KeyEvent: Codable, Sendable, Equatable {
    public var id: Int
    public var time: Double
    public var kind: EventKind
    public var key: Key
    public var text: String
    public var keyCode: Int?
    public var modifiers: Modifiers
    public var source: String
    public var own: Bool
    public var repeatKey: Bool
    public var secure: Bool
    public var deadKey: Bool
    public var caretPosition: Int?
    public init(id: Int = 0, time: Double = 0, kind: EventKind = .down, key: Key = .character, text: String = "",
                keyCode: Int? = nil, modifiers: Modifiers = [], source: String = "ru", own: Bool = false,
                repeatKey: Bool = false, secure: Bool = false, deadKey: Bool = false, caretPosition: Int? = nil) {
        self.id = id; self.time = time; self.kind = kind; self.key = key; self.text = text; self.keyCode = keyCode
        self.modifiers = modifiers; self.source = source; self.own = own; self.repeatKey = repeatKey
        self.secure = secure; self.deadKey = deadKey
        self.caretPosition = caretPosition
    }
    public var characters: String {
        switch key { case .space: " "; case .enter: "\n"; case .tab: "\t"; default: text }
    }
}
public struct Profile: Codable, Sendable, Equatable {
    public var enabled = true
    public var pairs = true
    public var roundPairs = false
    public var layoutSwitch = true
    public var reverseLayout = false
    public var correctBeforeEnter = true
    public var retroactive = true
    public var strictLatin = false
    public var spaceOnly = false
    public var inlineCompletion = false
    public var doubleShift = true
    public var backspaceRevert = false
    public var interEventDelayMs: Double = 0
    public var chunkSize = 20
    public init() {}
}
public struct Stroke: Codable, Sendable, Equatable {
    public var text: String
    public var keyCode: Int?
    public var modifiers: Modifiers
    public var source: String
    public var time: Double
    public init(_ event: KeyEvent, text: String? = nil) {
        self.text = text ?? event.characters; keyCode = event.keyCode; modifiers = event.modifiers
        source = event.source; time = event.time
    }
}
public enum ActionKind: String, Codable, Sendable {
    case pass, hold, swallow, trigger, softTrigger, revert, pairInsert, pairOvertype, pairDelete, manualFix, reset, cancel, plan
}
public struct ActionRecord: Codable, Sendable, Equatable {
    public var kind: ActionKind
    public var eventID: Int?
    public var time: Double
    public init(_ kind: ActionKind, eventID: Int? = nil, time: Double) {
        self.kind = kind; self.eventID = eventID; self.time = time
    }
}
public enum CoreError: Error { case invalidData, missingLayout, invalidPlan, invalidScenario }
