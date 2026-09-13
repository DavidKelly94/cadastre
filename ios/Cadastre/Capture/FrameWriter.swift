import CoreVideo
import Foundation

import CadastreCore

/// Writing keyframes and stills to disk, off the ARKit delegate thread.
///
/// The delegate is called thirty times a second on the main thread, and encoding
/// a frame takes about as long as the gap between calls. So the delegate does the
/// cheap part — copying depth out of its buffer, which must happen before ARKit
/// reuses it — and hands the rest here.
///
/// The queue is bounded. When the phone falls behind, a keyframe is refused and
/// counted rather than queued: `BoundedWriteQueue` explains why, and it is tested
/// on Linux. Nothing in this class decides that policy; it only reports what
/// happened so the recorder can keep the statistics honest.
final class FrameWriter {
  /// What became of a submitted keyframe. `dropped` is not an error: it is the
  /// backpressure working, and the manifest records how often it happened.
  enum Outcome {
    case written(bytes: Int)
    case dropped
    case failed(Error)
  }

  private let layout: SessionLayout
  private let queue: BoundedWriteQueue
  private let encoder = JPEGEncoder()
  private let frames: JSONLWriter
  private let stills: JSONLWriter
  private let quality: Double

  private let lock = NSLock()
  private var linesSinceFlush = 0

  init(layout: SessionLayout, quality: Double = AppConfig.defaultJPEGQuality) throws {
    self.layout = layout
    self.quality = quality
    self.queue = BoundedWriteQueue(
      label: "ai.cadastre.frame-writer", depth: AppConfig.writerQueueDepth)
    self.frames = try JSONLWriter(url: layout.frames)
    self.stills = try JSONLWriter(url: layout.stills)
  }

  /// Submit a keyframe. Returns immediately; `completion` runs on the writer queue.
  ///
  /// `depth` and `confidence` are already packed, because they have to be copied
  /// out of their pixel buffers before ARKit reuses them. The colour buffer is
  /// retained instead of copied — retaining `capturedImage` is safe, where
  /// retaining the `ARFrame` would stop ARKit delivering any more.
  @discardableResult
  func write(
    record: FrameRecord,
    colour: CVPixelBuffer,
    depth: Data,
    confidence: Data,
    completion: @escaping @Sendable (Outcome) -> Void
  ) -> Bool {
    let accepted = queue.enqueue { [self] in
      do {
        let jpeg = try encoder.encode(colour, quality: quality)
        try jpeg.write(to: layout.rgb(keyframe: record.index), options: .atomic)
        try depth.write(to: layout.depth(keyframe: record.index), options: .atomic)
        try confidence.write(to: layout.confidence(keyframe: record.index), options: .atomic)
        try frames.append(record)
        flushIfDue(frames)
        completion(.written(bytes: jpeg.count + depth.count + confidence.count))
      } catch {
        completion(.failed(error))
      }
    }
    if !accepted {
      completion(.dropped)
    }
    return accepted
  }

  /// Submit a high-resolution still. Stills have no depth files.
  @discardableResult
  func write(
    still: StillRecord,
    colour: CVPixelBuffer,
    completion: @escaping @Sendable (Outcome) -> Void
  ) -> Bool {
    let accepted = queue.enqueue { [self] in
      do {
        let jpeg = try encoder.encode(colour, quality: quality)
        try jpeg.write(to: layout.still(still.stillIndex), options: .atomic)
        try stills.append(still)
        flushIfDue(stills)
        completion(.written(bytes: jpeg.count))
      } catch {
        completion(.failed(error))
      }
    }
    if !accepted {
      completion(.dropped)
    }
    return accepted
  }

  /// Wait for everything submitted, then flush and close.
  ///
  /// Called before the manifest is rewritten, so its statistics describe files
  /// that are actually on disk rather than ones still in a queue.
  func finish() throws {
    queue.drain()
    try frames.close()
    try stills.close()
  }

  /// Flush every `AppConfig.flushEveryLines` lines.
  ///
  /// Not every line: fsync costs more than it saves at thirty a second, and a
  /// session that dies is recoverable from whatever reached disk. Not never
  /// either, or a crash loses the lot.
  private func flushIfDue(_ writer: JSONLWriter) {
    lock.lock()
    linesSinceFlush += 1
    let due = linesSinceFlush >= AppConfig.flushEveryLines
    if due { linesSinceFlush = 0 }
    lock.unlock()

    if due {
      try? writer.synchronize()
    }
  }
}
