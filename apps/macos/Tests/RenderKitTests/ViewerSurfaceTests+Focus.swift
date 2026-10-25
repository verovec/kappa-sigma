import AppKit
import Foundation
import ImageKit
import RenderKit
import Testing

extension ViewerSurfaceTests {
  /// Records what the surface asked of the window's full screen.
  @MainActor
  final class FullScreenRecorder {
    var isOn = false
    var toggles = 0

    var seam: ViewerFullScreen {
      ViewerFullScreen(
        isOn: { _ in self.isOn },
        toggle: { _ in
          self.toggles += 1
          self.isOn.toggle()
        })
    }
  }

  /// Answers `cancelOperation(_:)` when the surface passes Esc on.
  final class EscapeRecorder: NSResponder {
    var cancelled = 0
    override func cancelOperation(_ sender: Any?) { cancelled += 1 }
  }

  @Test("⌘= / ⌘- / ⇧⌘F reach the surface through the responder chain")
  func testZoomAndFocus_ThroughResponderChain() throws {
    let (surface, cleanUp) = try Self.panelSurface()
    defer { cleanUp() }
    let recorder = FullScreenRecorder()
    surface.view.fullScreen = recorder.seam
    let responder = try #require(surface.window.firstResponder)
    let scale = surface.model.frame.transform.scale

    #expect(responder.tryToPerform(#selector(ViewerMTKView.zoomIn(_:)), with: nil))
    #expect(surface.model.frame.transform.scale == scale / 2)
    #expect(responder.tryToPerform(#selector(ViewerMTKView.zoomOut(_:)), with: nil))
    #expect(surface.model.frame.transform.scale == scale)

    #expect(responder.tryToPerform(#selector(ViewerMTKView.toggleFocusImage(_:)), with: nil))
    #expect(surface.model.isFocused && recorder.toggles == 1, "focus enters full screen")
    #expect(responder.tryToPerform(#selector(ViewerMTKView.toggleFocusImage(_:)), with: nil))
    #expect(!surface.model.isFocused && recorder.toggles == 2, "and leaves the one it entered")
  }

  @Test("Esc exits focus only when focused; otherwise it is passed on")
  func testEscape() throws {
    let (surface, cleanUp) = try Self.panelSurface()
    defer { cleanUp() }
    let recorder = FullScreenRecorder()
    surface.view.fullScreen = recorder.seam
    let next = EscapeRecorder()
    surface.view.nextResponder = next

    surface.view.cancelOperation(nil)
    #expect(next.cancelled == 1 && !surface.model.isFocused)

    surface.model.isFocused = true
    surface.view.cancelOperation(nil)
    #expect(!surface.model.isFocused && next.cancelled == 1, "Esc is the focus's own")
  }

  @Test("a window already in full screen stays there when focus exits")
  func testFocus_KeepsTheUsersFullScreen() throws {
    let (surface, cleanUp) = try Self.panelSurface()
    defer { cleanUp() }
    let recorder = FullScreenRecorder()
    recorder.isOn = true
    surface.view.fullScreen = recorder.seam

    surface.model.isFocused = true
    surface.model.isFocused = false
    #expect(recorder.toggles == 0 && recorder.isOn)
  }

  @Test("entering focus fits once, then a resize to the full-screen frame keeps the zoom")
  func testFocus_FitOnceThenKeep() throws {
    let (surface, cleanUp) = try Self.panelSurface()
    defer { cleanUp() }
    surface.view.fullScreen = FullScreenRecorder().seam
    let view = surface.view
    surface.model.frame.transform = ViewTransform(scale: 0.25, origin: .zero)

    surface.model.isFocused = true
    view.mtkView(view, drawableSizeWillChange: CGSize(width: 640, height: 320))
    #expect(
      surface.model.frame.transform
        == .fit(imageWidth: 64, imageHeight: 32, viewWidth: 640, viewHeight: 320))
    #expect(view.tryToPerform(#selector(ViewerMTKView.zoomIn(_:)), with: nil))
    let zoomed = surface.model.frame.transform
    view.mtkView(view, drawableSizeWillChange: CGSize(width: 1280, height: 640))
    #expect(surface.model.frame.transform.scale == zoomed.scale)
  }

  @Test("the focus menu item is checked while focused")
  func testFocus_MenuState() throws {
    let (surface, cleanUp) = try Self.panelSurface()
    defer { cleanUp() }
    surface.view.fullScreen = FullScreenRecorder().seam
    let item = NSMenuItem(
      title: "", action: #selector(ViewerMTKView.toggleFocusImage(_:)), keyEquivalent: "f")
    #expect(surface.view.validateMenuItem(item) && item.state == .off)
    surface.model.isFocused = true
    #expect(surface.view.validateMenuItem(item) && item.state == .on)
  }

  @Test("leaving the window leaves the focus and the full screen it entered")
  func testFocus_LeftWithTheWindow() throws {
    let (surface, cleanUp) = try Self.panelSurface()
    defer { cleanUp() }
    let recorder = FullScreenRecorder()
    surface.view.fullScreen = recorder.seam
    let container = NSView(frame: surface.view.frame)
    surface.window.contentView = container
    container.addSubview(surface.view)
    surface.model.isFocused = true
    #expect(recorder.isOn)

    surface.view.removeFromSuperview()
    #expect(!surface.model.isFocused)
    #expect(!recorder.isOn && recorder.toggles == 2)
  }

  @Test("a full screen the user left themselves is not toggled again when focus exits")
  func testFocus_UserLeftFullScreen() throws {
    let (surface, cleanUp) = try Self.panelSurface()
    defer { cleanUp() }
    let recorder = FullScreenRecorder()
    surface.view.fullScreen = recorder.seam
    surface.model.isFocused = true
    recorder.isOn = false
    NotificationCenter.default.post(
      name: NSWindow.didExitFullScreenNotification, object: surface.window)
    recorder.isOn = true  // then chose full screen again, on purpose

    surface.model.isFocused = false
    #expect(recorder.isOn && recorder.toggles == 1)
  }

  @Test("the Esc key leaves the focus; ⌥⌘0 is greyed and does nothing while focused")
  func testFocus_EscapeKeyAndPanelCommand() throws {
    let (surface, cleanUp) = try Self.panelSurface()
    defer { cleanUp() }
    surface.view.fullScreen = FullScreenRecorder().seam
    let toggle = #selector(ViewerMTKView.toggleViewerPanel(_:))
    let item = NSMenuItem(title: "", action: toggle, keyEquivalent: "0")
    surface.model.isFocused = true

    #expect(!surface.view.validateMenuItem(item))
    surface.view.toggleViewerPanel(nil)
    #expect(!surface.model.showsPanel, "the panel stays hidden in focus")
    let escape = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: surface.window.windowNumber, context: nil, characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
    let other = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: surface.window.windowNumber, context: nil, characters: "a",
        charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
    surface.view.keyDown(with: other)
    #expect(surface.model.isFocused, "another key goes on up the chain")
    surface.view.keyDown(with: escape)
    #expect(!surface.model.isFocused && surface.model.showsPanel)
    #expect(surface.view.validateMenuItem(item))
  }
}
