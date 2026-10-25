import XCTest
import Foundation
@testable import UCCore

private struct Generator {
    var state: UInt64 = 0x5543320001
    mutating func next(_ bound:Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 32) % UInt64(bound))
    }
}
/// Independent, string-based editor oracle. It never calls VirtualField or InjectionPlan.operations.
private struct ReferenceEditor {
    var content=""
    var cursor=0
    var history:[(String,Int)]=[]
    mutating func splice(_ range:Range<Int>,_ replacement:String) {
        let start=content.index(content.startIndex,offsetBy:range.lowerBound)
        let end=content.index(content.startIndex,offsetBy:range.upperBound)
        content.replaceSubrange(start..<end,with:replacement)
    }
    mutating func event(_ e:KeyEvent) {
        if e.kind == .mouse, let caret=e.caretPosition { cursor=min(content.count,max(0,caret)) }
        guard e.kind == .down else { return }
        if e.modifiers.contains(.command) && e.text == "z" {
            if let undo=history.popLast() { content=undo.0;cursor=undo.1 };return
        }
        if !e.modifiers.intersection([.command,.control,.function]).isEmpty { return }
        history.append((content,cursor))
        switch e.key {
        case .backspace:
            if cursor>0 { splice((cursor-1)..<cursor,"");cursor-=1 }
        case .forwardDelete:
            if cursor<content.count { splice(cursor..<(cursor+1),"") }
        case .left:cursor=max(0,cursor-1)
        case .right:cursor=min(content.count,cursor+1)
        case .home:cursor=0
        case .end:cursor=content.count
        case .character,.space,.enter:splice(cursor..<cursor,e.characters);cursor+=e.characters.count
        default:break
        }
    }
    mutating func plan(_ p:InjectionPlan) -> Bool {
        guard cursor>=p.deleteBackward, cursor+p.deleteForward<=content.count else { return false }
        let start=cursor-p.deleteBackward
        let observed = String(content.dropFirst(start).prefix(p.deleteBackward+p.deleteForward))
        var expected = Array(p.before)
        // before includes the held delimiter, which has not reached the field yet.
        if let trailing = p.trailing {
            let length = trailing.characters.count
            guard p.beforeCursor >= length, p.beforeCursor <= expected.count else { return false }
            expected.removeSubrange((p.beforeCursor-length)..<p.beforeCursor)
        }
        guard observed == String(expected) else { return false }
        splice(start..<(cursor+p.deleteForward),p.insert)
        cursor=start+p.insert.count
        cursor=max(0,min(content.count,cursor-p.cursorLeft+p.cursorRight))
        if let trailing=p.trailing {
            if p.overtypeTrailing { cursor=min(content.count,cursor+1) }
            else { event(trailing) }
        }
        return true
    }
}

final class PropertyTests:XCTestCase {
    func testTenThousandFixedSeedStreamsWithBothEngines() throws {
        let map=try layouts();var rng=Generator();var correctionPlans=0;var totalEvents=0;var totalPlans=0
        let alphabet=Array("абвгдпревт []{}\".-🧪")
        for stream in 0..<10_000 {
            var events:[KeyEvent]=[];var time:Double=0
            let count=20+rng.next(40)
            for i in 0..<count {
                time += Double(rng.next(5)+1)
                var e=KeyEvent(id:i+1,time:time,source:"ru")
                if i<7 {
                    let c=Array("превет ")[i];e.text=String(c);e.key = c == " " ? .space : .character
                } else {
                    switch rng.next(15) {
                    case 0:e.key = .backspace
                    case 1:e.key = .left
                    case 2:e.key = .right
                    case 3:e.kind = .flags;e.modifiers = rng.next(2)==0 ? .shift : []
                    case 4:e.kind = .up
                    case 5:e.kind = .focus
                    case 6:e.key = .space
                    case 7:e.key = .enter
                    case 8:e.kind = .mouse;e.caretPosition=rng.next(8)
                    case 9:e.text="c";e.modifiers = .command
                    default:e.text=String(alphabet[rng.next(alphabet.count)])
                    }
                }
                if let entry=map.stroke(for:e.text,source:"ru") { e.keyCode=entry.keyCode }
                events.append(e)
            }
            totalEvents+=events.count
            for mode in 0..<2 {
                var profile=Profile();profile.pairs = stream%3==0
                let engine:any CorrectionEngine = mode==0 ? KeepEngine() : StubLayoutEngine(rules:[StubRule(input:"превет",replacement:"привет")],map:map)
                var driver=InputCoordinator(session:TypingSession(boundaryKnown:true,profile:profile),field:VirtualField(),engine:engine,map:map,
                                            decisionDelayMs:Double(stream%28),planStepMs:Double(stream%4))
                for e in events { driver.receive(e) };driver.finish()
                XCTAssertTrue(driver.field.deliveredIDs==events.map(\.id),"stream=\(stream) engine=\(mode) order")
                var reference=ReferenceEditor();var valid=true
                for step in driver.trace {
                    switch step {
                    case .event(let e,let consumed):if !consumed { reference.event(e) }
                    case .injection(let plan):valid = reference.plan(plan) && valid
                    }
                }
                let same=valid && reference.content==driver.field.text && reference.cursor==driver.field.cursor
                XCTAssertTrue(same,"stream=\(stream) engine=\(mode) reference")
                XCTAssertTrue(driver.queue.isEmpty && !driver.busy,"stream=\(stream) drained")
                XCTAssertLessThanOrEqual(driver.session.buffer.count,400)
                if !same || driver.field.deliveredIDs != events.map(\.id) { return }
                totalPlans+=driver.plans.count
                correctionPlans+=driver.plans.filter { $0.isCorrection }.count
                if driver.plans.isEmpty {
                    var baseline=ReferenceEditor();for e in events { baseline.event(e) }
                    XCTAssertTrue(baseline.content==driver.field.text,"stream=\(stream) unchanged baseline")
                }
            }
        }
        XCTAssertGreaterThan(correctionPlans,1000)
        let report:[String:Any]=["seed":"0x5543320001","streams":10_000,"engines":2,"executions":20_000,"events_per_engine":totalEvents,
                                 "plans":totalPlans,"correction_plans":correctionPlans,"failures":0]
        let folder=projectRoot.appendingPathComponent("work");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("property-report.json"))
        print("property_streams=10000 engines=2 executions=20000 failures=0")
    }
}
