/// A process whose result may leave 0…1 on purpose (no clip, the stretch takes the range).
///
/// The Studio panel shows the maximum of its preview per channel (card 0120), so the range is
/// seen before Apply. Shown only, never read by the process (R2).
package protocol RangeShown: ImageProcess {}
