package import AppKit
package import Foundation
internal import ImageKit
internal import Metal
package import RenderKit
internal import SwiftUI
internal import UniformTypeIdentifiers
internal import os

/// A window showing one FITS image in the Metal viewer (until the Studio, E12, hosts it).
package final class ImageViewerWindow: NSWindowController, NSWindowDelegate {
  private nonisolated static let logger = Logger(
    subsystem: "fr.astrostack", category: "App/viewer")
  /// Windows kept alive while open.
  private static var opened: [ImageViewerWindow] = []

  /// Asks for a FITS file and shows it.
  static func choose() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = ["fit", "fits", "fts"].compactMap {
      UTType(filenameExtension: $0)
    }
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    show(url)
  }

  /// Opens `url` in a viewer window; a failure is shown, never swallowed.
  @discardableResult
  package static func show(_ url: URL) -> Task<Void, Never> {
    Task {
      do {
        try await open(url)
      } catch {
        logger.error("cannot open \(url.path, privacy: .public): \(error, privacy: .public)")
        NSAlert(error: error).runModal()
      }
    }
  }

  /// Reads `url` off the main actor and shows it in a new viewer window.
  @discardableResult
  package static func open(_ url: URL) async throws -> ImageViewerWindow {
    guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.noDevice }
    let renderer = try ViewerRenderer(device: device)
    let loaded = try await Loaded.read(url, device: device)
    let model = ViewerModel(image: loaded.image, autoSTF: loaded.autoSTF)
    let view = ViewerView(model: model, renderer: renderer, texture: loaded.texture, reference: nil)
    let controller = ImageViewerWindow(view: view, title: url.lastPathComponent)
    controller.model = model
    opened.append(controller)
    controller.showWindow(nil)
    return controller
  }

  /// The viewer windows currently open.
  package static var openWindows: [ImageViewerWindow] { opened }
  /// The shown image's viewer state.
  package private(set) var model: ViewerModel?

  private init(view: ViewerView, title: String) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
      defer: false)
    window.title = title
    window.contentView = NSHostingView(rootView: view)
    window.center()
    super.init(window: window)
    window.delegate = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  package func windowWillClose(_ notification: Notification) {
    Self.opened.removeAll { $0 === self }
  }

  /// The decoded image, its textures and its autostretch, built off the main actor.
  private nonisolated struct Loaded {
    let image: AstroImage
    let texture: ImageTexture
    let autoSTF: [STFParameters]

    /// FITS decode, pyramid + upload and statistics: CPU-bound, never on the main actor.
    @concurrent
    nonisolated static func read(_ url: URL, device: MTLDevice) async throws -> sending Self {
      let started = ContinuousClock.now
      let image = try FITSFile.read(at: url).image()
      let decoded = ContinuousClock.now
      let texture = try ImageTexture(
        device: device, width: image.width, height: image.height, planes: image.planes)
      let uploaded = ContinuousClock.now
      let autoSTF = AutoSTF.compute(planes: image.planes, linked: false)
      logger.info(
        """
        opened \(url.lastPathComponent, privacy: .public) \(image.width)×\(image.height)×\
        \(image.planes.count), \(texture.mipLevels) mip levels: read \
        \(decoded - started, privacy: .public), upload \(uploaded - decoded, privacy: .public), \
        STF \(ContinuousClock.now - uploaded, privacy: .public)
        """)
      return Self(image: image, texture: texture, autoSTF: autoSTF)
    }
  }
}
