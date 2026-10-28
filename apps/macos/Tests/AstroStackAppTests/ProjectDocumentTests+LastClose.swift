import AppKit
import AstroStackApp
import Testing

extension ProjectDocumentTests {
  @Test("closing the last project fires lastDocumentClosed once; closing another one does not")
  func testProjectDocument_lastClose_firesHook() throws {
    let controller = NSDocumentController.shared
    let first = try ProjectDocument(type: Self.type)
    let second = try ProjectDocument(type: Self.type)
    controller.addDocument(first)
    controller.addDocument(second)
    let (hook, documents) = (ProjectDocument.lastDocumentClosed, ProjectDocument.openDocuments)
    defer {
      ProjectDocument.lastDocumentClosed = hook
      ProjectDocument.openDocuments = documents
    }
    var fired = 0
    ProjectDocument.lastDocumentClosed = { _ in fired += 1 }
    // Other suites may hold documents in the shared controller: only these two count here.
    ProjectDocument.openDocuments = {
      controller.documents.filter { $0 === first || $0 === second }
    }

    first.close()
    #expect(fired == 0)
    second.close()
    #expect(fired == 1)
  }
}

extension ProjectDocumentTests {
  @Test("a second close of the last project, or closing a document never shown, fires nothing")
  func testProjectDocument_closeAgain_firesNothing() throws {
    let controller = NSDocumentController.shared
    let shown = try ProjectDocument(type: Self.type)
    let never = try ProjectDocument(type: Self.type)
    controller.addDocument(shown)
    let (hook, documents) = (ProjectDocument.lastDocumentClosed, ProjectDocument.openDocuments)
    defer {
      ProjectDocument.lastDocumentClosed = hook
      ProjectDocument.openDocuments = documents
    }
    var fired = 0
    ProjectDocument.lastDocumentClosed = { _ in fired += 1 }
    ProjectDocument.openDocuments = { controller.documents.filter { $0 === shown } }

    shown.close()
    #expect(fired == 1)
    shown.close()
    never.close()
    #expect(fired == 1)
  }

  @Test("closing quietly says so to the hook; a plain close after does not")
  func testProjectDocument_closeQuietly() throws {
    let controller = NSDocumentController.shared
    let (quiet, plain) = (
      try ProjectDocument(type: Self.type), try ProjectDocument(type: Self.type)
    )
    let (hook, documents) = (ProjectDocument.lastDocumentClosed, ProjectDocument.openDocuments)
    defer {
      ProjectDocument.lastDocumentClosed = hook
      ProjectDocument.openDocuments = documents
    }
    var calls: [Bool] = []
    ProjectDocument.lastDocumentClosed = { calls.append($0) }
    ProjectDocument.openDocuments = {
      controller.documents.filter { $0 === quiet || $0 === plain }
    }

    controller.addDocument(quiet)
    ProjectDocument.closeQuietly([quiet])
    controller.addDocument(plain)
    plain.close()

    #expect(calls == [true, false])
  }
}
