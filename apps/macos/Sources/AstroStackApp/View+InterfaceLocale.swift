package import SwiftUI

extension View {
  /// Gives a window's content the interface locale (`AppLocale.interface`).
  ///
  /// Its strings, the glossary and `AstroFormat` then speak the same language. Applied once per
  /// window root.
  package func interfaceLocale() -> some View {
    environment(\.locale, AppLocale.interface())
  }
}
