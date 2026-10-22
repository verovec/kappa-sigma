import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import Testing

@MainActor
@Suite("AppDelegate: launch and quit behaviour of a document app")
struct AppDelegateTests {
  @Test("quitting closes open documents, so untitled temporary packages are deleted")
  func testAppDelegate_willTerminate_closesDocuments() throws {
    let controller = NSDocumentController.shared
    let document = try ProjectDocument(type: ProjectPackage.typeIdentifier)
    let untitled = try #require(document.packageURL)
    controller.addDocument(document)

    AppDelegate().applicationWillTerminate(
      Notification(name: NSApplication.willTerminateNotification))

    #expect(!controller.documents.contains(document))
    #expect(!FileManager.default.fileExists(atPath: untitled.path))
  }

  @Test("an app launched without a file shows the welcome window, not an untitled project")
  func testLaunchShowsWelcomeNotUntitled() {
    let delegate = AppDelegate()
    let before = NSDocumentController.shared.documents.count

    #expect(delegate.applicationShouldOpenUntitledFile(NSApplication.shared))
    #expect(delegate.applicationOpenUntitledFile(NSApplication.shared))

    #expect(WelcomeWindow.isVisible)
    #expect(NSDocumentController.shared.documents.count == before)
    WelcomeWindow.show().close()
  }
}
