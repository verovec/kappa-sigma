import AppKit

/// AstroStack 2: the application entry point.
///
/// The AppKit lifecycle, not a SwiftUI `App`: documents are `NSDocument`s (`ProjectDocument`,
/// declared in `App/Info.plist`) because a package holding SQLite and large FITS files must be
/// saved in place (playbook §7). A SwiftUI `App` without a `DocumentGroup` also swallows
/// AppKit's untitled-document-at-launch callback. Window content is SwiftUI.
@main
enum AstroStackApp {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    let menu = MainMenu.make()
    app.mainMenu = menu
    app.windowsMenu = MainMenu.windowsMenu(in: menu)
    app.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) { app.run() }
  }
}
