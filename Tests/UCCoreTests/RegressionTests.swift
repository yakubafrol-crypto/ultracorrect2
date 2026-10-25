import XCTest
@testable import UCCore

final class RegressionTests: XCTestCase {
    func events(_ text: String, source: String = "ru", start: Double = 0) throws -> [KeyEvent] {
        let map = try layouts()
        return text.enumerated().map { index, char in
            let entry = map.stroke(for: String(char), source: source)
            return KeyEvent(id: index+1, time: start+Double(index)*10, key: char == " " ? .space : .character,
                            text: String(char), keyCode: entry?.keyCode, modifiers: Modifiers(rawValue: entry?.modifiers ?? 0), source: source)
        }
    }
    func shift(_ driver: inout InputCoordinator, at time: Double, source: String) {
        for (offset, flags) in [(0.0, Modifiers.shift), (10, []), (100, .shift), (110, [])] {
            driver.receive(KeyEvent(time: time+offset, kind: .flags, modifiers: flags, source: source))
        }
        driver.advance(to: time+200)
    }
    func testManualCandidateCycleReturnsOriginalAndPreservesTail() throws {
        let map = try layouts()
        var profile = Profile(); profile.pairs = false
        var driver = InputCoordinator(session: TypingSession(boundaryKnown: true, profile: profile), field: VirtualField(),
                                      engine: StubLayoutEngine(rules: [StubRule(input: "абв", replacement: "гдеж", alternatives: ["зик"])], map: map), map: map)
        for event in try events("абв") { driver.receive(event) }
        shift(&driver, at: 1000, source: "ru")
        XCTAssertTrue(driver.field.text == "гдеж")
        shift(&driver, at: 2000, source: "ru")
        XCTAssertTrue(driver.field.text == "зик")
        shift(&driver, at: 3000, source: "ru")
        XCTAssertTrue(driver.field.text == "абв")
        XCTAssertEqual(driver.plans.count, 3)
    }
    func testUndoRestoresOwnedClosingPair() throws {
        let map = try layouts()
        var driver = InputCoordinator(session: TypingSession(source: "en", boundaryKnown: true), field: VirtualField(source: "en"),
                                      engine: StubLayoutEngine(rules: [StubRule(input: "[jhjij", source: "ru")], map: map), map: map)
        for event in try events("[jhjij ", source: "en") { driver.receive(event) }
        driver.receive(KeyEvent(time: 100, text: "z", modifiers: .command, source: "ru"))
        XCTAssertTrue(driver.field.text == "[jhjij ]")
        XCTAssertEqual(driver.session.pairs.stack.count, 1)
        driver.receive(KeyEvent(time: 150, text: "]", source: "en"))
        driver.finish()
        XCTAssertTrue(driver.field.text == "[jhjij ]")
        XCTAssertEqual(driver.field.cursor, 8)
    }
    func testReverseLayoutRespectsProfile() throws {
        let map = try layouts()
        for enabled in [false, true] {
            var profile = Profile(); profile.pairs = false; profile.reverseLayout = enabled
            var driver = InputCoordinator(session: TypingSession(boundaryKnown: true, profile: profile), field: VirtualField(),
                                          engine: StubLayoutEngine(rules: [StubRule(input: "руддщ", source: "en")], map: map), map: map)
            for event in try events("руддщ ") { driver.receive(event) }; driver.finish()
            XCTAssertTrue(driver.field.text == (enabled ? "hello " : "руддщ "))
            XCTAssertEqual(driver.field.source, enabled ? "en" : "ru")
        }
    }
    func testHeldQueueRebasedAcrossSecondTrigger() throws {
        let map = try layouts(); var profile = Profile(); profile.pairs = false
        var driver = InputCoordinator(session: TypingSession(source: "en", boundaryKnown: true, profile: profile), field: VirtualField(source: "en"),
                                      engine: StubLayoutEngine(rules: [StubRule(input: "ghbdtn", source: "ru")], map: map), map: map,
                                      decisionDelayMs: 20, planStepMs: 3)
        var input = try events("ghbdtn f g", source: "en")
        for index in input.indices { input[index].time = Double(index) }
        for event in input { driver.receive(event) }; driver.finish()
        XCTAssertTrue(driver.field.text == "привет а п")
        XCTAssertEqual(driver.field.deliveredIDs, input.map(\.id))
        XCTAssertEqual(driver.replayMappingFailures, 0)
    }
    func testIncompleteMappingDeclinesBeforePlanAndPreservesEvents() throws {
        let map = try layouts(); var profile = Profile(); profile.pairs = false
        var driver = InputCoordinator(session: TypingSession(source: "en", boundaryKnown: true, profile: profile), field: VirtualField(source: "en"),
                                      engine: StubLayoutEngine(rules: [StubRule(input: "ghbdtn", source: "ru")], map: map), map: map, decisionDelayMs: 20)
        for event in try events("ghbdtn ", source: "en") { driver.receive(event) }
        driver.receive(KeyEvent(id: 99, time: 61, text: "🧪", source: "en")); driver.finish()
        XCTAssertTrue(driver.field.text == "ghbdtn 🧪")
        XCTAssertEqual(driver.cancellations, 1)
        XCTAssertTrue(driver.plans.isEmpty)
    }
}
