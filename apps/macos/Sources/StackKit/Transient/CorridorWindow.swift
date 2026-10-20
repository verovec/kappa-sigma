/// One 64-step stretch of a segment's swath (`corridorWindow`): the unique plane indices inside
/// the swath over t ∈ [t0, t1].
struct CorridorWindow {
  var t0: Double
  var t1: Double
  var pixels: [Int] = []
}
