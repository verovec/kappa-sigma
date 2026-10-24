import AppKit
import Foundation
import RenderKit
import SwiftUI
import Testing

/// The component gallery — every shared component in every state — laid out offscreen in light
/// and dark, French and English, and rendered to PNG attachments (the card's screenshots).
@MainActor
@Suite("Component gallery — every component in every variant")
struct ComponentGalleryTests {
  struct Variant: Sendable, CustomTestStringConvertible {
    let appearance: DesignAppearance
    let language: String
    var testDescription: String { "\(appearance)-\(language)" }
  }

  nonisolated static let variants = DesignAppearance.allCases.flatMap { appearance in
    ["en", "fr"].map { Variant(appearance: appearance, language: $0) }
  }

  /// `view` in an offscreen hosting view drawn as `appearance` over the window background.
  static func render<Content: View>(
    _ view: Content, _ variant: Variant, width: CGFloat = 760
  ) throws -> (size: CGSize, png: Data, bitmap: NSBitmapImageRep) {
    let host = NSHostingView(
      rootView: view.environment(\.locale, Locale(identifier: variant.language))
        .frame(width: width)
        .background(DesignColor.surface.color))
    // Offscreen there is no window to paint behind the text: pin the appearance and an opaque
    // background, or text renders invisible (LiveImportSheetTests).
    host.appearance = variant.appearance.nsAppearance
    host.frame = NSRect(origin: .zero, size: CGSize(width: width, height: 10))
    let size = host.fittingSize
    host.frame = NSRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    return (size, png, bitmap)
  }

  @Test("every component lays out in light and dark, French and English", arguments: variants)
  func testEveryComponentLaysOutInEveryVariant(_ variant: Variant) throws {
    let (size, png, bitmap) = try Self.render(ComponentGallery(), variant)
    Attachment.record(png, named: "component-gallery-\(variant.testDescription).png")
    #expect(size.height > 600, "every section stacked: \(size)")

    // Text and badges drew something other than the background.
    let surface = try #require(DesignColor.surface.resolved(in: variant.appearance))
    var inked = 0
    for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
      for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
        guard let pixel = bitmap.colorAt(x: x, y: y).flatMap({ SRGB($0, in: variant.appearance) })
        else { continue }
        inked += pixel.contrast(with: surface) > 3 ? 1 : 0
      }
    }
    #expect(inked > 500, "text is visible on the surface: \(inked) inked samples")
  }

  @Test("the gallery shows every status and both parameter states")
  func testGalleryCoversEveryState() {
    #expect(ComponentGallery.statuses == DesignStatus.allCases)
    #expect(ComponentGallery.parameters.map(\.isDefault) == [true, false])
    #expect(ComponentGallery.installStates.count == 4)
  }

  @Test("French words are longer: the gallery widens nothing past its frame", arguments: variants)
  func testNoClippingAtNarrowWidth(_ variant: Variant) throws {
    let (size, _, _) = try Self.render(ComponentGallery(), variant, width: 520)
    #expect(size.width == 520)
  }
}
