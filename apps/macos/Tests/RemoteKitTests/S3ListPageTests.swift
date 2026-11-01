import Foundation
import RemoteKit
import Testing

@Suite("Malformed S3 answers are errors, never empty results")
struct S3ListPageTests {
  @Test(
    "a listing that is not one, or an entry without Key or Size, is invalidResponse",
    arguments: [
      "<Error><Code>X</Code></Error>",
      "<ListBucketResult><Contents><Key>k</Key></Contents></ListBucketResult>",
      "<ListBucketResult><Contents><Size>1</Size></Contents></ListBucketResult>",
    ])
  func testMalformedListing(body: String) {
    #expect(throws: S3Error.self) { try S3ListPage.parse(Data(body.utf8)) }
  }

  @Test("an unreadable Last-Modified is no date, not a failure")
  func testDates() {
    #expect(S3Dates.http("yesterday") == nil)
    #expect(S3Dates.iso8601("2026-10-18T21:04:05Z") != nil)
  }
}
