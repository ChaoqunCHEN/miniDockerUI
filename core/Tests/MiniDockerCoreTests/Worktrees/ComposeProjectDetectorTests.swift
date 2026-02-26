import Foundation
@testable import MiniDockerCore
import XCTest

final class ComposeProjectDetectorTests: XCTestCase {
    private let detector = ComposeProjectDetector()

    // MARK: - Helpers

    private func makeContainer(
        id: String = UUID().uuidString,
        name: String = "test",
        labels: [String: String] = [:]
    ) -> ContainerSummary {
        ContainerSummary(
            engineContextId: "local",
            id: id,
            name: name,
            image: "test:latest",
            status: "Up 5 minutes",
            health: nil,
            labels: labels,
            startedAt: nil
        )
    }

    private func composeLabels(
        project: String,
        service: String = "web",
        workingDir: String = "/app",
        configFiles: String = "/app/docker-compose.yml"
    ) -> [String: String] {
        [
            ComposeProjectDetector.projectLabelKey: project,
            ComposeProjectDetector.serviceLabelKey: service,
            ComposeProjectDetector.workingDirLabelKey: workingDir,
            ComposeProjectDetector.configFilesLabelKey: configFiles,
        ]
    }

    // MARK: - Tests

    func testDetectSingleProject() {
        let containers = [
            makeContainer(id: "c1", name: "proj-web-1", labels: composeLabels(project: "proj", service: "web")),
            makeContainer(id: "c2", name: "proj-db-1", labels: composeLabels(project: "proj", service: "db")),
        ]

        let projects = detector.detectProjects(from: containers)

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].projectName, "proj")
        XCTAssertEqual(Set(projects[0].containerIds), Set(["c1", "c2"]))
    }

    func testDetectMultipleProjects() {
        let containers = [
            makeContainer(id: "c1", labels: composeLabels(project: "alpha", service: "web")),
            makeContainer(id: "c2", labels: composeLabels(project: "beta", service: "api")),
        ]

        let projects = detector.detectProjects(from: containers)

        XCTAssertEqual(projects.count, 2)
        XCTAssertEqual(projects[0].projectName, "alpha")
        XCTAssertEqual(projects[1].projectName, "beta")
    }

    func testIgnoresContainersWithoutComposeLabels() {
        let containers = [
            makeContainer(id: "c1", labels: composeLabels(project: "proj", service: "web")),
            makeContainer(id: "c2", labels: ["some.other.label": "value"]),
            makeContainer(id: "c3", labels: [:]),
        ]

        let projects = detector.detectProjects(from: containers)

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].containerIds, ["c1"])
    }

    func testEmptyContainerList() {
        let projects = detector.detectProjects(from: [])
        XCTAssertTrue(projects.isEmpty)
    }

    func testExtractsWorkingDirectory() {
        let containers = [
            makeContainer(labels: composeLabels(project: "myproj", workingDir: "/home/user/myproj")),
        ]

        let projects = detector.detectProjects(from: containers)

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].workingDirectory, "/home/user/myproj")
    }

    func testExtractsConfigFiles() {
        let containers = [
            makeContainer(labels: composeLabels(
                project: "myproj",
                configFiles: "/app/docker-compose.yml,/app/docker-compose.override.yml"
            )),
        ]

        let projects = detector.detectProjects(from: containers)

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].configFiles, [
            "/app/docker-compose.yml",
            "/app/docker-compose.override.yml",
        ])
    }

    func testExtractsServiceNames() {
        let containers = [
            makeContainer(id: "c1", labels: composeLabels(project: "proj", service: "web")),
            makeContainer(id: "c2", labels: composeLabels(project: "proj", service: "db")),
            makeContainer(id: "c3", labels: composeLabels(project: "proj", service: "web")),
        ]

        let projects = detector.detectProjects(from: containers)

        XCTAssertEqual(projects.count, 1)
        // "web" appears twice but should be deduplicated
        XCTAssertEqual(projects[0].serviceNames, ["web", "db"])
    }

    func testHandlesMissingWorkingDirLabel() {
        let labels: [String: String] = [
            ComposeProjectDetector.projectLabelKey: "proj",
            ComposeProjectDetector.serviceLabelKey: "web",
            // No working_dir label
        ]
        let containers = [makeContainer(labels: labels)]

        let projects = detector.detectProjects(from: containers)

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].workingDirectory, "")
    }

    func testProjectsSortedByName() {
        let containers = [
            makeContainer(labels: composeLabels(project: "zeta")),
            makeContainer(labels: composeLabels(project: "alpha")),
            makeContainer(labels: composeLabels(project: "mango")),
        ]

        let projects = detector.detectProjects(from: containers)

        XCTAssertEqual(projects.map(\.projectName), ["alpha", "mango", "zeta"])
    }
}
