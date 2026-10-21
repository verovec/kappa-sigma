/// Why the store refused a write, with what the user can fix.
package enum ProjectStoreError: Error, Equatable, Sendable {
  /// A saved item (a pipeline) needs a name.
  case emptyName
  /// A JSON body that is not UTF-8 text.
  case notText
}
