import Foundation
import MiniDockerCore
import Observation

/// Thin editing adapter over ``ReadinessManager`` for the readiness detail view.
///
/// Local editing state lives here; actual evaluation and persistence is
/// delegated to the centralized ``ReadinessManager``.
@MainActor
@Observable
final class ReadinessViewModel {
    private let readinessManager: ReadinessManager
    let containerId: String
    let containerKey: String

    // MARK: - Editing State

    var editingMode: ReadinessMode = .healthOnly
    var editingRegexPattern: String = ""
    var editingMustMatchCount: Int = 1
    var editingWindowStartPolicy: ReadinessWindowStartPolicy = .containerStart

    var isEvaluating: Bool = false

    init(
        readinessManager: ReadinessManager,
        containerId: String,
        containerKey: String
    ) {
        self.readinessManager = readinessManager
        self.containerId = containerId
        self.containerKey = containerKey
        loadFromSavedRule()
    }

    // MARK: - Computed Properties (read from manager)

    var result: ReadinessResult? {
        readinessManager.containerStates[containerKey]?.result
    }

    var isLatched: Bool {
        readinessManager.containerStates[containerKey]?.isLatched ?? false
    }

    var errorMessage: String? {
        readinessManager.containerStates[containerKey]?.errorMessage
    }

    var hasRule: Bool {
        readinessManager.rules[containerKey] != nil
    }

    var isPolling: Bool {
        readinessManager.isPolling(forContainerKey: containerKey)
    }

    var hasUnsavedChanges: Bool {
        let defaultRule = ReadinessRule(
            mode: .healthOnly, regexPattern: nil, mustMatchCount: 1,
            windowStartPolicy: .containerStart
        )
        let savedRule = readinessManager.rules[containerKey] ?? defaultRule
        return buildRule() != savedRule
    }

    // MARK: - Rule Building

    func buildRule() -> ReadinessRule {
        // Only include regex pattern for modes that use it
        let hasRegex = editingMode != .healthOnly && !editingRegexPattern.isEmpty
        let regexPattern: String? = hasRegex ? editingRegexPattern : nil

        return ReadinessRule(
            mode: editingMode,
            regexPattern: regexPattern,
            mustMatchCount: max(1, editingMustMatchCount),
            windowStartPolicy: editingWindowStartPolicy
        )
    }

    // MARK: - Save / Remove

    func saveRule() {
        let rule = buildRule()
        readinessManager.saveRule(rule, forContainerKey: containerKey)
    }

    func removeRule() {
        readinessManager.removeRule(forContainerKey: containerKey)
        resetEditingFields()
    }

    // MARK: - Test Evaluate (one-shot for testing before saving)

    func testEvaluate() async {
        isEvaluating = true
        let rule = buildRule()
        await readinessManager.evaluateOnce(
            containerKey: containerKey,
            containerId: containerId,
            rule: rule,
            force: true
        )
        isEvaluating = false
    }

    // MARK: - Private

    private func loadFromSavedRule() {
        guard let rule = readinessManager.rules[containerKey] else { return }
        editingMode = rule.mode
        editingRegexPattern = rule.regexPattern ?? ""
        editingMustMatchCount = rule.mustMatchCount
        editingWindowStartPolicy = rule.windowStartPolicy
    }

    private func resetEditingFields() {
        editingMode = .healthOnly
        editingRegexPattern = ""
        editingMustMatchCount = 1
        editingWindowStartPolicy = .containerStart
    }
}
