internal import Foundation
internal import ImageKit

extension PhotometricNormaliser {
  /// One group: measured, fitted, gated against clipping, applied unless reference or identity.
  static func normalise(
    _ group: PhotomGroup, onto reference: FrameCurve, referenceMeta: PhotomMeta, isReference: Bool,
    notes: inout [String]
  ) -> PhotomGroupRecord {
    var record = PhotomGroupRecord(skipping: group)
    record.isReference = isReference
    var (transform, curve) = measure(
      group, onto: reference, referenceMeta: referenceMeta, notes: &notes)
    if !isReference,
      let (degraded, note) = degradeClipping(
        group.label, transform, group: curve, reference: reference)
    {
      transform = degraded
      record.reverted = true
      notes.append(note)
    }
    record.scale = transform.scale
    record.offset = transform.offset
    record.residual = transform.residual
    record.method = transform.method
    record.clamped = transform.clamped
    record.metaDisagree = transform.metaDisagree
    record.metaSeeded = transform.metaSeeded
    record.saturatedFraction = curve.saturatedFraction
    record.saturationCeiling = transform.offset.addingProduct(
      transform.scale, Double(FrameCurve.saturationLevel))
    if record.saturatedFraction > saturationNoteFraction {
      notes.append(
        "group \"\(group.label)\": "
          + "\(String(format: "%.2f", record.saturatedFraction * 100))% of pixels near "
          + "sensor saturation — the clipped core carries no photometric information "
          + "(the pre-stack repair draws on unsaturated nights)")
    }
    notes += warnings(group.label, transform)
    guard !isReference, !transform.isIdentity(referenceNoise: reference.noise) else {
      return record
    }
    do {
      try apply(transform, to: group.paths)
      record.applied = true
    } catch {
      notes.append(
        Task.isCancelled
          ? "group \"\(group.label)\": photometric normalization cancelled"
          : "photometric normalization skipped for group \"\(group.label)\": "
            + "frames are not 32-bit float"
      )
    }
    return record
  }

  /// The median transform over the group's probe frames, and its median curve.
  static func measure(
    _ group: PhotomGroup, onto reference: FrameCurve, referenceMeta: PhotomMeta,
    notes: inout [String]
  ) -> (PhotomTransform, FrameCurve) {
    var fits: [PhotomTransform] = []
    var curves: [FrameCurve] = []
    for path in evenSpaced(group.paths, maxProbeFrames) {
      guard let curve = try? measure(path) else {
        notes.append("group \"\(group.label)\": unreadable frame \(path)")
        continue
      }
      curves.append(curve)
      fits.append(
        CurveFit.fit(curve, onto: reference, frameMeta: group.meta, referenceMeta: referenceMeta))
    }
    guard !fits.isEmpty else { return (PhotomTransform(), FrameCurve()) }
    var transform = PhotomTransform(
      scale: PhotomStats.median(fits.map(\.scale)), offset: PhotomStats.median(fits.map(\.offset)),
      method: dominant(fits.map(\.method)))
    transform.residual = PhotomStats.median(fits.map(\.residual))
    transform.clamped = fits.contains(where: \.clamped)
    transform.metaDisagree = fits.contains(where: \.metaDisagree)
    transform.metaSeeded = fits.contains(where: \.metaSeeded)
    transform.backgroundDisagree = fits.contains(where: \.backgroundDisagree)
    return (transform, FrameCurve.median(curves))
  }

  /// The most frequent method; ties go to the most authoritative (`dominantMethod`).
  static func dominant(_ methods: [PhotomTransform.Method]) -> PhotomTransform.Method {
    var best = PhotomTransform.Method.identity
    var bestCount = 0
    for method in PhotomTransform.Method.allCases {
      let count = methods.count { $0 == method }
      if count > bestCount { (best, bestCount) = (method, count) }
    }
    return best
  }

  /// Rewrites each frame in place as `scale · p + offset`.
  ///
  /// Only float32 frames with BZERO 0 and BSCALE 1 (`OverwriteData`'s requirement), checked before
  /// any is touched.
  static func apply(_ transform: PhotomTransform, to paths: [String]) throws {
    for path in paths {
      try Task.checkCancellation()
      let url = URL(fileURLWithPath: path)
      let file = try FITSFile.read(at: url)
      guard file.header.int("BITPIX") == -32, (file.header.double("BZERO") ?? 0) == 0,
        (file.header.double("BSCALE") ?? 1) == 1
      else { throw CocoaError(.fileWriteUnknown) }
      let image = try file.image()
      image.planes = image.planes.map { $0.map(transform.apply) }
      try file.write(image, to: url)
    }
  }
}
