import Foundation
import XCTest

@testable import VividHomeCore

/// Section 14.1 is the second thing the app and the PC agree on, so the file
/// list, the resume rule and the two answers are checked against the document.
final class SessionUploadTests: XCTestCase {
  private var documents: URL!

  override func setUpWithError() throws {
    documents = FileManager.default.temporaryDirectory
      .appendingPathComponent("vividhome-upload-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let documents, FileManager.default.fileExists(atPath: documents.path) {
      try FileManager.default.removeItem(at: documents)
    }
  }

  private func write(_ relative: String, under root: URL, bytes: Int) throws {
    let url = root.appendingPathComponent(relative)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0x41, count: bytes).write(to: url)
  }

  private func makeSession() throws -> (SessionLayout, URL) {
    let project = documents.appendingPathComponent("sessions/our-house", isDirectory: true)
    let layout = SessionLayout(
      root: project.appendingPathComponent("20261103-141502_main_kitchen_k3x7qa", isDirectory: true))
    try layout.createDirectories()
    try write("manifest.json", under: layout.root, bytes: 300)
    try write("frames.jsonl", under: layout.root, bytes: 1200)
    try write("rgb/000001.jpg", under: layout.root, bytes: 5000)
    try write("depth/000001.f32", under: layout.root, bytes: 196_608)
    try write("conf/000001.u8", under: layout.root, bytes: 49152)
    try write("mesh.obj", under: layout.root, bytes: 70)
    // Never sent: the pipeline's folder, and dotted names.
    try write("derived/validate.json", under: layout.root, bytes: 10)
    try write("derived/thumbs/000001.jpg", under: layout.root, bytes: 10)
    try write(".DS_Store", under: layout.root, bytes: 10)
    try write("rgb/.hidden", under: layout.root, bytes: 10)
    let plans = project.appendingPathComponent("plans", isDirectory: true)
    try write("main.png", under: plans, bytes: 2000)
    try write("main.json", under: plans, bytes: 400)
    try write("main.source.pdf", under: plans, bytes: 9000)
    try write(".stray", under: plans, bytes: 1)
    return (layout, plans)
  }

  func testEverySessionFileIsListedAndNothingOfThePipelinesIs() throws {
    let (layout, plans) = try makeSession()
    let files = try SessionUpload.files(of: layout, plans: plans)
    XCTAssertEqual(
      files.map(\.path),
      [
        "conf/000001.u8", "depth/000001.f32", "frames.jsonl", "manifest.json", "mesh.obj",
        "plans/main.json", "plans/main.png", "plans/main.source.pdf", "rgb/000001.jpg",
      ])
    XCTAssertEqual(files.first { $0.path == "rgb/000001.jpg" }?.bytes, 5000)
    XCTAssertEqual(files.first { $0.path == "plans/main.png" }?.bytes, 2000)
    XCTAssertEqual(SessionUpload.totalBytes(files), 300 + 1200 + 5000 + 196_608 + 49152 + 70 + 2000 + 400 + 9000)
    XCTAssertTrue(files.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
  }

  func testTheCapturesOwnPlacementGoesWithItAndNoOtherSessions() throws {
    let (layout, plans) = try makeSession()
    let alignments = plans.deletingLastPathComponent().appendingPathComponent("alignments", isDirectory: true)
    try write("20261103-141502_main_kitchen_k3x7qa.json", under: alignments, bytes: 640)
    try write("20261104-090000_upper_hall_bbbbbb.json", under: alignments, bytes: 600)
    let files = try SessionUpload.files(of: layout, plans: plans, alignments: alignments)
    XCTAssertEqual(
      files.filter { $0.path.hasPrefix("alignments/") }.map(\.path),
      ["alignments/20261103-141502_main_kitchen_k3x7qa.json"])
    XCTAssertEqual(files.first { $0.path.hasPrefix("alignments/") }?.bytes, 640)
    XCTAssertEqual(try SessionUpload.files(of: layout, plans: plans, alignments: nil).filter { $0.path.hasPrefix("alignments/") }.count, 0)
  }

  func testWithoutAPlansFolderOnlyTheSessionGoes() throws {
    let (layout, _) = try makeSession()
    let files = try SessionUpload.files(of: layout, plans: nil)
    XCTAssertFalse(files.contains { $0.path.hasPrefix("plans/") })
    XCTAssertEqual(files.count, 6)
    let missing = documents.appendingPathComponent("nowhere/plans")
    XCTAssertEqual(try SessionUpload.files(of: layout, plans: missing).count, 6)
  }

  func testTheServersPathRuleIsMirrored() {
    for good in ["manifest.json", "rgb/000123.jpg", "plans/main.source.pdf", "mesh_classes.u8", "log.txt"] {
      XCTAssertTrue(SessionUpload.isSendable(good), good)
    }
    for bad in [
      "", "derived/validate.json", "a/b/c.jpg", ".hidden", "rgb/.hidden", "rgb/", "/rgb/x.jpg",
      "rgb//x.jpg", "../x", "rgb/..", "rgb/00 01.jpg", "rgb/ü.jpg", "rgb/0001;rm.jpg",
    ] {
      XCTAssertFalse(SessionUpload.isSendable(bad), bad)
    }
  }

  func testAFileTheInboxAlreadyHoldsAtTheSameSizeIsNotSentAgain() throws {
    let (layout, plans) = try makeSession()
    let files = try SessionUpload.files(of: layout, plans: plans)
    let listing = SessionUpload.Listing(
      sessionID: "20261103-141502_main_kitchen_k3x7qa", state: "partial",
      files: ["rgb/000001.jpg": 5000, "manifest.json": 299, "plans/main.png": 2000])
    let remaining = SessionUpload.remaining(files, given: listing)
    XCTAssertFalse(remaining.contains { $0.path == "rgb/000001.jpg" })
    XCTAssertFalse(remaining.contains { $0.path == "plans/main.png" })
    XCTAssertTrue(remaining.contains { $0.path == "manifest.json" }, "a size mismatch is sent again")
    XCTAssertEqual(remaining.count, files.count - 2)
    XCTAssertEqual(SessionUpload.remaining(files, given: .init(sessionID: "x", state: "none", files: [:])), files)
  }

  func testTheDocumentedAnswersDecode() throws {
    let listing = """
      {"session_id": "20261103-141502_main_kitchen_k3x7qa", "state": "partial",
       "files": {"manifest.json": 812, "rgb/000000.jpg": 311204}, "later": true}
      """
    let decoded = try JSONDecoder().decode(SessionUpload.Listing.self, from: Data(listing.utf8))
    XCTAssertEqual(decoded.state, "partial")
    XCTAssertFalse(decoded.isIngested)
    XCTAssertEqual(decoded.files["rgb/000000.jpg"], 311204)
    let newer = try JSONDecoder().decode(
      SessionUpload.Listing.self,
      from: Data(#"{"session_id": "x", "state": "quarantined", "files": {}}"#.utf8))
    XCTAssertEqual(newer.state, "quarantined", "a word this build does not know still decodes")

    let receipt = """
      {"session_id": "20261103-141502_main_kitchen_k3x7qa", "ingested": true, "validated": true,
       "destination": "sessions/our-house/20261103-141502_main_kitchen_k3x7qa",
       "errors": [], "warnings": 1,
       "plans": [{"level": "main", "imported": true, "reason": "copied from beside the session"}]}
      """
    let good = try JSONDecoder().decode(SessionUpload.Receipt.self, from: Data(receipt.utf8))
    XCTAssertTrue(good.validated)
    XCTAssertEqual(good.summary, "On the PC and validated; plan for main imported.")

    let failed = SessionUpload.Receipt(
      sessionID: "x", ingested: true, validated: false, destination: "sessions/p/x",
      errors: ["rule 3: rgb/000004.jpg is missing", "rule 3: depth/000004.f32 is missing"],
      warnings: 0, plans: [])
    XCTAssertEqual(
      failed.summary,
      "On the PC, but validation failed (2 errors). rule 3: rgb/000004.jpg is missing")

    let refusal = try JSONDecoder().decode(
      SessionUpload.Refusal.self, from: Data(#"{"error": "the pairing code is missing or wrong"}"#.utf8))
    XCTAssertEqual(refusal.error, "the pairing code is missing or wrong")
  }
}
