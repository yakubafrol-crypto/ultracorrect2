import Foundation

public enum ReplayStep: Sendable {
    case event(KeyEvent, consumed: Bool)
    case injection(InjectionPlan)
}
/// A deterministic event scheduler. The platform layer will supply the same clock and completion messages.
public struct InputCoordinator: Sendable {
    public private(set) var session: TypingSession
    public private(set) var field: VirtualField
    public private(set) var actions: [ActionRecord] = []
    public private(set) var plans: [InjectionPlan] = []
    public private(set) var queue: [KeyEvent] = []
    public private(set) var cancellations = 0
    public private(set) var replayMappingFailures = 0
    public private(set) var trace: [ReplayStep] = []
    public var decisionDelayMs: Double
    public var planStepMs: Double
    public let engine: any CorrectionEngine
    public let map: any KeyLayoutMap
    private var pending: (CorrectionRequest, Double)?
    private var executing: (InjectionPlan, [InjectionOperation], Int, Double)?
    private var now: Double = 0
    private var suspendedAt: Double = 0
    public init(session: TypingSession, field: VirtualField, engine: any CorrectionEngine, map: any KeyLayoutMap,
                decisionDelayMs: Double = 0, planStepMs: Double = 0) {
        self.session = session; self.field = field; self.engine = engine; self.map = map
        self.decisionDelayMs = max(0, decisionDelayMs); self.planStepMs = max(0, planStepMs)
    }
    public var busy: Bool { pending != nil || executing != nil }
    private mutating func deliver(_ event: KeyEvent, consumed: Bool = false, account: Bool = true) {
        trace.append(.event(event,consumed:consumed))
        if consumed { field.account(event) } else { field.receive(event,account:account) }
    }
    public mutating func receive(_ event: KeyEvent) {
        advance(to: event.time)
        if busy {
            queue.append(event); actions.append(ActionRecord(session.held(event).action, eventID: event.id, time: event.time))
            // Never abandon an executing plan, even on overflow, focus loss or permission changes.
            if executing == nil && (queue.count > 64 || event.time-suspendedAt > 150 ||
                                    [.mouse,.focus,.secureInput,.sourceChanged,.tapDisabled].contains(event.kind)) { cancelPending() }
            return
        }
        process(event)
        advance(to: event.time)
    }
    private mutating func process(_ event: KeyEvent) {
        now = max(now,event.time)
        let effect = session.handle(event)
        actions.append(ActionRecord(effect.action,eventID:event.id,time:now))
        if let request = effect.request {
            pending = (request,now); suspendedAt = now
            // The triggering key is accounted when its plan/unchanged delimiter is delivered.
            if request.trailing == nil { deliver(event,consumed:true) }
        } else if let plan = effect.plan {
            if effect.pass { deliver(event) } else if plan.trailing?.id != event.id { deliver(event,consumed:true) }
            if !begin(plan, at: now, checkWitness: plan.isCorrection || plan.kind == .revert) {
                if !effect.pass { deliver(event, account: plan.trailing?.id == event.id) }
                session.reset()
            }
        } else if effect.pass { deliver(event) }
        else { deliver(event,consumed:true) }
    }
    private mutating func cancelPending() {
        guard let (request,_) = pending else { return }
        pending = nil; cancellations += 1; actions.append(ActionRecord(.cancel,time:now))
        let effect = session.declined(request)
        if let event = request.trailing {
            if let plan = effect.plan { deliver(event,consumed:true); begin(plan,at:now,checkWitness:false) }
            else { deliver(event) }
        }
        replay()
    }
    public mutating func advance(to time: Double) {
        while true {
            if let (request,started) = pending {
                let due = started + min(decisionDelayMs,25)
                if due > time { break }
                now = due
                if decisionDelayMs >= 25 { cancelPending(); continue }
                pending = nil
                var decision = engine.decide(request)
                if request.manual && TokenRules.english(request.source),
                   let converted = LayoutConverter(map:map).convert(request.strokes,to:"ru") { decision = .replace(converted,source:"ru") }
                if request.manual {
                    session.prepareManual(TokenRules.english(request.source) ? [decision] : engine.candidates(request))
                }
                if !request.manual, TokenRules.english(request.source),
                   case .replace(let value, let source) = decision, source != nil, value.filter(\.isLetter).count <= 2 {
                    decision = .deferred(value, source: source)
                }
                if request.soft {
                    _ = session.declined(request,decision:decision)
                    if let event = request.trailing { deliver(event) }
                    replay(); continue
                }
                switch decision {
                case .replace(let value,let source):
                    if let plan = session.makePlan(request,replacement:value,sourceAfter:source) {
                        if !begin(plan,at:now,checkWitness:true) {
                            let effect = session.declined(request)
                            if let event = request.trailing {
                                if let plan = effect.plan { deliver(event,consumed:true); begin(plan,at:now,checkWitness:false) }
                                else { deliver(event) }
                            }
                            session.reset(); replay()
                        }
                    } else {
                        if let event = request.trailing { deliver(event) }; session.reset(); replay()
                    }
                default:
                    let effect = session.declined(request,decision:decision)
                    if let event = request.trailing {
                        if let plan = effect.plan { deliver(event,consumed:true); begin(plan,at:now,checkWitness:false) }
                        else { deliver(event) }
                    }
                    replay()
                }
                continue
            }
            if var current = executing {
                let step = max(planStepMs,session.profile.interEventDelayMs)
                let due = current.3 + Double(current.2)*step
                if due > time { break }
                now = due
                if current.2 < current.1.count {
                    let operation = current.1[current.2]
                    field.inject(operation,at:now); current.2 += 1; executing = current
                    continue
                }
                var plan = current.0; plan.then = queue
                if let event = plan.trailing { deliver(event,consumed:true) }
                field.source = plan.inputSourceAfter
                plans.append(plan); session.completed(plan,at:now); executing = nil
                actions.append(ActionRecord(.plan,time:now))
                replay(sourceChanged: plan.inputSourceBefore != plan.inputSourceAfter)
                continue
            }
            break
        }
        now = max(now,time)
    }
    @discardableResult private mutating func begin(_ plan: InjectionPlan, at time: Double, checkWitness: Bool) -> Bool {
        if checkWitness {
            let expected = String(session.text.suffix(plan.deleteBackward))
            if !field.witness.permits(expected:expected,inlineCompletion:session.profile.inlineCompletion) {
                cancellations += 1; actions.append(ActionRecord(.cancel,time:time)); return false
            }
            if plan.inputSourceBefore != plan.inputSourceAfter,
               queue.contains(where: { $0.kind == .down && $0.key == .character && LayoutConverter(map:map).rebase($0,to:plan.inputSourceAfter) == nil }) {
                cancellations += 1; actions.append(ActionRecord(.cancel,time:time)); return false
            }
        }
        trace.append(.injection(plan))
        executing = (plan,plan.operations(chunkSize:session.profile.chunkSize),0,time); suspendedAt = time
        return true
    }
    private mutating func replay(sourceChanged: Bool = false) {
        // New triggers can suspend replay again. Remaining events keep their original order.
        var remaining = queue; queue.removeAll()
        if sourceChanged {
            // Rebase the complete queue before another trigger can suspend replay.
            remaining = remaining.map { event in
                LayoutConverter(map: map).rebase(event, to: field.source) ?? event
            }
        }
        while !remaining.isEmpty {
            var event = remaining.removeFirst()
            event.time = now
            if sourceChanged && event.source != field.source && event.kind != .sourceChanged {
                if let rebased = LayoutConverter(map:map).rebase(event,to:field.source) { event = rebased }
                else { replayMappingFailures += 1; session.reset(); deliver(event); continue }
            }
            if busy { queue.append(event); queue += remaining; break }
            process(event)
        }
    }
    public mutating func finish() { advance(to: now + 1_000_000) }
}
