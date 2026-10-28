import AppKit
import AstroStackApp
import FilterKit
import Foundation
import ProjectKit
import RenderKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// The Données pane (0078) laid out offscreen: before any scan and after one, in fr and en, light
/// and dark; the words it shows come from the glossary and the catalog.
@MainActor
@Suite("Données pane — integration and calibration coverage in every variant")
struct DonneesPaneTests {
  struct Variant: Sendable, CustomTestStringConvertible {
    let scanned: Bool
    let language: String
    let appearance: DesignAppearance
    var testDescription: String {
      "\(scanned ? "scanned" : "empty")-\(language)-\(appearance)"
    }
  }

  nonisolated static let variants = [false, true].flatMap { scanned in
    ["en", "fr"].flatMap { language in
      DesignAppearance.allCases.map {
        Variant(scanned: scanned, language: language, appearance: $0)
      }
    }
  }

  @Test(
    "lays out, scanned or not, in fr and en, light and dark", .scratchDirectory, arguments: variants
  )
  func testLaysOutInEveryVariant(_ variant: Variant) async throws {
    let project = try ProjectWorkspaceTests.project()
    defer { try? project.close() }
    let model = ProjectWindowModel(
      store: { project.store }, planning: { _ in { DataScanTests.gapPlan($0) } })
    model.add(ImportRequest(paths: ["/captures/M31-DB"]))
    model.select(.data)
    if variant.scanned {
      model.rescan()
      await model.scanSettled()
      #expect(model.integration?.frames == 36)
    }

    let host = ImportSheetTests.host(
      ProjectWindowView(model: model)
        .environment(\.locale, Locale(identifier: variant.language)))
    host.appearance = variant.appearance.nsAppearance
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width >= 640 && host.fittingSize.height >= 400)
    if variant.scanned && variant.appearance == .light {
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let png = try #require(bitmap.representation(using: .png, properties: [:]))
      Attachment.record(png, named: "donnees-\(variant.language).png")
    }
  }

  @Test(
    "a filter reads in the glossary's words, colour and clip filter included",
    arguments: zip(
      [
        ("Ha", FilterSet.unknown, "en"), ("RGB", .dualband, "en"), ("Hd", .unknown, "fr"),
        ("Hb", .unknown, "fr"),
      ],
      ["Hydrogen-alpha", "Colour · Dual-band", "Hd", "Hydrogène bêta"]))
  func testFilterWords(_ input: (String, FilterSet, String), expected: String) {
    #expect(
      ImportFormat.filter(input.0, filterSet: input.1, locale: Locale(identifier: input.2))
        == expected)
  }

  @Test("a coverage cell's badge: covered is fine, skipped is the user's, a gap needs attention")
  func testCellBadges() {
    #expect(ImportFormat.badge(.library(path: "/l/d.fits", frames: 5)) == .ok)
    #expect(ImportFormat.badge(.build(frames: 12)) == .ok)
    #expect(ImportFormat.badge(.excluded(.build(frames: 12))) == .unavailable)
    #expect(ImportFormat.badge(.missing) == .attention)
  }
}
