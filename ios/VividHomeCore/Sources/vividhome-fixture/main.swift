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

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
  FileHandle.standardError.write(Data("usage: vividhome-fixture <output-directory>\n".utf8))
  exit(2)
}

let sessionID = SessionID("20261103-141502_main_kitchen_k3x7qa")!
let layout = SessionLayout(root: URL(fileURLWithPath: arguments[1]))
try layout.createDirectories()

let colourWidth = 64
let colourHeight = 48
let depthWidth = 8
let depthHeight = 6

let intrinsics = Intrinsics(
  fx: 48.4, fy: 48.4, cx: Double(colourWidth) / 2, cy: Double(colourHeight) / 2)

/// A pose translated along +x, with an honest rotation block.
func pose(x: Double) -> Transform {
  Transform(elements: [
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    x, 0, 0, 1,
  ])!
}

let keyframes = 5
let framesWriter = try JSONLWriter(url: layout.frames)
var stats = SessionStats()

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
    time: Double(index) * 0.5,
    poseWorldFromCamera: pose(x: Double(index) * 0.25),
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

let landmarksWriter = try JSONLWriter(url: layout.landmarks)
for (label, x) in [("corner-nw", 0.0), ("corner-ne", 4.0)] {
  try landmarksWriter.append(
    LandmarkRecord(
      time: 0.2,
      index: 0,
      label: label,
      kind: .corner,
      position: Vector3(x, 0, 0),
      method: "raycast-estimatedPlane"))
  stats.recordLandmark()
}
try landmarksWriter.close()

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
