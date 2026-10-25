import Foundation

public enum PlanKind: String, Codable, Sendable { case correction, layout, revert, pairInsert, pairDelete, pairOvertype, manual }
public enum InjectionOperation: Sendable, Equatable {
    case backspace, forwardDelete, text(String), textUp, left, right, trailing(KeyEvent)
    public var modifiers: Modifiers { [] }
}
public struct InjectionPlan: Sendable, Equatable {
    public var kind: PlanKind
    public var epoch: Int
    public var start: Int
    public var deleteBackward: Int
    public var deleteForward: Int
    public var insert: String
    public var trailing: KeyEvent?
    public var then: [KeyEvent]
    public var before: String
    public var after: String
    public var beforeCursor: Int
    public var afterCursor: Int
    public var cursorLeft: Int
    public var cursorRight: Int
    public var inputSourceBefore: String
    public var inputSourceAfter: String
    public var overtypeTrailing: Bool
    public var pairsBefore: [AutoPair.Pending]? = nil
    public var pairsAfter: [AutoPair.Pending]? = nil
    public init(kind: PlanKind, epoch: Int, start: Int, deleteBackward: Int = 0, deleteForward: Int = 0,
                insert: String = "", trailing: KeyEvent? = nil, then: [KeyEvent] = [], before: String = "", after: String = "",
                beforeCursor: Int? = nil, afterCursor: Int? = nil, cursorLeft: Int = 0, cursorRight: Int = 0,
                inputSourceBefore: String = "ru", inputSourceAfter: String = "ru", overtypeTrailing: Bool = false) {
        self.kind = kind; self.epoch = epoch; self.start = start; self.deleteBackward = deleteBackward; self.deleteForward = deleteForward
        self.insert = insert; self.trailing = trailing; self.then = then; self.before = before; self.after = after
        self.beforeCursor = beforeCursor ?? before.count; self.afterCursor = afterCursor ?? after.count
        self.cursorLeft = cursorLeft; self.cursorRight = cursorRight; self.inputSourceBefore = inputSourceBefore
        self.inputSourceAfter = inputSourceAfter; self.overtypeTrailing = overtypeTrailing
    }
    public var isCorrection: Bool { [.correction, .layout, .manual].contains(kind) }
    public var originalToken: String {
        let length = max(0, beforeCursor-(trailing?.characters.count ?? 0))
        return String(before.prefix(length)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public func operations(chunkSize: Int = 20) -> [InjectionOperation] {
        var result = Array(repeating: InjectionOperation.backspace, count: max(0, deleteBackward))
        result += Array(repeating: .forwardDelete, count: max(0, deleteForward))
        // Chunk on Unicode scalar boundaries, never split a UTF-16 surrogate pair.
        let limit = max(2, min(20, chunkSize)); var chunk = ""
        for scalar in insert.unicodeScalars {
            let next = String(scalar)
            if chunk.utf16.count + next.utf16.count > limit { result += [.text(chunk), .textUp]; chunk = "" }
            chunk += next
        }
        if !chunk.isEmpty { result += [.text(chunk), .textUp] }
        result += Array(repeating: .left, count: max(0, cursorLeft))
        result += Array(repeating: .right, count: max(0, cursorRight))
        if let trailing { result.append(overtypeTrailing ? .right : .trailing(trailing)) }
        return result
    }
    public func inverse(withoutDelimiter: Bool = false) -> InjectionPlan {
        var restored = before; var cursor = beforeCursor
        if withoutDelimiter, let delimiter = trailing?.characters, !delimiter.isEmpty {
            var chars = Array(restored)
            let count = delimiter.count
            if cursor >= count && String(chars[(cursor-count)..<cursor]) == delimiter {
                chars.removeSubrange((cursor-count)..<cursor); cursor -= count; restored = String(chars)
            }
        }
        var result = InjectionPlan(kind: .revert, epoch: epoch, start: start, deleteBackward: afterCursor,
                             deleteForward: after.count - afterCursor, insert: restored, before: after, after: restored,
                             beforeCursor: afterCursor, afterCursor: cursor, cursorLeft: restored.count-cursor,
                             inputSourceBefore: inputSourceAfter, inputSourceAfter: inputSourceBefore)
        result.pairsBefore = pairsAfter; result.pairsAfter = pairsBefore
        return result
    }
    public static func retroactive(original: String, replacement: String, tail: String, start: Int, epoch: Int,
                                   sourceBefore: String, sourceAfter: String, trailing: KeyEvent?, profile: Profile,
                                   sameEpoch: Bool, wordsFromEnd: Int, idleMs: Double) -> InjectionPlan? {
        guard profile.retroactive, sameEpoch, wordsFromEnd <= 2, wordsFromEnd > 0, tail.count <= 40,
              tail.allSatisfy({ $0.isLetter || $0 == " " || $0 == "-" }), trailing != nil || idleMs >= 120 else { return nil }
        let delimiter = trailing?.characters ?? ""
        return InjectionPlan(kind: .correction, epoch: epoch, start: start, deleteBackward: original.count+tail.count,
                             insert: replacement+tail, trailing: trailing, before: original+tail+delimiter,
                             after: replacement+tail+delimiter, inputSourceBefore: sourceBefore, inputSourceAfter: sourceAfter)
    }
}

public struct RevertWindow: Sendable {
    public private(set) var journal: [InjectionPlan] = []
    public private(set) var current: InjectionPlan?
    private var openedAt: Double = 0
    public init() {}
    public mutating func record(_ plan: InjectionPlan, at time: Double) {
        guard plan.isCorrection else { return }
        journal.append(plan); if journal.count > 3 { journal.removeFirst() }
        current = plan; openedAt = time
    }
    public func available(at time: Double) -> InjectionPlan? { time-openedAt <= 15_000 ? current : nil }
    public mutating func close() { current = nil }
    public mutating func reset() { current = nil; journal.removeAll() }
    public mutating func remove(_ plan: InjectionPlan) { journal.removeAll { $0 == plan }; close() }
}

public struct AutoPair: Sendable {
    public struct Pending: Sendable, Equatable { public var opener: String; public var closer: String; public var position: Int }
    public private(set) var stack: [Pending] = []
    public init() {}
    public static func closing(for opening: String, previous: Character?, round: Bool) -> String? {
        switch opening {
        case "[": return "]"
        case "{": return "}"
        case "(" where round: return ")"
        case "\"" where previous == nil || previous!.isWhitespace || "[({\n".contains(previous!): return "\""
        default: return nil
        }
    }
    public mutating func opened(_ opening: String, closing: String, position: Int) { stack.append(Pending(opener: opening, closer: closing, position: position)) }
    public func canOvertype(_ text: String) -> Bool { stack.last?.closer == text }
    public func empty(at cursor: Int) -> Bool { stack.last.map { $0.position+1 == cursor } ?? false }
    public mutating func pop() { _ = stack.popLast() }
    public mutating func reset() { stack.removeAll() }
    public mutating func restore(_ snapshot: [Pending]) { stack = snapshot }
    public func closingSuffix(from start: Int) -> String { stack.reversed().filter { $0.position >= start }.map(\.closer).joined() }
    public mutating func remove(from start: Int) { stack.removeAll { $0.position >= start } }
    public mutating func shift(after start: Int, by delta: Int) {
        for i in stack.indices where stack[i].position >= start { stack[i].position += delta }
    }
}
