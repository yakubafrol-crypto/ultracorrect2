import XCTest
import Foundation
@testable import UCCore

let projectRoot = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
func layouts() throws -> FixtureLayoutMap { try FixtureLayoutMap(directory:projectRoot.appendingPathComponent("Tests/Fixtures/layouts")) }

final class SimulationTests: XCTestCase {
    func testAllSpecifiedScenarios() throws {
        let scenarios = try SimulationRunner.load(directory:projectRoot.appendingPathComponent("Tests/Scenarios"))
        XCTAssertGreaterThanOrEqual(scenarios.count,80)
        let report = try SimulationRunner.run(scenarios,map:layouts())
        for row in report.results { XCTAssertTrue(row.passed,"scenario_id=\(row.id) failed_checks=\(row.checks.filter { !$0.value }.keys.sorted())") }
    }
    func testPhysicalTablesAndConversion() throws {
        let map = try layouts(); XCTAssertEqual(map.tables.count,4)
        let converter = LayoutConverter(map:map)
        for source in ["en","us","ru","ru-pc"] {
            for entry in map.tables.first(where: { $0.id==source })!.entries where !entry.dead {
                let event=KeyEvent(text:entry.text,keyCode:entry.keyCode,modifiers:Modifiers(rawValue:entry.modifiers),source:source)
                XCTAssertTrue(converter.convert([Stroke(event)],to:source)==entry.text)
            }
        }
        XCTAssertNil(map.character(keyCode:999,modifiers:[],source:"en"))
        XCTAssertNil(map.character(keyCode:0,modifiers:[],source:"ime"))
        XCTAssertNil(map.stroke(for:"🧪",source:"en"))
        XCTAssertNil(converter.convert([Stroke(KeyEvent(text:"x"))],to:"ru"))
        XCTAssertNil(converter.rebase(KeyEvent(text:"x"),to:"ru"))
        let focus=KeyEvent(kind:.sourceChanged,source:"us")
        XCTAssertEqual(converter.rebase(focus,to:"ru"),focus)
        XCTAssertEqual(converter.convert([Stroke(KeyEvent(key:.space)),Stroke(KeyEvent(key:.enter))],to:"ru")," \n")
        let a=map.stroke(for:"a",source:"en")!
        XCTAssertEqual(map.character(keyCode:a.keyCode,modifiers:.capsLock,source:"en"),"A")
        // Apple Russian and Russian-PC intentionally have different slash keys.
        XCTAssertEqual(map.character(keyCode:44,modifiers:.shift,source:"ru"),"?")
        XCTAssertEqual(map.character(keyCode:44,modifiers:.shift,source:"ru-pc"),",")
        for code in [33,30,41,39,43,47,44,50] {
            XCTAssertNotNil(map.character(keyCode:code,modifiers:[],source:"ru"))
        }
    }
    func testEmptyAndMalformedFixturesFailClosed() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        XCTAssertThrowsError(try FixtureLayoutMap(directory:folder))
        XCTAssertThrowsError(try SimulationRunner.load(directory:folder))
        try Data("{}".utf8).write(to:folder.appendingPathComponent("bad.yaml"))
        XCTAssertThrowsError(try SimulationRunner.load(directory:folder))
        var scenario=Scenario(id:"invalid",events:[KeyEvent(id:1,time:2),KeyEvent(id:1,time:1)],expectedText:"")
        XCTAssertThrowsError(try SimulationRunner.execute(scenario,map:layouts()))
        scenario.events=[KeyEvent(time:Double.infinity)]
        XCTAssertThrowsError(try SimulationRunner.execute(scenario,map:layouts()))
    }
    func testInjectionUnicodeChunksHavePairedEdgesAndNeutralFlags() {
        let value=String(repeating:"я🧪e\u{301}",count:25)
        let p=InjectionPlan(kind:.correction,epoch:0,start:0,deleteBackward:3,deleteForward:1,insert:value,cursorLeft:2,cursorRight:1)
        let ops=p.operations(chunkSize:7)
        var joined="";var down=0;var up=0
        for op in ops {
            XCTAssertTrue(op.modifiers.isEmpty)
            if case .text(let chunk)=op { joined+=chunk;down+=1;XCTAssertLessThanOrEqual(chunk.utf16.count,7) }
            if case .textUp=op { up+=1 }
        }
        XCTAssertEqual(joined,value);XCTAssertEqual(down,up)
        var field=VirtualField()
        for op in InjectionPlan(kind:.correction,epoch:0,start:0,insert:value).operations(chunkSize:2) { field.inject(op,at:0) }
        XCTAssertTrue(field.text==value)
        XCTAssertEqual(field.cursor,value.count)
    }
    func testRetroactiveSafetyGuards() {
        var profile=Profile()
        func plan(_ tail:String=" слово ",epoch:Bool=true,words:Int=2,idle:Double=120,delimiter:KeyEvent?=nil) -> InjectionPlan? {
            InjectionPlan.retroactive(original:"абв",replacement:"где",tail:tail,start:0,epoch:1,sourceBefore:"ru",sourceAfter:"ru",
                                      trailing:delimiter,profile:profile,sameEpoch:epoch,wordsFromEnd:words,idleMs:idle)
        }
        XCTAssertNotNil(plan());XCTAssertNil(plan(epoch:false));XCTAssertNil(plan(words:3));XCTAssertNil(plan(words:0))
        XCTAssertNil(plan(idle:119));XCTAssertNotNil(plan(idle:0,delimiter:KeyEvent(key:.space)))
        XCTAssertNil(plan(" мир!"));XCTAssertNil(plan(String(repeating:"а",count:41)));XCTAssertNotNil(plan(String(repeating:"а",count:40)))
        profile.retroactive=false;XCTAssertNil(plan())
    }
    func testRevertWindowJournalAndExpiry() {
        var window=RevertWindow()
        for i in 0..<5 { window.record(InjectionPlan(kind:.correction,epoch:0,start:i,before:"a",after:"b"),at:0) }
        XCTAssertEqual(window.journal.count,3);XCTAssertNotNil(window.available(at:15_000));XCTAssertNil(window.available(at:15_001))
        window.record(InjectionPlan(kind:.pairInsert,epoch:0,start:0),at:1);XCTAssertEqual(window.journal.count,3)
        let plan=window.journal.last!;window.remove(plan);XCTAssertEqual(window.journal.count,2);XCTAssertNil(window.available(at:1))
        window.reset();XCTAssertTrue(window.journal.isEmpty)
        let paired=InjectionPlan(kind:.layout,epoch:0,start:0,deleteBackward:2,deleteForward:1,insert:"аб",trailing:KeyEvent(key:.space),
                                 before:"xy ]",after:"аб ",beforeCursor:3,inputSourceBefore:"en",inputSourceAfter:"ru")
        let inverse=paired.inverse(withoutDelimiter:true)
        XCTAssertEqual(inverse.insert,"xy]");XCTAssertEqual(inverse.cursorLeft,1);XCTAssertEqual(inverse.inputSourceAfter,"en")
    }
    func testWitnessDeadlineAndSelection() {
        XCTAssertFalse(FieldWitness(available:true,beforeCursor:"a",selectionLength:1).permits(expected:"a",inlineCompletion:false))
        XCTAssertFalse(FieldWitness(available:true,beforeCursor:"b").permits(expected:"a",inlineCompletion:false))
        XCTAssertTrue(FieldWitness(available:true,latencyMs:20,beforeCursor:"xa").permits(expected:"a",inlineCompletion:true))
        XCTAssertFalse(FieldWitness(available:true,latencyMs:20.01,beforeCursor:"a").permits(expected:"a",inlineCompletion:true))
        XCTAssertTrue(FieldWitness(available:false).permits(expected:"a",inlineCompletion:false))
    }
    func testVirtualFieldsExposeFailuresRatherThanSilentlyRepairingThem() {
        var slow=VirtualField(kind:.slowBackspace,text:"abcd")
        slow.inject(.backspace,at:0);slow.inject(.backspace,at:1)
        XCTAssertEqual(slow.text,"abc");XCTAssertEqual(slow.lostBackspaces,1)
        var plain=VirtualField(text:"abcd",cursor:1,selectionLength:2)
        plain.receive(KeyEvent(key:.backspace));XCTAssertEqual(plain.text,"ad")
        plain.receive(KeyEvent(key:.forwardDelete));XCTAssertEqual(plain.text,"a")
        plain.receive(KeyEvent(text:"a",modifiers:.command));plain.receive(KeyEvent(text:"b"));XCTAssertEqual(plain.text,"b")
        plain.receive(KeyEvent(key:.home));plain.receive(KeyEvent(key:.end));plain.receive(KeyEvent(key:.right))
        XCTAssertEqual(plain.cursor,1)
        var substitutions=VirtualField(kind:.substitutions)
        for c in "текст  " { substitutions.receive(KeyEvent(text:String(c))) }
        XCTAssertEqual(substitutions.text,"Текст. ")
        var native=VirtualField(kind:.autoPairs)
        native.receive(KeyEvent(text:"["));native.receive(KeyEvent(key:.backspace));XCTAssertTrue(native.text.isEmpty)
    }
}
