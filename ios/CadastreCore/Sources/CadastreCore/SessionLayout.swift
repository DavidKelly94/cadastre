import Foundation

/// Where every file in a session lives.
///
/// The names in `docs/session-format.md` §2 appear here once. The app writes
/// through this and the pipeline reads the same names from its own constants, so
/// a change to the layout is a change to the contract and shows up in both.
public struct SessionLayout: Sendable {
  public let root: URL

  public init(root: URL) {
    self.root = root
  }

  /// The layout for a session inside a project directory.
  public init(documents: URL, project: String, sessionID: SessionID) {
    self.root =
      documents
      .appendingPathComponent("sessions", isDirectory: true)
      .appendingPathComponent(project, isDirectory: true)
      .appendingPathComponent(sessionID.stringValue, isDirectory: true)
  }

  public var manifest: URL { root.appendingPathComponent("manifest.json") }
  public var frames: URL { root.appendingPathComponent("frames.jsonl") }
  public var stills: URL { root.appendingPathComponent("stills.jsonl") }
  public var markers: URL { root.appendingPathComponent("markers.jsonl") }
  public var landmarks: URL { root.appendingPathComponent("landmarks.jsonl") }
  public var log: URL { root.appendingPathComponent("log.txt") }
  public var mesh: URL { root.appendingPathComponent("mesh.obj") }
  public var meshClasses: URL { root.appendingPathComponent("mesh_classes.u8") }
  public var meshSummary: URL { root.appendingPathComponent("mesh.json") }

  public var rgbDirectory: URL { root.appendingPathComponent("rgb", isDirectory: true) }
  public var depthDirectory: URL { root.appendingPathComponent("depth", isDirectory: true) }
  public var confidenceDirectory: URL { root.appendingPathComponent("conf", isDirectory: true) }
  public var stillsDirectory: URL { root.appendingPathComponent("stills", isDirectory: true) }

  /// Written only by the pipeline. The app creates it for nobody.
  public var derived: URL { root.appendingPathComponent("derived", isDirectory: true) }

  /// Directories the app creates when a session starts.
  public var requiredDirectories: [URL] {
    [root, rgbDirectory, depthDirectory, confidenceDirectory, stillsDirectory]
  }

  public func rgb(keyframe index: Int) -> URL {
    rgbDirectory.appendingPathComponent(FrameRecord.paths(forKeyframe: index).rgb.fileName)
  }

  public func depth(keyframe index: Int) -> URL {
    depthDirectory.appendingPathComponent(FrameRecord.paths(forKeyframe: index).depth.fileName)
  }

  public func confidence(keyframe index: Int) -> URL {
    confidenceDirectory.appendingPathComponent(FrameRecord.paths(forKeyframe: index).conf.fileName)
  }

  public func still(_ index: Int) -> URL {
    stillsDirectory.appendingPathComponent(StillRecord.path(forStill: index).fileName)
  }

  /// Creates the directories a session needs.
  public func createDirectories(using manager: FileManager = .default) throws {
    for directory in requiredDirectories {
      try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
  }
}

extension String {
  /// The last path component of a session-relative path such as `rgb/000123.jpg`.
  fileprivate var fileName: String {
    split(separator: "/").last.map(String.init) ?? self
  }
}
