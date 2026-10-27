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
    ProjectDocument.openDocuments = { [document] }

    // Only this test's document: another suite's documents stay open.
    AppDelegate().closeForQuit([document])

    #expect(!NSDocumentController.shared.documents.contains(document))
    #expect(fired == 0)
  }

  @Test(
    "launching arms the hook: the last project closed brings the welcome window back, with the retention review once"
  )
  func testAppDelegate_willFinishLaunching_setsWelcomeHook() async {
    let hook = ProjectDocument.lastDocumentClosed
    defer { ProjectDocument.lastDocumentClosed = hook }
    var shown = 0
    let reviewed = AsyncStream<Void>.makeStream()
    let delegate = AppDelegate(
      welcome: { shown += 1 }, reviewRetention: { reviewed.continuation.yield() })

    delegate.applicationWillFinishLaunching(
      Notification(name: NSApplication.willFinishLaunchingNotification))
    ProjectDocument.lastDocumentClosed()
    ProjectDocument.lastDocumentClosed()

    #expect(shown == 2)
    // A launch that restored a project reviews when its last window closes.
    var reviews = 0
    for await _ in reviewed.stream.prefix(1) { reviews += 1 }
    #expect(reviews == 1)
  }
}

extension AppDelegateTests {
  @Test("Clear Menu clears AppKit's recents, which the welcome window and Open Recent read")
  func testAppDelegate_clearRecentProjects() {
    // Answers the catalog's action without AppKit's own Open Recent machinery (clearRecentDocuments:).
    #expect(AppDelegate.instancesRespond(to: NSSelectorFromString("clearRecentProjects:")))
    #expect(CommandCatalog.command("file.clearRecent")?.action == "clearRecentProjects:")
  }
}
