import Foundation
public protocol NeuralScorer: Sendable {
    func score(candidates: [String], context: [String]) async throws -> [Double]
}
