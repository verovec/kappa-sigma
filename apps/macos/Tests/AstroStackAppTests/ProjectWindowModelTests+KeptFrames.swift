import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// Card 0192: the bucket frames a project keeps are shown with their size and removed on the
/// user's word — this project's copies alone, never while a run is going.
@MainActor
@Suite("ProjectWindowModel — the downloaded bucket frames shown and removed")
struct ProjectWindowModelKeptFramesTests {
  typealias Remote = ProjectWindowModelRemoteRunTests

  /// Keeps the lights of the bucket night in `cache`, as a run would have left them.
  static func keep(in cache: RemoteFrameCache) throws {
    for frame in Remote.inventory().frames where frame.type == .light {
      let parts = try #require(ProjectSource.remoteParts(of: frame.path))
      let file = cache.file(bucket: parts.bucket, key: parts.key)
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data("a light of the bucket".utf8).write(to: file)
      try cache.keep(file, as: "21|e")
    }
  }

  @Test("nothing kept: nothing shown, nothing to remove", .scratchDirectory)
  func testNothingKept() async throws {
    let (project, window) = try await Remote.project(Remote.Heard())
    defer { try? project.close() }
    await window.keptFramesSettled()

    #expect(window.keptFrames == nil)
    #expect(!window.canRemoveKeptFrames && !window.offersKeptFramesRemoval)
    window.removeKeptFrames()
    await window.keptFramesSettled()
    #expect(window.error == nil)
  }

  @Test(
    "the kept frames are shown with their size, and removed: this project's copies alone",
    .scratchDirectory)
  func testRemoveKeptFrames() async throws {
    let (project, window) = try await Remote.project(Remote.Heard())
    defer { try? project.close() }
    let cache = try #require(window.remoteFrameCache)
    try Self.keep(in: cache)
    // A neighbour's copies and a capture of this Mac, beside what may be removed.
    let neighbour = RemoteFrameCache(
      root: cache.root.deletingLastPathComponent().appendingPathComponent("M42-ffffffff"))
    try Self.keep(in: neighbour)
    let capture = try ScratchDirectory.url.appendingPathComponent("captures/M31/l_1.fits")
    try FileManager.default.createDirectory(
      at: capture.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("a light of this Mac".utf8).write(to: capture)

    window.rescan()
    await window.scanSettled()
    await window.keptFramesSettled()
    let kept = try #require(window.keptFrames)
    #expect(kept.bytes > 0 && kept.folder == cache.root && window.canRemoveKeptFrames)
    #expect(!window.offersKeptFramesRemoval, "offered once an export is made, not before")
    let before = try #require(window.scratchBudget?.neededBytes)

    window.removeKeptFrames()
    #expect(window.isRemovingKeptFrames && !window.canRun && !window.canRemoveKeptFrames)
    window.removeKeptFrames()
    await window.keptFramesSettled()

    #expect(!window.isRemovingKeptFrames && window.canRun, "Run waited for the removal")
    #expect(window.keptFrames == nil && window.error == nil)
    #expect(!FileManager.default.fileExists(atPath: cache.root.path))
    #expect(neighbour.size() > 0, "another project's copies stay")
    #expect(FileManager.default.fileExists(atPath: capture.path), "a capture of this Mac stays")
    let after = try #require(window.scratchBudget?.neededBytes)
    #expect(after > before, "the next run downloads them again: \(before) → \(after)")
  }

  @Test(
    "nothing is removed while a run is going: its lanes link the kept frames",
    .scratchDirectory)
  func testNoRemovalDuringARun() async throws {
    let (project, window) = try await Remote.project(Remote.Heard())
    defer { try? project.close() }
    let cache = try #require(window.remoteFrameCache)
    try Self.keep(in: cache)
    window.rescan()
    await window.scanSettled()
    await window.keptFramesSettled()

    window.startRun()
    #expect(window.isStacking && !window.canRemoveKeptFrames)
    window.removeKeptFrames()
    #expect(cache.size() > 0, "refused: a run is going")
    await ProjectScopeTests.queueSettled(window)
    await window.keptFramesSettled()

    #expect(window.keptFrames != nil && window.canRemoveKeptFrames, "offered again once it ends")
  }

  @Test(
    "the line says how much is kept and where, and the confirmation what is freed",
    arguments: [Locale(identifier: "en"), Locale(identifier: "fr")])
  func testLineWords(locale: Locale) {
    let kept = KeptFrames(
      bytes: 5_200_000_000, folder: URL(fileURLWithPath: "/Volumes/Scratch/remote-frames/M31"),
      scratch: URL(fileURLWithPath: "/Volumes/Scratch"))
    let size = AstroFormat(locale: locale).bytes(kept.bytes)
    let notice = String(localized: KeptFramesLine.notice(kept, locale: locale))
    let consequence = String(localized: KeptFramesLine.consequence(kept, locale: locale))
    #expect(notice.contains(size) && notice.contains("/Volumes/Scratch/remote-frames/M31"))
    #expect(consequence.contains(size))
    #expect(notice != consequence)
  }

  @Test(
    "the line lays out with and without its button, and takes no room when nothing is kept",
    .scratchDirectory, arguments: [Locale(identifier: "en"), Locale(identifier: "fr")])
  func testLineLaysOut(locale: Locale) async throws {
    let (project, window) = try await Remote.project(Remote.Heard())
    defer { try? project.close() }
    await window.keptFramesSettled()
    let empty = NSHostingView(
      rootView: KeptFramesLine(model: window).environment(\.locale, locale))
    #expect(empty.fittingSize.height == 0)

    try Self.keep(in: try #require(window.remoteFrameCache))
    window.rescan()
    await window.scanSettled()
    await window.keptFramesSettled()
    for offers in [true, false] {
      let host = NSHostingView(
        rootView: KeptFramesLine(model: window, offersRemoval: offers)
          .environment(\.locale, locale).frame(width: 900))
      #expect(host.fittingSize.height > 0, "button: \(offers)")
    }
  }
}
