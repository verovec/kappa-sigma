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

extension AppDelegateTests {
  @Test("quitting closes every document without bringing the welcome window back")
  func testAppDelegate_willTerminate_clearsWelcomeHook() throws {
    let document = try ProjectDocument(type: ProjectPackage.typeIdentifier)
    NSDocumentController.shared.addDocument(document)
    let (hook, documents) = (ProjectDocument.lastDocumentClosed, ProjectDocument.openDocuments)
    defer {
      ProjectDocument.lastDocumentClosed = hook
      ProjectDocument.openDocuments = documents
    }
    var fired = 0
    ProjectDocument.lastDocumentClosed = { fired += 1 }
    // Every close is the last one here: only the cleared hook keeps the window away.
    ProjectDocument.openDocuments = { [] }

    AppDelegate().applicationWillTerminate(
      Notification(name: NSApplication.willTerminateNotification))

    #expect(!NSDocumentController.shared.documents.contains(document))
    #expect(fired == 0)
  }

  @Test("launching arms the hook: the last project closed brings the welcome window back")
  func testAppDelegate_willFinishLaunching_setsWelcomeHook() {
    let hook = ProjectDocument.lastDocumentClosed
    defer { ProjectDocument.lastDocumentClosed = hook }
    var shown = 0
    let delegate = AppDelegate(welcome: { shown += 1 })

    delegate.applicationWillFinishLaunching(
      Notification(name: NSApplication.willFinishLaunchingNotification))
    ProjectDocument.lastDocumentClosed()

    #expect(shown == 1)
  }
}
