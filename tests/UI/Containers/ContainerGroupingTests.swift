import MiniDockerCore
import XCTest

final class ContainerGroupingTests: XCTestCase {
    private func makeContainer(
        id: String, name: String, status: String = "Up",
        engineContextId: String = "local"
    ) -> ContainerSummary {
        ContainerSummary(
            engineContextId: engineContextId, id: id, name: name,
            image: "alpine:3.20", status: status, health: nil,
            labels: [:], startedAt: nil
        )
    }

    private func key(_ container: ContainerSummary) -> String {
        ContainerGrouper.containerKey(for: container)
    }

    func testGroupContainersWithNoFavorites() {
        let containers = [
            makeContainer(id: "1", name: "web", status: "Up"),
            makeContainer(id: "2", name: "db", status: "Exited (0)"),
        ]
        let groups = ContainerGrouper.group(
            containers: containers, favoriteKeys: [], keyForContainer: key
        )
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].title, "Running")
        XCTAssertEqual(groups[1].title, "Stopped")
    }

    func testGroupContainersWithFavorites() {
        let web = makeContainer(id: "1", name: "web", status: "Up")
        let db = makeContainer(id: "2", name: "db", status: "Exited (0)")
        let favKeys: Set<String> = [key(web)]
        let groups = ContainerGrouper.group(
            containers: [web, db], favoriteKeys: favKeys, keyForContainer: key
        )
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].title, "Favorites")
        XCTAssertEqual(groups[0].containers.count, 1)
        XCTAssertEqual(groups[1].title, "Stopped")
    }

    func testGroupContainersAllFavorites() {
        let c1 = makeContainer(id: "1", name: "a", status: "Up")
        let c2 = makeContainer(id: "2", name: "b", status: "Exited")
        let favKeys: Set<String> = [key(c1), key(c2)]
        let groups = ContainerGrouper.group(
            containers: [c1, c2], favoriteKeys: favKeys, keyForContainer: key
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "Favorites")
        XCTAssertEqual(groups[0].containers.count, 2)
    }

    func testGroupContainersEmptyList() {
        let groups = ContainerGrouper.group(
            containers: [], favoriteKeys: [], keyForContainer: key
        )
        XCTAssertTrue(groups.isEmpty)
    }

    func testGroupContainersSortedAlphabetically() {
        let containers = [
            makeContainer(id: "1", name: "zeta", status: "Up"),
            makeContainer(id: "2", name: "alpha", status: "Up"),
            makeContainer(id: "3", name: "mid", status: "Up"),
        ]
        let groups = ContainerGrouper.group(
            containers: containers, favoriteKeys: [], keyForContainer: key
        )
        let names = groups[0].containers.map(\.name)
        XCTAssertEqual(names, ["alpha", "mid", "zeta"])
    }

    func testGroupContainersFavoritesMixedStates() {
        let running = makeContainer(id: "1", name: "web", status: "Up")
        let stopped = makeContainer(id: "2", name: "db", status: "Exited")
        let favKeys: Set<String> = [key(running), key(stopped)]
        let groups = ContainerGrouper.group(
            containers: [running, stopped], favoriteKeys: favKeys, keyForContainer: key
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "Favorites")
        XCTAssertEqual(groups[0].containers.count, 2)
    }

    func testGroupContainersFavoriteKeyMismatchIgnored() {
        let c1 = makeContainer(id: "1", name: "web", status: "Up")
        let groups = ContainerGrouper.group(
            containers: [c1], favoriteKeys: ["nonexistent:key"], keyForContainer: key
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "Running")
    }
}
