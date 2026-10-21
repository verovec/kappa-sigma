import AppKit
import RenderKit
import Testing

/// The semantic colours resolved as AppKit draws them, in each appearance: text and status
/// colours readable on the surface (WCAG AA), the image surround neutral grey.
@MainActor
@Suite("Design tokens — status contrast and a neutral canvas in light and dark")
struct DesignTokensTests {
  /// Text drawn on the surface: the two text levels and every status.
  static let textTokens: [DesignColor] =
    [.textPrimary, .textSecondary] + DesignStatus.allCases.map(\.token)

  @Test(
    "every text and status colour reaches 4.5:1 on the surface",
    arguments: DesignAppearance.allCases)
  func testStatusColoursMeetContrast(_ appearance: DesignAppearance) throws {
    let surface = try #require(DesignColor.surface.resolved(in: appearance))
    for token in Self.textTokens {
      let colour = try #require(token.resolved(in: appearance))
      #expect(colour.contrast(with: surface) >= 4.5, "\(token) on surface in \(appearance)")
    }
  }

  @Test("the canvas around the image is neutral grey", arguments: DesignAppearance.allCases)
  func testCanvasIsNeutral(_ appearance: DesignAppearance) throws {
    let canvas = try #require(DesignColor.canvas.resolved(in: appearance))
    #expect(canvas.red == canvas.green && canvas.green == canvas.blue)
    #expect(DesignColor.canvasGrey(in: appearance) == Float(canvas.red))
  }

  @Test("the canvas does not follow the accent colour")
  func testCanvasIgnoresAccent() throws {
    for appearance in DesignAppearance.allCases {
      let canvas = try #require(DesignColor.canvas.resolved(in: appearance))
      let accent = try #require(SRGB(NSColor.controlAccentColor, in: appearance))
      #expect(canvas != accent)
    }
  }

  @Test("light and dark resolve to different colours for every token that has text on it")
  func testAppearancesDiffer() throws {
    for token in Self.textTokens + [.surface] {
      #expect(token.resolved(in: .light) != token.resolved(in: .dark), "\(token)")
    }
  }

  @Test(
    "contrast and luminance follow WCAG 2.x",
    arguments: zip(
      [(SRGB(hex: 0x000000), SRGB(hex: 0xFFFFFF)), (SRGB(hex: 0x777777), SRGB(hex: 0xFFFFFF))],
      [21.0, 4.48]))
  func testContrastFormula(_ pair: (SRGB, SRGB), _ expected: Double) {
    #expect(abs(pair.0.contrast(with: pair.1) - expected) < 0.01)
    #expect(abs(pair.1.contrast(with: pair.0) - expected) < 0.01)
  }

  @Test("an appearance is read from AppKit's, dark variants included")
  func testAppearanceFromAppKit() throws {
    let names: [NSAppearance.Name] = [.aqua, .darkAqua, .vibrantDark, .vibrantLight]
    let read = try names.map { DesignAppearance(try #require(NSAppearance(named: $0))) }
    #expect(read == [.light, .dark, .dark, .light])
  }

  @Test("every status has an icon, so a status is never told by colour alone")
  func testStatusesHaveIcons() {
    let icons = DesignStatus.allCases.map(\.systemImage)
    #expect(Set(icons).count == DesignStatus.allCases.count)
    #expect(
      icons.allSatisfy { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil })
  }
}
