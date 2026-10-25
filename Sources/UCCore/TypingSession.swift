import Foundation

public struct SessionEffect: Sendable {
    public var action: ActionKind
    public var pass: Bool
    public var request: CorrectionRequest?
    public var plan: InjectionPlan?
    public init(_ action: ActionKind = .pass, pass: Bool = true, request: CorrectionRequest? = nil, plan: InjectionPlan? = nil) {
        self.action = action; self.pass = pass; self.request = request; self.plan = plan
    }
}
public struct TypingSession: Sendable {
    public private(set) var buffer: [Stroke] = []
    public private(set) var epoch = 0
    public private(set) var leftBoundaryKnown: Bool
    public private(set) var source: String
    public private(set) var secure = false
    public private(set) var pairs = AutoPair()
    public private(set) var reverts = RevertWindow()
    public var profile: Profile
    public private(set) var inCode = false
    public private(set) var lastTypedAt: Double = -.infinity
    public private(set) var acceptedTokens = Set<String>()
    private var tokenStart = 0
    private var bufferStartBoundaryKnown: Bool
    private var sentenceStart = true
    private var shiftReleasedAt: Double?
    private var shiftDown = false
    private var deferred: CorrectionRequest?
    private var soft: (CorrectionRequest, CorrectionDecision)?
    private var manualOriginal: InjectionPlan?
    private var manualCandidates: [CorrectionDecision] = []
    private var manualIndex = 0
    public init(source: String = "ru", boundaryKnown: Bool = false, profile: Profile = Profile()) {
        self.source = source; leftBoundaryKnown = boundaryKnown; self.profile = profile
        bufferStartBoundaryKnown = boundaryKnown
    }
    public var text: String { buffer.map(\.text).joined() }
    public mutating func reset(boundaryKnown: Bool = false) {
        epoch += 1; buffer.removeAll(); tokenStart = 0; leftBoundaryKnown = boundaryKnown
        bufferStartBoundaryKnown = boundaryKnown
        pairs.reset(); reverts.reset(); deferred = nil; soft = nil; inCode = false
        shiftReleasedAt = nil; shiftDown = false; manualOriginal = nil; acceptedTokens.removeAll(); sentenceStart = boundaryKnown
        manualCandidates.removeAll(); manualIndex = 0
    }
    public func held(_ event: KeyEvent) -> SessionEffect { SessionEffect(.hold, pass: false) }
    public mutating func prepareManual(_ candidates: [CorrectionDecision]) {
        manualCandidates = candidates.filter { if case .replace = $0 { return true }; return false }
        manualIndex = 0
    }
    private mutating func append(_ event: KeyEvent) {
        for character in event.characters { buffer.append(Stroke(event, text: String(character))) }
        if buffer.count > 400 {
            let count = buffer.count-400
            buffer.removeFirst(count); tokenStart -= count
            bufferStartBoundaryKnown = false
            if tokenStart < 0 { tokenStart = 0; leftBoundaryKnown = false }
            pairs.reset(); reverts.reset(); deferred = nil; soft = nil; manualOriginal = nil
        }
    }
    private mutating func boundary(_ event: KeyEvent) {
        if event.key == .enter { reset(boundaryKnown: true); return }
        if tokenStart < buffer.count { sentenceStart = false }
        append(event); tokenStart = buffer.count; leftBoundaryKnown = true
        if event.characters.contains(where: { ".!?…".contains($0) }) { sentenceStart = true }
    }
    private mutating func recomputeTokenStart() {
        tokenStart = buffer.count
        let english = TokenRules.english(source)
        while tokenStart > 0 {
            let previous = buffer[tokenStart-1].text
            if previous.contains(where: \.isWhitespace) ||
                (!english && previous.count == 1 && ",!?:;()[]{}»…\"".contains(previous)) { break }
            tokenStart -= 1
        }
        leftBoundaryKnown = tokenStart > 0 || bufferStartBoundaryKnown
    }
    private func request(trailing: KeyEvent?, manual: Bool = false, soft: Bool = false) -> CorrectionRequest? {
        guard leftBoundaryKnown, tokenStart < buffer.count else { return nil }
        let strokes = Array(buffer[tokenStart...]); let token = strokes.map(\.text).joined()
        guard !acceptedTokens.contains(token), TokenRules.eligible(token, source: source, sentenceStart: sentenceStart, inCode: inCode, manual: manual) else { return nil }
        if TokenRules.english(source) && !profile.layoutSwitch && !manual { return nil }
        return CorrectionRequest(strokes: strokes, token: token,
                                 context: String(text.prefix(tokenStart)).split(whereSeparator: \.isWhitespace).map(String.init),
                                 start: tokenStart, epoch: epoch, source: source, trailing: trailing, soft: soft, manual: manual, profile: profile)
    }
    public mutating func handle(_ event: KeyEvent) -> SessionEffect {
        if event.own { return SessionEffect() }
        if event.kind == .secureInput { secure = event.secure; reset(); return SessionEffect(.reset) }
        if [.focus, .mouse, .sourceChanged, .tapDisabled].contains(event.kind) {
            if event.kind == .sourceChanged { source = event.source }
            reset(); return SessionEffect(.reset)
        }
        if event.kind == .up { return SessionEffect() }
        if event.kind == .flags {
            if event.modifiers.contains(.function) { reset(); return SessionEffect(.reset) }
            let nowDown = event.modifiers.contains(.shift)
            defer { shiftDown = nowDown }
            guard shiftDown && !nowDown else { return SessionEffect() }
            if let previous = shiftReleasedAt, event.time-previous <= 350, profile.doubleShift, !secure, profile.enabled {
                shiftReleasedAt = nil
                return manualEffect(event)
            }
            shiftReleasedAt = event.time
            return SessionEffect()
        }
        if event.kind != .down { return SessionEffect() }
        shiftReleasedAt = nil
        if event.modifiers.contains(.command), event.text.lowercased() == "z", !event.modifiers.contains(.shift),
           let previous = reverts.available(at: event.time) {
            reverts.remove(previous); acceptedTokens.insert(previous.originalToken)
            return SessionEffect(.revert, pass: false, plan: previous.inverse())
        }
        if event.key == .backspace, profile.backspaceRevert, let previous = reverts.available(at: event.time) {
            reverts.remove(previous); acceptedTokens.insert(previous.originalToken)
            return SessionEffect(.revert, pass: false, plan: previous.inverse(withoutDelimiter: true))
        }
        reverts.close(); manualOriginal = nil
        let whitelist = event.modifiers == .command && ["c", "s", "f"].contains(event.text.lowercased())
        if whitelist { return SessionEffect() }
        if !event.modifiers.intersection([.command, .control, .function]).isEmpty ||
            (event.key == .backspace && event.modifiers.contains(.option)) ||
            [.tab, .forwardDelete, .left, .right, .up, .down, .home, .end, .pageUp, .pageDown, .escape, .globe].contains(event.key) {
            reset(); return SessionEffect(.reset)
        }
        if secure || !profile.enabled || !TokenRules.simpleSource(event.source) || event.deadKey {
            reset(); source = event.source; return SessionEffect(.reset)
        }
        if source != event.source { reset(); source = event.source }
        lastTypedAt = event.time
        if event.key == .backspace {
            soft = nil; deferred = nil
            if profile.pairs && pairs.empty(at: buffer.count) {
                let closing = pairs.stack.last!.closer; let opening = buffer.last?.text ?? ""
                pairs.pop(); if !buffer.isEmpty { buffer.removeLast() }
                recomputeTokenStart()
                let plan = InjectionPlan(kind: .pairDelete, epoch: epoch, start: buffer.count, deleteBackward: 1, deleteForward: 1,
                                         before: opening+closing, inputSourceBefore: source, inputSourceAfter: source)
                return SessionEffect(.pairDelete, pass: false, plan: plan)
            }
            if !buffer.isEmpty { buffer.removeLast() }
            if buffer.isEmpty { bufferStartBoundaryKnown = false }
            recomputeTokenStart(); return SessionEffect()
        }
        if let pending = soft {
            soft = nil
            if event.key == .space || (event.key == .enter && profile.correctBeforeEnter) {
                var r = pending.0; r.trailing = event; r.soft = false
                if case .replace(let replacement, let nextSource) = pending.1,
                   let plan = makePlan(r, replacement: replacement + ".", sourceAfter: nextSource, extraBackward: 1) {
                    return SessionEffect(.trigger, pass: false, plan: plan)
                }
            }
        }
        if event.key == .enter && !profile.correctBeforeEnter { boundary(event); return SessionEffect() }
        let isEnglish = TokenRules.english(source)
        let quoteClosesWord = event.characters == "\"" && text.last?.isLetter == true
        let hard = event.key == .space || event.key == .enter || (!isEnglish && event.characters.count == 1 && (",!?:;)]}»…".contains(event.characters) || quoteClosesWord))
        let softDot = !isEnglish && event.characters == "." && !profile.spaceOnly
        if (hard && (!profile.spaceOnly || event.key == .space)) || softDot {
            var req = request(trailing: event, soft: softDot)
            if event.key == .space || event.key == .enter, let previous = deferred,
               previous.epoch == epoch, profile.retroactive,
               buffer.count-previous.start <= previous.token.count+41,
               String(text.dropFirst(previous.start+previous.token.count)).allSatisfy({
                   $0.isLetter || $0 == " " || $0 == "-" || (isEnglish && "`[];',.~{}:\"<>".contains($0))
               }) {
                let strokes = Array(buffer[previous.start...]); let combined = strokes.map(\.text).joined()
                req = CorrectionRequest(strokes: strokes, token: combined, context: previous.context, start: previous.start,
                                        epoch: epoch, source: previous.source, trailing: event, soft: false, manual: false, profile: profile)
            }
            if let req { return SessionEffect(softDot ? .softTrigger : .trigger, pass: false, request: req) }
            if profile.pairs && pairs.canOvertype(event.characters) { return overtype(event) }
            if !softDot { boundary(event) } else { append(event) }
            return SessionEffect()
        }
        if profile.pairs && pairs.canOvertype(event.characters) { return overtype(event) }
        if !isEnglish && event.characters == "`" { inCode.toggle() }
        let previous = text.last
        append(event)
        if profile.pairs, let close = AutoPair.closing(for: event.characters, previous: previous, round: profile.roundPairs) {
            pairs.opened(event.characters, closing: close, position: buffer.count-1)
            if !isEnglish { tokenStart = buffer.count; leftBoundaryKnown = true }
            let plan = InjectionPlan(kind: .pairInsert, epoch: epoch, start: buffer.count, insert: close, after: close,
                                     afterCursor: 0, cursorLeft: 1, inputSourceBefore: source, inputSourceAfter: source)
            return SessionEffect(.pairInsert, pass: true, plan: plan)
        }
        if event.key == .space || event.key == .enter { tokenStart = buffer.count; leftBoundaryKnown = true }
        if !isEnglish && ["[", "{", "("].contains(event.characters) { tokenStart = buffer.count; leftBoundaryKnown = true }
        return SessionEffect()
    }
    private mutating func overtype(_ event: KeyEvent) -> SessionEffect {
        pairs.pop(); append(event); tokenStart = buffer.count; leftBoundaryKnown = true
        return SessionEffect(.pairOvertype, pass: false, plan: InjectionPlan(kind: .pairOvertype, epoch: epoch, start: buffer.count-1,
                                                                           cursorRight: 1, inputSourceBefore: source, inputSourceAfter: source))
    }
    public mutating func declined(_ request: CorrectionRequest, decision: CorrectionDecision = .keep) -> SessionEffect {
        if request.soft {
            soft = (request, decision)
            if let event = request.trailing { append(event) }
        } else {
            if case .deferred = decision { deferred = request } else { deferred = nil }
            if let event = request.trailing {
                if profile.pairs && pairs.canOvertype(event.characters) { return overtype(event) }
                boundary(event)
            }
        }
        return SessionEffect()
    }
    public func makePlan(_ request: CorrectionRequest, replacement: String, sourceAfter: String?, extraBackward: Int = 0) -> InjectionPlan? {
        guard request.epoch == epoch, request.start >= 0, request.start <= buffer.count else { return nil }
        let nextSource = sourceAfter ?? source
        let tail = request.manual ? String(text.dropFirst(request.start+request.token.count)) : ""
        if request.manual && (tail.count > 40 || !tail.allSatisfy({ $0.isLetter || $0 == " " || $0 == "-" })) { return nil }
        let owned = nextSource != source ? pairs.closingSuffix(from: request.start) : ""
        let delimiter = request.trailing?.characters ?? ""
        let original = request.token + (extraBackward > 0 ? "." : "") + tail
        let overtype = !owned.isEmpty ? false : request.trailing.map { pairs.canOvertype($0.characters) } ?? false
        var result = InjectionPlan(kind: request.manual ? .manual : (sourceAfter == nil ? .correction : .layout), epoch: epoch, start: request.start,
                             deleteBackward: original.count, deleteForward: owned.count,
                             insert: replacement+tail, trailing: request.trailing, before: original+delimiter+owned,
                             after: replacement+tail+delimiter, beforeCursor: original.count+delimiter.count,
                             inputSourceBefore: source, inputSourceAfter: nextSource, overtypeTrailing: overtype)
        result.pairsBefore = pairs.stack
        var afterPairs = pairs
        if !owned.isEmpty { afterPairs.remove(from: request.start) }
        if overtype { afterPairs.pop() }
        afterPairs.shift(after: request.start, by: result.afterCursor-original.count)
        result.pairsAfter = afterPairs.stack
        return result
    }
    public mutating func completed(_ plan: InjectionPlan, at time: Double) {
        guard plan.isCorrection || plan.kind == .revert else { return }
        if plan.epoch != epoch { return }
        if plan.kind == .manual && manualOriginal == nil { manualOriginal = plan }
        let start = min(plan.start, buffer.count); buffer.removeSubrange(start...)
        let newText = String(plan.after.prefix(plan.afterCursor))
        source = plan.inputSourceAfter
        let event = KeyEvent(time: time, text: newText, source: source)
        append(event)
        if let snapshot = plan.pairsAfter { pairs.restore(snapshot) }
        else {
            if plan.deleteForward > 0 { pairs.remove(from: start) }
            if plan.overtypeTrailing { pairs.pop() }
            pairs.shift(after: start, by: newText.count-plan.deleteBackward)
        }
        deferred = nil; soft = nil
        recomputeTokenStart()
        sentenceStart = newText.last.map { ".!?\n".contains($0) } ?? false
        if plan.trailing?.key == .enter {
            // Enter begins a new epoch. Only this correction remains available for immediate undo.
            reset(boundaryKnown: true)
            var undoable = plan; undoable.epoch = epoch; undoable.start = 0
            reverts.record(undoable, at: time)
            return
        }
        reverts.record(plan, at: time)
    }
    private mutating func manualEffect(_ event: KeyEvent) -> SessionEffect {
        if let original = manualOriginal {
            let current = reverts.journal.last(where: { $0.kind == .manual }) ?? original
            manualIndex += 1
            if manualIndex < manualCandidates.count,
               case .replace(let replacement, let nextSource) = manualCandidates[manualIndex] {
                let tail = String(original.after.reversed().prefix(while: \.isWhitespace).reversed())
                var next = InjectionPlan(kind: .manual, epoch: epoch, start: original.start,
                                         deleteBackward: current.afterCursor, deleteForward: current.after.count-current.afterCursor,
                                         insert: replacement+tail, before: current.after, after: replacement+tail,
                                         beforeCursor: current.afterCursor, inputSourceBefore: source,
                                         inputSourceAfter: nextSource ?? source)
                next.pairsBefore = current.pairsAfter; next.pairsAfter = current.pairsAfter
                return SessionEffect(.manualFix, pass: false, plan: next)
            }
            manualOriginal = nil; reverts.remove(current)
            var undo = original.inverse()
            undo.deleteBackward = current.afterCursor; undo.deleteForward = current.after.count-current.afterCursor
            undo.before = current.after; undo.inputSourceBefore = source
            return SessionEffect(.manualFix, pass: false, plan: undo)
        }
        for previous in reverts.journal.reversed() {
            guard previous.epoch == epoch, previous.start <= buffer.count else { continue }
            let suffix = String(text.dropFirst(previous.start))
            guard suffix.hasPrefix(previous.after) else { continue }
            let tail = String(suffix.dropFirst(previous.after.count))
            let wordCount = suffix.split(whereSeparator: \.isWhitespace).count
            if let plan = InjectionPlan.retroactive(original: previous.after, replacement: previous.before, tail: tail,
                                                    start: previous.start, epoch: epoch, sourceBefore: source,
                                                    sourceAfter: previous.inputSourceBefore, trailing: nil, profile: profile,
                                                    sameEpoch: true, wordsFromEnd: wordCount, idleMs: event.time-lastTypedAt) {
                var undo = plan; undo.kind = .revert; reverts.remove(previous)
                acceptedTokens.insert(previous.originalToken)
                return SessionEffect(.revert, pass: false, plan: undo)
            }
        }
        var start = buffer.count
        while start > 0 && buffer[start-1].text.allSatisfy(\.isWhitespace) { start -= 1 }
        let wordEnd = start
        while start > 0 && !buffer[start-1].text.contains(where: \.isWhitespace) { start -= 1 }
        guard start < wordEnd, leftBoundaryKnown else { return SessionEffect(.manualFix) }
        let strokes = Array(buffer[start..<wordEnd]); let token = strokes.map(\.text).joined()
        let request = CorrectionRequest(strokes: strokes, token: token, context: [], start: start, epoch: epoch,
                                        source: source, trailing: nil, soft: false, manual: true, profile: profile)
        return SessionEffect(.manualFix, pass: false, request: request)
    }
}
