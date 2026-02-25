import Foundation
import MiniDockerCore
import Observation

@MainActor
@Observable
final class ReadinessViewModel {
    private let evaluator: ReadinessEvaluator
    private let buffer: LogRingBuffer
    private let engine: any EngineAdapter
    let containerId: String

    var rule: ReadinessRule?
    var result: ReadinessResult?
    var isEvaluating: Bool = false
    var errorMessage: String?
    var healthStatus: ContainerHealthStatus?

    var editingMode: ReadinessMode = .healthOnly
    var editingRegexPattern: String = ""
    var editingMustMatchCount: Int = 1
    var editingWindowStartPolicy: ReadinessWindowStartPolicy = .containerStart

    private var evaluationTask: Task<Void, Never>?

    init(
        engine: any EngineAdapter,
        buffer: LogRingBuffer,
        containerId: String,
        evaluator: ReadinessEvaluator = ReadinessEvaluator()
    ) {
        self.engine = engine
        self.buffer = buffer
        self.containerId = containerId
        self.evaluator = evaluator
    }

    // MARK: - Rule Building

    func buildRule() -> ReadinessRule {
        let regexPattern: String?
        switch editingMode {
        case .healthOnly:
            regexPattern = nil
        case .regexOnly, .healthThenRegex:
            regexPattern = editingRegexPattern.isEmpty ? nil : editingRegexPattern
        }

        return ReadinessRule(
            mode: editingMode,
            regexPattern: regexPattern,
            mustMatchCount: max(1, editingMustMatchCount),
            windowStartPolicy: editingWindowStartPolicy
        )
    }

    // MARK: - Evaluation

    func evaluate() async {
        isEvaluating = true
        errorMessage = nil

        let builtRule = buildRule()
        rule = builtRule

        do {
            let detail = try await engine.inspectContainer(id: containerId)
            healthStatus = detail.healthDetail?.status

            let logEntries = buffer.entries(forContainer: containerId)
            let windowStart = computeWindowStart(detail: detail)

            result = try evaluator.evaluate(
                rule: builtRule,
                healthStatus: healthStatus,
                logEntries: logEntries,
                windowStart: windowStart
            )
        } catch {
            errorMessage = "Evaluation failed: \(error.localizedDescription)"
        }

        isEvaluating = false
    }

    // MARK: - Polling

    func startPolling(interval: TimeInterval = 5.0) {
        stopPolling()
        let nanoseconds = UInt64(interval * 1_000_000_000)
        evaluationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await evaluate()
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
        }
    }

    func stopPolling() {
        evaluationTask?.cancel()
        evaluationTask = nil
    }

    // MARK: - Window Start Computation

    func computeWindowStart(detail: ContainerDetail?) -> Date {
        switch editingWindowStartPolicy {
        case .containerStart:
            return detail?.summary.startedAt ?? Date.distantPast
        case .actionDispatch:
            return Date()
        case .firstLogEntry:
            let entries = buffer.entries(forContainer: containerId)
            return entries.first?.timestamp ?? Date.distantPast
        }
    }
}
