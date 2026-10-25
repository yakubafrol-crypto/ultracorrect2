import Foundation

public struct Scenario: Codable, Sendable {
    public var id: String
    public var category: String
    public var source: String
    public var field: FieldKind
    public var initialText: String
    public var initialCursor: Int?
    public var selectionLength: Int
    public var witnessAvailable: Bool
    public var witnessLatencyMs: Double
    public var boundaryKnown: Bool
    public var profile: Profile
    public var rules: [StubRule]
    public var decisionDelayMs: Double
    public var planStepMs: Double
    public var events: [KeyEvent]
    public var expectedText: String
    public var expectedSource: String
    public var expectedCursor: Int?
    public var requiredActions: [ActionKind]
    public var expectedPlans: Int?
    public var expectedCancellations: Int?
    public var completion: String
    public init(id: String, category: String = "mechanics", source: String = "ru", field: FieldKind = .plain,
                initialText: String = "", initialCursor: Int? = nil, selectionLength: Int = 0,
                witnessAvailable: Bool = true, witnessLatencyMs: Double = 0, boundaryKnown: Bool = true,
                profile: Profile = Profile(), rules: [StubRule] = [], decisionDelayMs: Double = 0, planStepMs: Double = 0,
                events: [KeyEvent], expectedText: String, expectedSource: String = "ru", expectedCursor: Int? = nil,
                requiredActions: [ActionKind] = [], expectedPlans: Int? = nil, expectedCancellations: Int? = nil, completion: String = "completion") {
        self.id=id; self.category=category; self.source=source; self.field=field; self.initialText=initialText
        self.initialCursor=initialCursor; self.selectionLength=selectionLength; self.witnessAvailable=witnessAvailable
        self.witnessLatencyMs=witnessLatencyMs; self.boundaryKnown=boundaryKnown; self.profile=profile; self.rules=rules
        self.decisionDelayMs=decisionDelayMs; self.planStepMs=planStepMs; self.events=events; self.expectedText=expectedText
        self.expectedSource=expectedSource; self.expectedCursor=expectedCursor; self.requiredActions=requiredActions
        self.expectedPlans=expectedPlans; self.expectedCancellations=expectedCancellations; self.completion=completion
    }
}
public struct ScenarioResult: Codable, Sendable {
    public var id: String
    public var category: String
    public var passed: Bool
    public var checks: [String: Bool]
    public var actions: [String: Int]
    public var events: Int
    public var plans: Int
    public var cancellations: Int
}
public struct SimulationReport: Codable, Sendable {
    public var schema = 1
    public var scenarios: Int
    public var passed: Int
    public var failed: [String]
    public var results: [ScenarioResult]
}
public enum SimulationRunner {
    public static func load(directory: URL) throws -> [Scenario] {
        let paths = try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
            .filter { $0.pathExtension == "yaml" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        // Scenario files use the JSON subset of YAML 1.2. No third-party YAML runtime is needed.
        let scenarios = try paths.flatMap { try JSONDecoder().decode([Scenario].self,from:Data(contentsOf:$0)) }
        guard !scenarios.isEmpty, Set(scenarios.map(\.id)).count == scenarios.count else { throw CoreError.invalidScenario }
        return scenarios
    }
    public static func execute(_ scenario: Scenario, map: FixtureLayoutMap) throws -> (ScenarioResult, InputCoordinator) {
        guard scenario.events.allSatisfy({ $0.time.isFinite && $0.time >= 0 }),
              zip(scenario.events,scenario.events.dropFirst()).allSatisfy({ $0.time <= $1.time }),
              Set(scenario.events.map(\.id)).count == scenario.events.count else { throw CoreError.invalidScenario }
        let session = TypingSession(source:scenario.source,boundaryKnown:scenario.boundaryKnown,profile:scenario.profile)
        var field = VirtualField(kind:scenario.field,text:scenario.initialText,cursor:scenario.initialCursor,selectionLength:scenario.selectionLength,
                                 source:scenario.source,witnessAvailable:scenario.witnessAvailable,completion:scenario.completion)
        field.witnessLatencyMs = scenario.witnessLatencyMs
        var driver = InputCoordinator(session:session,field:field,engine:StubLayoutEngine(rules:scenario.rules,map:map),map:map,
                                      decisionDelayMs:scenario.decisionDelayMs,planStepMs:scenario.planStepMs)
        for event in scenario.events { driver.receive(event) }
        driver.finish()
        let counts = Dictionary(driver.actions.map { ($0.kind.rawValue,1) },uniquingKeysWith:+)
        var checks = ["text":driver.field.text == scenario.expectedText,"source":driver.field.source == scenario.expectedSource,
                      "event_order":driver.field.deliveredIDs == scenario.events.map(\.id),
                      "modifiers":driver.field.syntheticModifiers.allSatisfy { $0.isEmpty },
                      "drained":!driver.busy && driver.queue.isEmpty,"buffer_limit":driver.session.buffer.count <= 400]
        if let cursor = scenario.expectedCursor { checks["cursor"] = driver.field.cursor == cursor }
        if let plans = scenario.expectedPlans { checks["plan_count"] = driver.plans.count == plans }
        if let cancellations = scenario.expectedCancellations { checks["cancellations"] = driver.cancellations == cancellations }
        for action in scenario.requiredActions { checks["action_"+action.rawValue] = counts[action.rawValue,default:0] > 0 }
        let result = ScenarioResult(id:scenario.id,category:scenario.category,passed:checks.values.allSatisfy { $0 },checks:checks,
                                    actions:counts,events:scenario.events.count,plans:driver.plans.count,cancellations:driver.cancellations)
        return (result,driver)
    }
    public static func run(_ scenarios: [Scenario], map: FixtureLayoutMap) throws -> SimulationReport {
        let results = try scenarios.map { try execute($0,map:map).0 }
        return SimulationReport(scenarios:results.count,passed:results.filter(\.passed).count,failed:results.filter { !$0.passed }.map(\.id),results:results)
    }
}
