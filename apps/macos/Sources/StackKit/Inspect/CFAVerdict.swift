/// The probe's answer; `unknown` is a genuine third state that keeps today's behaviour.
package enum CFAVerdict: Sendable {
  case cfa
  case mono
  case unknown
}
