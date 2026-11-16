import Flutter
import UIKit
import XCTest

class RunnerTests: XCTestCase {

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

  /// BL-35: a push can launch the app while the phone is locked, when UIKit
  /// cannot read its data-protected state restoration files, and UIKit then
  /// ended the app at the next unlock. The app restores nothing through
  /// UIKit, so it opts out of saving and restoring that state. Restore reads
  /// the coder that save wrote, so FlutterAppDelegate's own timestamp check
  /// cannot make it pass.
  func testBL35AppDelegateOptsOutOfUIKitSecureStateRestoration() throws {
    let delegate = try XCTUnwrap(UIApplication.shared.delegate)
    let coder = NSKeyedArchiver(requiringSecureCoding: true)
    XCTAssertEqual(
      delegate.application?(UIApplication.shared, shouldSaveSecureApplicationState: coder),
      false
    )
    coder.finishEncoding()
    let decoder = try NSKeyedUnarchiver(forReadingFrom: coder.encodedData)
    XCTAssertEqual(
      delegate.application?(UIApplication.shared, shouldRestoreSecureApplicationState: decoder),
      false
    )
  }

}
