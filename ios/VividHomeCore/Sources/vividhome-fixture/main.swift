import Foundation

import VividHomeCore

// Writes a session using nothing but VividHomeCore, so the pipeline's validator
// can be pointed at it.
//
// Every other test in this repository checks one side of the app/pipeline
// contract against its own idea of the other. This is the only thing that puts
// the two implementations in contact: Swift writes, Python reads, and if they
// have drifted apart CI says so instead of the first real capture saying so.
//
// It writes no JPEGs. Encoding needs CoreImage, which does not exist on Linux,
// and the images are not the part at risk — the records are.
//
// It also runs the two pieces of field maths the phone ported from the
// pipeline, the corner snap (corners.py) and the live wall coverage
// (coverage.py), on the room it just wrote, and leaves their answers in a JSON
// file beside the session for pipeline/tests/test_contract.py to hold against
// the Python's own. The ports were written blind; this is what keeps them the
// same rule.

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
  FileHandle.standardError.write(
    Data("usage: vividhome-fixture <output-directory> [<contract-json>]\n".utf8))
  exit(2)
}

let sessionID = SessionID("20261103-141502_main_kitchen_k3x7qa")!
let layout = SessionLayout(root: URL(fileURLWithPath: arguments[1]))
let contractPath =
  arguments.count >= 3
  ? URL(fileURLWithPath: arguments[2])
  : URL(fileURLWithPath: arguments[1] + "-contract.json")
try layout.createDirectories()

// The room: 4 m along x, 5 m along z, 2.4 m high, its north-west floor corner at
// the origin, as `synth.py` lays its room out. Walls, floor and ceiling as two
// triangles each, classified as section 9 says (1 wall, 2 floor, 3 ceiling).
let roomWidth = 4.0
let roomDepth = 5.0
let roomHeight = 2.4
let corners: [(label: String, x: Double, z: Double)] = [
  ("corner-nw", 0, 0), ("corner-ne", roomWidth, 0), ("corner-se", roomWidth, roomDepth),
  ("corner-sw", 0, roomDepth),
]

let colourWidth = 64
let colourHeight = 48
let depthWidth = 8
let depthHeight = 6

let intrinsics = Intrinsics(
  fx: 48.4, fy: 48.4, cx: Double(colourWidth) / 2, cy: Double(colourHeight) / 2)

/// A pose translated along +x, with an honest rotation block: the camera at
/// chest height in the middle of the room, looking down its own -z, which is
/// at the north wall.
func pose(x: Double) -> Transform {
  Transform(elements: [
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    x, 1.4, roomDepth / 2, 1,
  ])!
}

let keyframes = 5
let framesWriter = try JSONLWriter(url: layout.frames)
var stats = SessionStats()
var frames: [FrameRecord] = []

for index in 0..<keyframes {
  // Depth and confidence at exactly the sizes validation rule 3 requires.
  //
  // Plausible metres, not zeros: the format calls 0 invalid, so an all-zero map
  // would warn on rule 6 every single run, and a check that always warns is one
  // nobody reads. With real values, any warning here is a real signal.
  var depth = Data(capacity: depthWidth * depthHeight * 4)
  for _ in 0..<(depthWidth * depthHeight) {
    withUnsafeBytes(of: Float32(2.5).bitPattern.littleEndian) { depth.append(contentsOf: $0) }
  }
  let confidence = Data(repeating: 2, count: depthWidth * depthHeight)
  try depth.write(to: layout.depth(keyframe: index))
  try confidence.write(to: layout.confidence(keyframe: index))

  let paths = FrameRecord.paths(forKeyframe: index)
  let record = FrameRecord(
    index: index,
    // Relative by construction, which is why the contract job never caught
    // the app writing absolute ARFrame timestamps. See SessionTimeline.
    time: Double(index) * 0.5,
    // Five stops along the room, 0.5 m to 3.5 m, so the north wall is walked.
    poseWorldFromCamera: pose(x: 0.5 + Double(index) * 0.75),
    intrinsics: intrinsics,
    width: colourWidth,
    height: colourHeight,
    depthWidth: depthWidth,
    depthHeight: depthHeight,
    exposureDuration: 0.0083,
    exposureOffset: 0,
    tracking: .normal,
    reason: .none,
    thermal: .nominal,
    rgb: paths.rgb,
    depth: paths.depth,
    conf: paths.conf)
  try framesWriter.append(record)
  frames.append(record)
  stats.recordKeyframe(bytes: depth.count + confidence.count)
}
try framesWriter.close()

// The pipeline checks that every referenced file exists, so the colour frames
// have to be there even though this cannot encode one. Empty files would fail
// the decode check, which is exactly why the contract job skips it.
for index in 0..<keyframes {
  guard FileManager.default.createFile(atPath: layout.rgb(keyframe: index).path, contents: Data())
  else {
    FileHandle.standardError.write(Data("could not create a placeholder colour frame\n".utf8))
    exit(1)
  }
}

let markersWriter = try JSONLWriter(url: layout.markers)
try markersWriter.append(
  MarkerObservation(
    time: 0.5,
    index: 1,
    markerID: MarkerID.string(for: 12),
    poseWorldFromAnchor: pose(x: 1.0),
    tracked: true,
    physicalWidth: 0.20))
try markersWriter.close()
stats.recordMarkerObservation()

// The four corners as a thumb taps them: a few centimetres into the room and
// a little above the floor, which is what a raycast onto the mesh gives. The
// snap below should take each back to where the walls meet the floor.
let taps: [(label: String, position: Vector3)] = [
  ("corner-nw", Vector3(0.06, 0.02, 0.05)),
  ("corner-ne", Vector3(roomWidth - 0.05, 0.02, 0.04)),
  ("corner-se", Vector3(roomWidth - 0.06, 0.02, roomDepth - 0.05)),
  ("corner-sw", Vector3(0.05, 0.02, roomDepth - 0.04)),
]
let landmarksWriter = try JSONLWriter(url: layout.landmarks)
for (number, tap) in taps.enumerated() {
  try landmarksWriter.append(
    LandmarkRecord(
      time: 0.2 + Double(number) * 0.2,
      index: 0,
      label: tap.label,
      kind: .corner,
      position: tap.position,
      method: "raycast_estimated_plane"))
  stats.recordLandmark()
}
try landmarksWriter.close()

// The mesh (section 9): vertices 1-4 are the floor corners, 5-8 the same
// corners at ceiling height.
let vertices: [Vector3] = corners.map { Vector3($0.x, 0, $0.z) } + corners.map { Vector3($0.x, roomHeight, $0.z) }
let wallClass: UInt8 = 1, floorClass: UInt8 = 2, ceilingClass: UInt8 = 3
var faces: [(a: Int, b: Int, c: Int, classification: UInt8)] = []
for side in 0..<4 {
  let next = (side + 1) % 4
  faces.append((side, next, next + 4, wallClass))
  faces.append((side, next + 4, side + 4, wallClass))
}
faces.append((0, 1, 2, floorClass))
faces.append((0, 2, 3, floorClass))
faces.append((4, 5, 6, ceilingClass))
faces.append((4, 6, 7, ceilingClass))
var obj = "# vividhome-fixture room, metres, session frame\n"
for vertex in vertices { obj += "v \(vertex.x) \(vertex.y) \(vertex.z)\n" }
for face in faces { obj += "f \(face.a + 1) \(face.b + 1) \(face.c + 1)\n" }
try obj.write(to: layout.mesh, atomically: true, encoding: .utf8)
try Data(faces.map { $0.classification }).write(to: layout.meshClasses)

// stills.jsonl is written empty: the format allows no stills, and an empty file
// is a case the reader should handle.
try JSONLWriter(url: layout.stills).close()

let manifest = Manifest.starting(
  sessionID: sessionID,
  project: SlugRef(slug: "our-house", name: "Our House"),
  level: LevelRef(slug: "main", name: "Main Floor", index: 1),
  room: SlugRef(slug: "kitchen", name: "Kitchen"),
  phases: [.electrical, .plumbing],
  notes: "Written by vividhome-fixture for the contract check.",
  expectedMarkers: [MarkerID.string(for: 12)],
  device: DeviceInfo(
    model: "fixture", iosVersion: "0", appVersion: VividHomeCore.version, appBuild: "0"),
  startedAt: "2026-11-03T14:15:02-05:00",
  videoFormat: VideoFormat(w: colourWidth, h: colourHeight, fps: 30),
  keyframePolicy: KeyframePolicy.documentedDefault,
  depth: DepthFormat(w: depthWidth, h: depthHeight),
  jpegQuality: 0.85,
  markerPhysicalWidth: 0.20,
  sceneReconstruction: "meshWithClassification")

let finalized = manifest.finalized(
  endedAt: "2026-11-03T14:15:04-05:00", duration: 2.0, stats: stats)

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
try encoder.encode(finalized).write(to: layout.manifest)

print("wrote \(layout.root.path)")
print("  \(stats.keyframes) keyframes, \(stats.landmarks) landmarks, \(stats.markerObservations) marker observations")

// --- The field maths, run on this room for the pipeline to check ----------

struct ContractSnap: Codable {
  var label: String
  var tap: [Double]
  var position: [Double]?
  var movedBy: Double?
  var floorSource: String?

  enum CodingKeys: String, CodingKey {
    case label, tap, position
    case movedBy = "moved_by"
    case floorSource = "floor_source"
  }
}

struct ContractWall: Codable {
  var start: String
  var end: String
  var lengthM: Double
  var photographedFraction: Double
  var notPhotographedM: [[Double]]

  enum CodingKeys: String, CodingKey {
    case start, end
    case lengthM = "length_m"
    case photographedFraction = "photographed_fraction"
    case notPhotographedM = "not_photographed_m"
  }
}

struct ContractLine: Codable {
  var text: String
  var ok: Bool
}

/// A leave check and the sentences the phone makes from it, for the Python
/// to make the same (fieldcheck.py).
struct ContractFieldCheck: Codable {
  var check: FieldCheck
  var lines: [ContractLine]
}

struct ContractItem: Codable {
  var id: String
  var name: String
}

struct Contract: Codable {
  var snaps: [ContractSnap]
  var coverage: [ContractWall]
  var rangeM: Double
  var keyframesUsed: Int
  var keyframesTotal: Int
  var checklist: [ContractItem]
  var fieldChecks: [ContractFieldCheck]

  enum CodingKeys: String, CodingKey {
    case snaps, coverage, checklist
    case rangeM = "range_m"
    case keyframesUsed = "keyframes_used"
    case keyframesTotal = "keyframes_total"
    case fieldChecks = "field_checks"
  }
}

/// The faces the app's MeshProbe would hand the snap: those with a vertex
/// within half a metre of the tap.
func facesNear(_ tap: Vector3) -> [CornerSnap.Face] {
  faces.compactMap { face in
    let triangle = [vertices[face.a], vertices[face.b], vertices[face.c]]
    let near = triangle.contains { vertex in
      let dx = vertex.x - tap.x, dy = vertex.y - tap.y, dz = vertex.z - tap.z
      return (dx * dx + dy * dy + dz * dz).squareRoot() <= CornerSnap.reachMetres
    }
    guard near else { return nil }
    return CornerSnap.Face(a: triangle[0], b: triangle[1], c: triangle[2], classification: face.classification)
  }
}

let snaps = taps.map { tap -> ContractSnap in
  let snap = CornerSnap.snap(tap: tap.position, faces: facesNear(tap.position))
  return ContractSnap(
    label: tap.label, tap: [tap.position.x, tap.position.y, tap.position.z],
    position: snap.map { [$0.position.x, $0.position.y, $0.position.z] },
    movedBy: snap?.movedBy, floorSource: snap?.floorSource)
}

// Coverage against the corners as tapped, in tap order: coverage.py's
// denominator, so the two measure the same walls.
let cameras = frames.compactMap { frame in
  WallCoverage.Camera(
    pose: frame.poseWorldFromCamera, fx: frame.intrinsics.fx, fy: frame.intrinsics.fy,
    width: frame.width, height: frame.height)
}
let footprint = taps.map { (label: $0.label, x: $0.position.x, z: $0.position.z) }
let walls = WallCoverage.coverage(outline: footprint, cameras: cameras)
func hundredths(_ value: Double) -> Double { (value * 100).rounded() / 100 }

// Leave checks of every shape the review screen can show, with the phone's
// sentences for each; the stills ids are the checklist's.
let sampleChecks: [FieldCheck] = [
  FieldCheck(
    placement: .init(status: "check", rmsM: 0.18, corners: 2),
    walls: .init(
      photographed: 4, total: 5,
      gaps: [
        .init(wall: "corner-nw->corner-ne", fromM: 1.9, lengthM: 0.8),
        .init(wall: "corner-se->corner-sw", fromM: 0, lengthM: 0.5),
      ]),
    stills: .init(done: 7, total: 11, missing: ["panel", "home-runs", "smoke-co", "boxes"]),
    checkedAt: "2026-10-03T18:00:00Z", together: ["20261103-141502_main_kitchen_aaaaaa"]),
  FieldCheck(
    placement: .init(status: "placed", rmsM: 0.0449, corners: 3),
    walls: .init(photographed: 4, total: 4, gaps: []),
    stills: .init(done: 10, total: 10, missing: []), checkedAt: "2026-10-03T18:00:00Z"),
  FieldCheck(
    placement: .init(status: "not_placed", rmsM: 0.314, corners: 2), walls: nil,
    stills: .init(done: 1, total: 8, missing: StillsChecklist.items(for: [.electrical]).dropFirst().map(\.id)),
    checkedAt: "2026-10-03T18:00:00Z"),
  FieldCheck(
    placement: .init(status: "untapped", corners: 1), walls: nil,
    stills: .init(done: 2, total: 10, missing: ["headers", "blocking"]), checkedAt: "2026-10-03T18:00:00Z"),
  FieldCheck(
    placement: .init(status: "free", corners: 0), walls: nil,
    stills: .init(done: 0, total: 0, missing: []), checkedAt: "2026-10-03T18:00:00Z"),
]

let contract = Contract(
  snaps: snaps,
  coverage: walls.map { wall in
    ContractWall(
      start: wall.start, end: wall.end, lengthM: wall.length, photographedFraction: wall.fraction,
      notPhotographedM: wall.gaps.map { [hundredths($0.from), hundredths($0.from + $0.length)] })
  },
  rangeM: WallCoverage.rangeMetres, keyframesUsed: cameras.count, keyframesTotal: frames.count,
  checklist: StillsChecklist.all.map { ContractItem(id: $0.id, name: $0.name) },
  fieldChecks: sampleChecks.map { check in
    ContractFieldCheck(check: check, lines: check.lines.map { ContractLine(text: $0.text, ok: $0.ok) })
  })
let contractEncoder = JSONEncoder()
contractEncoder.outputFormatting = [.sortedKeys, .prettyPrinted]
try contractEncoder.encode(contract).write(to: contractPath)
print("wrote \(contractPath.path)")
for snap in snaps {
  let moved = snap.movedBy.map { String(format: "%.3f m", $0) } ?? "no snap"
  print("  \(snap.label): \(moved)")
}
for wall in contract.coverage {
  print("  \(wall.start) -> \(wall.end): photographed \(Int((wall.photographedFraction * 100).rounded()))%")
}
