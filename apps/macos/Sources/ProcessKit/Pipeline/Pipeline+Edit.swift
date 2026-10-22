extension Pipeline {
  /// The pipeline without step `index` (card 0107); unchanged when there is no such step.
  package func removing(at index: Int) -> Pipeline {
    guard steps.indices.contains(index) else { return self }
    var edited = self
    edited.steps.remove(at: index)
    return edited
  }

  /// The pipeline with step `from` moved so it is step `to` (card 0107), its breakpoint and lock
  /// with it; unchanged when either is not a step.
  package func moving(from: Int, to: Int) -> Pipeline {
    guard steps.indices.contains(from), steps.indices.contains(to) else { return self }
    var edited = self
    edited.steps.insert(edited.steps.remove(at: from), at: to)
    return edited
  }
}
