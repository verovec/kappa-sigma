/// How the test bundle was compiled: the heavy live suites (real multi-night captures) run only
/// optimised — unoptimised, their Swift passes over 26 MP frames take more than 90 minutes.
enum BuildConfiguration {
  static let optimized: Bool = {
    #if DEBUG
      false
    #else
      true
    #endif
  }()
}
