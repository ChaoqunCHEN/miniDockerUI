import Foundation
@testable import MiniDockerCore
import XCTest

final class WorktreeMappingValidatorTests: XCTestCase {
    private let validator = WorktreeMappingValidator()

    private func validMapping(
        id: String = "m1",
        repoRoot: String = "/repo",
        anchorPath: String = "/repo/anchor",
        targetId: String = "container-1",
        targetType: WorktreeTargetType = .container,
        restartPolicy: WorktreeRestartPolicy = .always
    ) -> WorktreeMapping {
        WorktreeMapping(
            id: id,
            repoRoot: repoRoot,
            anchorPath: anchorPath,
            targetType: targetType,
            targetId: targetId,
            restartPolicy: restartPolicy
        )
    }

    // MARK: - Happy Path

    func testValidMappingPasses() throws {
        XCTAssertNoThrow(try validator.validate(validMapping()))
    }

    func testValidCollectionPasses() throws {
        let mappings = [
            validMapping(id: "m1"),
            validMapping(id: "m2"),
        ]
        XCTAssertNoThrow(try validator.validateAll(mappings))
    }

    func testComposeProjectTargetValid() throws {
        let mapping = validMapping(targetType: .composeProject)
        XCTAssertNoThrow(try validator.validate(mapping))
    }

    // MARK: - Single Mapping Errors

    func testEmptyIdFails() {
        XCTAssertThrowsError(try validator.validate(validMapping(id: ""))) { error in
            guard case WorktreeValidationError.emptyMappingId = error else {
                XCTFail("Expected emptyMappingId, got \(error)")
                return
            }
        }
    }

    func testRelativeRepoRootFails() {
        XCTAssertThrowsError(try validator.validate(validMapping(repoRoot: "relative/path", anchorPath: "/abs/path"))) { error in
            guard case WorktreeValidationError.repoRootNotAbsolute = error else {
                XCTFail("Expected repoRootNotAbsolute, got \(error)")
                return
            }
        }
    }

    func testRelativeAnchorPathFails() {
        XCTAssertThrowsError(try validator.validate(validMapping(anchorPath: "relative/anchor"))) { error in
            guard case WorktreeValidationError.anchorPathNotAbsolute = error else {
                XCTFail("Expected anchorPathNotAbsolute, got \(error)")
                return
            }
        }
    }

    func testAnchorOutsideRepoFails() {
        XCTAssertThrowsError(try validator.validate(validMapping(repoRoot: "/repo", anchorPath: "/other/path"))) { error in
            guard case WorktreeValidationError.anchorPathOutsideRepo = error else {
                XCTFail("Expected anchorPathOutsideRepo, got \(error)")
                return
            }
        }
    }

    func testEmptyTargetIdFails() {
        XCTAssertThrowsError(try validator.validate(validMapping(targetId: ""))) { error in
            guard case WorktreeValidationError.emptyTargetId = error else {
                XCTFail("Expected emptyTargetId, got \(error)")
                return
            }
        }
    }

    // MARK: - Collection Errors

    func testDuplicateIdInCollection() {
        let mappings = [
            validMapping(id: "dup"),
            validMapping(id: "dup"),
        ]
        XCTAssertThrowsError(try validator.validateAll(mappings)) { error in
            guard case WorktreeValidationError.duplicateMappingId = error else {
                XCTFail("Expected duplicateMappingId, got \(error)")
                return
            }
        }
    }

    // MARK: - allErrors

    func testAllErrorsReturnsSingle() {
        let mapping = validMapping(id: "")
        let errors = validator.allErrors(for: mapping)
        XCTAssertTrue(errors.contains(where: {
            if case .emptyMappingId = $0 { return true }
            return false
        }))
    }

    func testAllErrorsReturnsMultiple() {
        let mapping = WorktreeMapping(
            id: "",
            repoRoot: "relative",
            anchorPath: "also-relative",
            targetType: .container,
            targetId: "",
            restartPolicy: .always
        )
        let errors = validator.allErrors(for: mapping)
        XCTAssertGreaterThanOrEqual(errors.count, 3)
    }

    func testAllErrorsCollectionDuplicates() {
        let mappings = [
            validMapping(id: "dup"),
            validMapping(id: "dup"),
        ]
        let errors = validator.allErrors(forAll: mappings)
        XCTAssertTrue(errors.contains(where: {
            if case .duplicateMappingId = $0 { return true }
            return false
        }))
    }

    // MARK: - Edge Cases

    func testTrailingSlashNormalized() throws {
        let mapping = validMapping(repoRoot: "/repo/root/", anchorPath: "/repo/root/sub")
        XCTAssertNoThrow(try validator.validate(mapping))
    }
}
