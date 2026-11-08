internal import Foundation
package import ProjectKit
package import StackKit

/// The buckets a run may read, and those whose connection the Keychain refused (card 0185).
package nonisolated struct RunBuckets: Sendable {
  /// One store per bucket the run can read.
  package var stores: [RemoteObjectStore] = []
  /// Why a bucket cannot be read, by name: the Keychain's refusal, as it was thrown.
  package var refusals: [String: any Error] = [:]

  /// No bucket: a run of this Mac's folders.
  package init() {}

  /// `bucket` has a store or a refusal already.
  package func names(_ bucket: String) -> Bool {
    refusals[bucket] != nil || stores.contains { $0.bucket == bucket }
  }

  /// The refusal of the first refused bucket a path of `paths` lives in; `nil` when none does.
  ///
  /// Asked before Siril starts (R2): a run needing a refused bucket stops with the refusal's
  /// own words, one that never reads it runs.
  package func refusal(reading paths: [String]) -> (any Error)? {
    guard !refusals.isEmpty else { return nil }
    for path in paths {
      if let bucket = ProjectSource.remoteParts(of: path)?.bucket, let refusal = refusals[bucket] {
        return refusal
      }
    }
    return nil
  }

  /// The remote sources of `sources` whose bucket a frame of `inventory` is read from: a run
  /// looks up only those connections, so a run of this Mac's frames never asks the Keychain.
  package static func sources(_ sources: [ProjectSource], readBy inventory: Inventory)
    -> [ProjectSource]
  {
    Self.sources(sources, reading: inventory.sets.flatMap { $0.frames.map(\.path) })
  }

  /// The remote sources of `sources` whose bucket a path of `paths` is read from (a master
  /// rebuild asks only for the connections of its own set's buckets).
  package static func sources(_ sources: [ProjectSource], reading paths: [String])
    -> [ProjectSource]
  {
    let read = Set(paths.compactMap { ProjectSource.remoteParts(of: $0)?.bucket })
    guard !read.isEmpty else { return [] }
    return sources.filter { $0.kind == .remoteNight && $0.bucket.map(read.contains) == true }
  }

  /// `refusal(reading:)` over every frame of `inventory`.
  package func refusal(in inventory: Inventory) -> (any Error)? {
    refusal(reading: inventory.sets.flatMap { $0.frames.map(\.path) })
  }
}
