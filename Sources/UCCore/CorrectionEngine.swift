import Foundation

public struct CorrectionRequest: Sendable {
    public var strokes: [Stroke]
    public var token: String
    public var context: [String]
    public var start: Int
    public var epoch: Int
    public var source: String
    public var trailing: KeyEvent?
    public var soft: Bool
    public var manual: Bool
    public var profile: Profile
}
public enum CorrectionDecision: Sendable, Equatable {
    case replace(String, source: String?)
    case deferred(String, source: String?)
    case keep
}
public protocol CorrectionEngine: Sendable {
    func decide(_ request: CorrectionRequest) -> CorrectionDecision
    func candidates(_ request: CorrectionRequest) -> [CorrectionDecision]
}
extension CorrectionEngine {
    public func candidates(_ request: CorrectionRequest) -> [CorrectionDecision] { [decide(request)] }
}
public struct KeepEngine: CorrectionEngine {
    public init() {}
    public func decide(_ request: CorrectionRequest) -> CorrectionDecision { .keep }
}
public struct StubRule: Codable, Sendable {
    public var input: String
    public var replacement: String?
    public var source: String?
    public var deferred: Bool
    public var context: String?
    public var alternatives: [String]?
    public init(input: String, replacement: String? = nil, source: String? = nil, deferred: Bool = false, context: String? = nil, alternatives: [String]? = nil) {
        self.input = input; self.replacement = replacement; self.source = source; self.deferred = deferred; self.context = context
        self.alternatives = alternatives
    }
}
/// Test data are supplied by the caller. There are no word-specific rules in production code.
public struct StubLayoutEngine: CorrectionEngine {
    public let rules: [StubRule]
    public let converter: LayoutConverter
    public init(rules: [StubRule], map: any KeyLayoutMap) { self.rules = rules; converter = LayoutConverter(map: map) }
    public func decide(_ request: CorrectionRequest) -> CorrectionDecision {
        guard let rule = rules.first(where: { $0.input == request.token && ($0.context == nil || request.context.last == $0.context) }) else { return .keep }
        let replacement: String?
        if let source = rule.source { replacement = converter.convert(request.strokes, to: source) }
        else { replacement = rule.replacement }
        guard let replacement else { return .keep }
        if let target = rule.source, TokenRules.english(target), !TokenRules.english(request.source), !request.profile.reverseLayout { return .keep }
        return rule.deferred ? .deferred(replacement, source: rule.source) : .replace(replacement, source: rule.source)
    }
    public func candidates(_ request: CorrectionRequest) -> [CorrectionDecision] {
        let first = decide(request)
        let alternatives = rules.first { $0.input == request.token && ($0.context == nil || request.context.last == $0.context) }?.alternatives ?? []
        return [first] + alternatives.map { .replace($0, source: nil) }
    }
}

public enum TokenRules {
    public static func english(_ source: String) -> Bool { source == "en" || source == "us" }
    public static func simpleSource(_ source: String) -> Bool { english(source) || source == "ru" || source == "ru-pc" }
    public static func eligible(_ token: String, source: String, sentenceStart: Bool, inCode: Bool, manual: Bool = false) -> Bool {
        guard !token.isEmpty, !inCode, simpleSource(source) else { return false }
        let letters = token.filter(\.isLetter)
        guard !letters.isEmpty, !token.contains(where: { $0.isNumber }),
              !token.contains(where: { "_@#\\".contains($0) }), !token.contains("://") else { return false }
        let hasLatin = letters.unicodeScalars.contains { (65...90).contains($0.value) || (97...122).contains($0.value) }
        let hasCyrillic = letters.unicodeScalars.contains { (0x400...0x52f).contains($0.value) }
        guard !(hasLatin && hasCyrillic) else { return false }
        if english(source) {
            // A terminal slash/question mark is Russian punctuation. Interior slash is a path.
            let body = token.last == "/" || token.last == "?" ? String(token.dropLast()) : token
            guard !body.contains("/"), !body.contains(".") else { return false }
            guard body.allSatisfy({ $0.isASCII && ($0.isLetter || "-`[];',~{}:\"<>".contains($0)) }) else { return false }
            let lowerUpper = zip(letters, letters.dropFirst()).contains { $0.isLowercase && $1.isUppercase }
            return !lowerUpper && hasLatin
        }
        guard !token.contains("."), !token.contains("/"), !token.contains("`"), hasCyrillic else { return false }
        guard token.allSatisfy({ $0.isLetter || "-'’".contains($0) }) else { return false }
        if manual { return true }
        if letters.count <= 2 { return false }
        if letters == letters.uppercased() && letters.count <= 5 { return false }
        if letters.first?.isUppercase == true && !sentenceStart { return false }
        return true
    }
}
