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
    ProjectDocument.lastDocumentClosed = { fired += 1 }
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
