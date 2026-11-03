/// One level of a bucket (card 0169): the objects directly under a prefix, and the sub-prefixes
/// below it — what a `delimiter=/` listing answers, so « Browse » can walk a bucket like folders
/// without ever listing the whole thing.
package struct S3Listing: Sendable, Equatable {
  /// The objects of this level, in key order.
  package let objects: [S3Object]
  /// The sub-prefixes of this level (each ending in the delimiter), in order.
  package let prefixes: [String]

  /// A level of `objects` and `prefixes`.
  package init(objects: [S3Object], prefixes: [String]) {
    self.objects = objects
    self.prefixes = prefixes
  }
}
