package import Foundation

/// A parsed XML element: S3 answers are small, shallow documents read in full.
package struct XMLNode: Sendable, Equatable {
  /// The element name, without namespace prefix handling (S3 uses a default namespace).
  package var name: String
  /// The element's own text, entities resolved.
  package var text: String
  /// Child elements in document order.
  package var children: [Self]

  /// The first child named `name`.
  package func child(_ name: String) -> Self? { children.first { $0.name == name } }

  /// Every child named `name`.
  package func all(_ name: String) -> [Self] { children.filter { $0.name == name } }

  /// The text of the first child named `name`.
  package func text(_ name: String) -> String? { child(name)?.text }

  /// Parses `data`; throws `invalidResponse` on malformed XML or an empty document.
  package static func parse(_ data: Data) throws -> Self {
    let builder = Builder()
    // S3 may pad a long-running answer (CompleteMultipartUpload) with whitespace before the
    // declaration to keep the connection alive; XMLParser refuses anything before `<?xml`.
    let start = data.firstIndex { !" \t\r\n".utf8.contains($0) } ?? data.endIndex
    let parser = XMLParser(data: Data(data[start...]))
    parser.delegate = builder
    guard parser.parse(), let root = builder.root else {
      let reason = parser.parserError.map { "\($0)" } ?? "empty document"
      throw S3Error.invalidResponse("XML: \(reason)")
    }
    return root
  }

  /// Builds the tree from the parser's callbacks (used on one thread, inside `parse`).
  private final class Builder: NSObject, XMLParserDelegate {
    var stack: [XMLNode] = []
    var root: XMLNode?

    func parser(
      _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
      stack.append(XMLNode(name: elementName, text: "", children: []))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
      guard !stack.isEmpty else { return }
      stack[stack.count - 1].text += string
    }

    func parser(
      _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?
    ) {
      guard let node = stack.popLast() else { return }
      if stack.isEmpty {
        root = node
      } else {
        stack[stack.count - 1].children.append(node)
      }
    }
  }
}
