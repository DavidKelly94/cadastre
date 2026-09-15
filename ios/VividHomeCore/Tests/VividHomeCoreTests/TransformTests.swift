import Foundation
import XCTest

@testable import VividHomeCore

final class TransformTests: XCTestCase {
  /// Rotation of `angle` about `+y`, built directly in column-major order.
  private func rotationY(_ angle: Double) -> Transform {
    let c = cos(angle)
    let s = sin(angle)
    return Transform(elements: [
      c, 0, -s, 0,
      0, 1, 0, 0,
      s, 0, c, 0,
      0, 0, 0, 1,
    ])!
  }

  private func assertClose(
    _ lhs: Transform, _ rhs: Transform, accuracy: Double = 1e-12,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    for index in 0..<Transform.elementCount {
      XCTAssertEqual(lhs.elements[index], rhs.elements[index], accuracy: accuracy,
        "element \(index)", file: file, line: line)
    }
  }

  func testInitRejectsWrongLength() {
    XCTAssertNil(Transform(elements: []))
    XCTAssertNil(Transform(elements: [Double](repeating: 0, count: 15)))
    XCTAssertNotNil(Transform(elements: [Double](repeating: 0, count: 16)))
  }

  func testColumnMajorIndexing() {
    // Elements numbered 0...15 in storage order: index = column * 4 + row.
    let t = Transform(elements: (0..<16).map(Double.init))!
    XCTAssertEqual(t[0, 0], 0)
    XCTAssertEqual(t[1, 0], 1)
    XCTAssertEqual(t[0, 1], 4)
    XCTAssertEqual(t[3, 3], 15)
  }

  func testTranslationLivesAtTwelveThirteenFourteen() {
    let t = Transform.translation(Vector3(1.5, -2.0, 3.25))
    XCTAssertEqual(t.elements[12], 1.5)
    XCTAssertEqual(t.elements[13], -2.0)
    XCTAssertEqual(t.elements[14], 3.25)
    XCTAssertEqual(t.translation, Vector3(1.5, -2.0, 3.25))
  }

  func testIdentityIsAMultiplicativeIdentity() {
    let t = rotationY(0.7) * Transform.translation(Vector3(1, 2, 3))
    assertClose(t * .identity, t)
    assertClose(.identity * t, t)
  }

  func testMultiplyAppliesRightHandSideFirst() {
    // Translating then rotating must not equal rotating then translating.
    let rotate = rotationY(.pi / 2)
    let translate = Transform.translation(Vector3(1, 0, 0))
    let rotateThenTranslate = translate * rotate
    let translateThenRotate = rotate * translate

    // `translate * rotate` leaves the translation column untouched.
    XCTAssertEqual(rotateThenTranslate.translation, Vector3(1, 0, 0))
    // `rotate * translate` turns +x into -z for a +90 degree rotation about +y.
    XCTAssertEqual(translateThenRotate.translation.x, 0, accuracy: 1e-12)
    XCTAssertEqual(translateThenRotate.translation.z, -1, accuracy: 1e-12)
  }

  func testInverseRoundTrips() {
    let t = rotationY(0.4) * Transform.translation(Vector3(-1, 2, 0.5))
    let inverse = t.inverted()
    XCTAssertNotNil(inverse)
    assertClose(t * inverse!, .identity, accuracy: 1e-12)
    assertClose(inverse! * t, .identity, accuracy: 1e-12)
  }

  func testInverseOfANonRigidTransformRoundTrips() {
    // Alignment transforms are not guaranteed rigid, so scaling must invert too.
    let scale = Transform(elements: [
      2, 0, 0, 0,
      0, 4, 0, 0,
      0, 0, 0.5, 0,
      1, 2, 3, 1,
    ])!
    assertClose(scale * scale.inverted()!, .identity, accuracy: 1e-12)
  }

  func testSingularTransformHasNoInverse() {
    XCTAssertNil(Transform(elements: [Double](repeating: 0, count: 16))!.inverted())
  }

  func testRotationAngleBetweenTransforms() {
    XCTAssertEqual(Transform.identity.rotationAngle(to: .identity), 0, accuracy: 1e-12)
    XCTAssertEqual(
      Transform.identity.rotationAngle(to: rotationY(.pi / 6)), .pi / 6, accuracy: 1e-12)
    XCTAssertEqual(
      rotationY(0.3).rotationAngle(to: rotationY(0.3 + 0.2)), 0.2, accuracy: 1e-12)
  }

  func testRotationAngleIgnoresTranslation() {
    let a = Transform.translation(Vector3(10, -5, 3))
    XCTAssertEqual(Transform.identity.rotationAngle(to: a), 0, accuracy: 1e-12)
  }

  func testRotationAngleIsUnsignedAndSymmetric() {
    let a = rotationY(0.9)
    XCTAssertEqual(a.rotationAngle(to: .identity), 0.9, accuracy: 1e-12)
    XCTAssertEqual(Transform.identity.rotationAngle(to: a), 0.9, accuracy: 1e-12)
  }

  func testOrthonormalRotationCheck() {
    XCTAssertTrue(Transform.identity.hasOrthonormalRotation())
    XCTAssertTrue(rotationY(1.1).hasOrthonormalRotation())
    XCTAssertTrue(Transform.translation(Vector3(3, 4, 5)).hasOrthonormalRotation())

    let scaled = Transform(elements: [
      2, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ])!
    XCTAssertFalse(scaled.hasOrthonormalRotation())

    // A reflection is orthonormal but has determinant -1, so it must be rejected.
    let reflection = Transform(elements: [
      -1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ])!
    XCTAssertFalse(reflection.hasOrthonormalRotation())
  }
}
