import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import TestSupport
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
    let controller = NSDocumentController.shared
    let document = try ProjectDocument(type: ProjectPackage.typeIdentifier)
    controller.addDocument(document)
    let (hook, documents) = (ProjectDocument.lastDocumentClosed, ProjectDocument.openDocuments)
    defer {
      ProjectDocument.lastDocumentClosed = hook
      ProjectDocument.openDocuments = documents
    }
    var shown = 0
    let delegate = AppDelegate(welcome: { shown += 1 }, reviewRetention: {})
    delegate.applicationWillFinishLaunching(
      Notification(name: NSApplication.willFinishLaunchingNotification))
    // This document is the only one that counts: closing it is the last close.
    ProjectDocument.openDocuments = { controller.documents.filter { $0 === document } }

    // Only this test's document: another suite's documents stay open.
    delegate.closeForQuit([document])

    #expect(!controller.documents.contains(document))
    #expect(shown == 0)
  }

  @Test("launching arms the hook: the last project closed brings the welcome window back")
  func testAppDelegate_willFinishLaunching_setsWelcomeHook() {
    let hook = ProjectDocument.lastDocumentClosed
    defer { ProjectDocument.lastDocumentClosed = hook }
    var (shown, reviews) = (0, 0)
    let delegate = AppDelegate(welcome: { shown += 1 }, reviewRetention: { reviews += 1 })

    delegate.applicationWillFinishLaunching(
      Notification(name: NSApplication.willFinishLaunchingNotification))
    ProjectDocument.lastDocumentClosed(false)
    // From the Dock afterwards: the welcome window, never a review over the project just closed.
    _ = delegate.applicationOpenUntitledFile(NSApplication.shared)

    #expect(shown == 2)
    #expect(reviews == 0)
  }

  @Test("a relaunch's quiet closes show no welcome window and disarm the launch review too")
  func testAppDelegate_quietLastClose_disarmsReview() {
    let hook = ProjectDocument.lastDocumentClosed
    defer { ProjectDocument.lastDocumentClosed = hook }
    var (shown, reviews) = (0, 0)
    let delegate = AppDelegate(welcome: { shown += 1 }, reviewRetention: { reviews += 1 })

    delegate.applicationWillFinishLaunching(
      Notification(name: NSApplication.willFinishLaunchingNotification))
    ProjectDocument.lastDocumentClosed(true)
    #expect(shown == 0)
    _ = delegate.applicationOpenUntitledFile(NSApplication.shared)

    #expect(shown == 1)
    #expect(reviews == 0)
  }

  @Test("a launch without a project reviews the stacks once, from the first welcome window")
  func testAppDelegate_launchReviewsOnce() {
    var (shown, reviews) = (0, 0)
    let hook = ProjectDocument.lastDocumentClosed
    defer { ProjectDocument.lastDocumentClosed = hook }
    let delegate = AppDelegate(welcome: { shown += 1 }, reviewRetention: { reviews += 1 })

    delegate.applicationWillFinishLaunching(
      Notification(name: NSApplication.willFinishLaunchingNotification))
    _ = delegate.applicationOpenUntitledFile(NSApplication.shared)
    _ = delegate.applicationOpenUntitledFile(NSApplication.shared)

    #expect(shown == 2)
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

extension AppDelegateTests {
  @Test("Clear Menu is enabled with any recent, a deleted package's too; other items stay enabled")
  func testAppDelegate_validatesClearMenu() {
    let (kept, gone) = (
      URL(fileURLWithPath: "/tmp/M 31.astrostack"), URL(fileURLWithPath: "/tmp/Gone.astrostack")
    )
    let clear = NSMenuItem(
      title: "", action: NSSelectorFromString("clearRecentProjects:"), keyEquivalent: "")
    let other = NSMenuItem(
      title: "", action: NSSelectorFromString("showWelcome:"), keyEquivalent: "")
    for (recents, enabled) in [([kept, gone], true), ([gone], true), ([], false)] {
      let delegate = AppDelegate(recentURLs: { recents })
      #expect(delegate.validateMenuItem(clear) == enabled, "\(recents.map(\.lastPathComponent))")
      #expect(delegate.validateMenuItem(other))
    }
  }
}
