import Foundation
import XCTest

@testable import Runner

final class OpaqueCallContactResolverTests: XCTestCase {
  private let handle = "223e4567-e89b-42d3-a456-426614174001"

  func testUnknownAndUnavailableMappingsUseGenericCaller() {
    let backend = MemoryOpaqueContactBackend()
    let resolver = OpaqueCallContactResolver(backend: backend, nowMs: { 10 })
    XCTAssertEqual(resolver.displayName(for: handle), "Mknoon call")
    backend.failReads = true
    XCTAssertEqual(resolver.displayName(for: handle), "Mknoon call")
  }

  func testOnlyVerifiedOpaqueMappingCanSupplyDisplayName() {
    let backend = MemoryOpaqueContactBackend()
    let resolver = OpaqueCallContactResolver(backend: backend, nowMs: { 10 })
    XCTAssertTrue(resolver.updateVerified(handle: handle, displayName: "  Alice  "))
    XCTAssertEqual(resolver.displayName(for: handle), "Alice")
    XCTAssertEqual(
      OpaqueCallContactResolver(backend: backend, nowMs: { 11 }).displayName(for: handle),
      "Alice"
    )

    XCTAssertFalse(resolver.updateVerified(handle: "Alice", displayName: "Mallory"))
    XCTAssertFalse(resolver.updateVerified(handle: handle, displayName: "Alice\nInjected"))
    XCTAssertEqual(resolver.displayName(for: handle), "Alice")
  }

  func testPublicationBoundaryRequiresCanonicalHandleAndDisplayName() {
    XCTAssertTrue(OpaqueCallContactResolver.validHandle("223e4567e89b42d3a456426614174001"))
    XCTAssertTrue(OpaqueCallContactResolver.validHandle(handle))
    XCTAssertFalse(OpaqueCallContactResolver.validHandle(handle.uppercased()))
    XCTAssertFalse(OpaqueCallContactResolver.validHandle(
      "223e4567-e89b-12d3-a456-426614174001"
    ))
    XCTAssertFalse(OpaqueCallContactResolver.validHandle(
      "223e4567-e89b-42d3-c456-426614174001"
    ))
    XCTAssertTrue(OpaqueCallContactResolver.validDisplayName("Alice"))
    XCTAssertFalse(OpaqueCallContactResolver.validDisplayName(" Alice "))
    XCTAssertFalse(OpaqueCallContactResolver.validDisplayName("Alice\nInjected"))
    XCTAssertFalse(OpaqueCallContactResolver.validDisplayName(String(repeating: "a", count: 81)))
  }

  func testBlockOrRemoveRevokesExactMappingWithoutAffectingAnother() {
    let backend = MemoryOpaqueContactBackend()
    let resolver = OpaqueCallContactResolver(backend: backend, nowMs: { 10 })
    let other = "323e4567-e89b-42d3-a456-426614174002"
    XCTAssertTrue(resolver.updateVerified(handle: handle, displayName: "Alice"))
    XCTAssertTrue(resolver.updateVerified(handle: other, displayName: "Bob"))
    XCTAssertTrue(resolver.revoke(handle: handle))
    XCTAssertEqual(resolver.displayName(for: handle), "Mknoon call")
    XCTAssertEqual(resolver.displayName(for: other), "Bob")
  }

  func testDurabilityFailureCannotPublishMemoryOnlyMapping() {
    let backend = MemoryOpaqueContactBackend()
    backend.failWrites = true
    let resolver = OpaqueCallContactResolver(backend: backend, nowMs: { 10 })
    XCTAssertFalse(resolver.updateVerified(handle: handle, displayName: "Alice"))
    XCTAssertEqual(resolver.displayName(for: handle), "Mknoon call")
  }

  func testRunnerBackendKeepsDirectoryTraversableAndMappingPrivate() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "vc205-contacts-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let resolver = OpaqueCallContactResolver(
      backend: try RunnerOpaqueCallContactFileBackend(directory: directory),
      nowMs: { 1_900_000_000_000 }
    )
    XCTAssertTrue(resolver.updateVerified(handle: handle, displayName: "Alice"))
    let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    let fileAttributes = try FileManager.default.attributesOfItem(
      atPath: directory.appendingPathComponent("opaque-contacts-v1.json").path
    )
    XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    XCTAssertEqual(
      RunnerOpaqueCallContactFileBackend.protectionType,
      .completeUntilFirstUserAuthentication
    )
  }
}

final class MemoryOpaqueContactBackend: OpaqueCallContactBackend {
  var data: Data?
  var failReads = false
  var failWrites = false

  func read() throws -> Data? {
    if failReads { throw CocoaError(.fileReadUnknown) }
    return data
  }

  func replace(with data: Data?) throws {
    if failWrites { throw CocoaError(.fileWriteUnknown) }
    self.data = data
  }
}
