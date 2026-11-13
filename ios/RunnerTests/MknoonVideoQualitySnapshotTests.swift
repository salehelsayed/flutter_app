import XCTest

@testable import Runner

final class MknoonVideoQualitySnapshotTests: XCTestCase {
  private func net(
    satisfied: Bool = true, wifi: Bool = false, cellular: Bool = false,
    wired: Bool = false, constrained: Bool = false, expensive: Bool = false
  ) -> MknoonVideoQualitySnapshot.NetworkInputs {
    MknoonVideoQualitySnapshot.NetworkInputs(
      satisfied: satisfied, wifi: wifi, cellular: cellular, wired: wired,
      constrained: constrained, expensive: expensive
    )
  }

  func testUnsatisfiedPathIsUnknownNotUnrestricted() {
    let snapshot = MknoonVideoQualitySnapshot.build(network: .unknown, thermal: .nominal)
    XCTAssertEqual(snapshot["networkClass"] as? String, "unknown")
    XCTAssertTrue(snapshot["lowDataMode"] is NSNull)
    XCTAssertTrue(snapshot["metered"] is NSNull)
    XCTAssertEqual(Set(snapshot.keys), ["networkClass", "lowDataMode", "metered", "thermalState"])
  }

  func testUnmeteredCellularStaysCellular() {
    let snapshot = MknoonVideoQualitySnapshot.build(network: net(cellular: true), thermal: .nominal)
    XCTAssertEqual(snapshot["networkClass"] as? String, "cellular")
    XCTAssertEqual(snapshot["metered"] as? Bool, false)
  }

  func testLowDataAndExpensiveFlags() {
    let snapshot = MknoonVideoQualitySnapshot.build(
      network: net(wifi: true, constrained: true, expensive: true), thermal: .nominal)
    XCTAssertEqual(snapshot["networkClass"] as? String, "wifi")
    XCTAssertEqual(snapshot["lowDataMode"] as? Bool, true)
    XCTAssertEqual(snapshot["metered"] as? Bool, true)
  }

  func testWiredIsOtherAndUnknownTransportIsUnknown() {
    XCTAssertEqual(MknoonVideoQualitySnapshot.networkClass(net(wired: true)), "other")
    XCTAssertEqual(MknoonVideoQualitySnapshot.networkClass(net()), "unknown")
  }

  func testThermalMapping() {
    XCTAssertEqual(MknoonVideoQualitySnapshot.thermalState(.nominal), "nominal")
    XCTAssertEqual(MknoonVideoQualitySnapshot.thermalState(.fair), "elevated")
    XCTAssertEqual(MknoonVideoQualitySnapshot.thermalState(.serious), "serious")
    XCTAssertEqual(MknoonVideoQualitySnapshot.thermalState(.critical), "critical")
  }
}
