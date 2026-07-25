import Testing

@testable import GifItCore

private func candidate(
  id: UInt32,
  layer: Int = 0,
  width: Double = 800,
  height: Double = 600,
  bundleIdentifier: String? = nil
) -> WindowCandidate {
  WindowCandidate(
    id: id,
    layer: layer,
    width: width,
    height: height,
    bundleIdentifier: bundleIdentifier
  )
}

@Test func frontmostWindowPolicySkipsFloatingOverlays() {
  let selection = FrontmostWindowPolicy.select(from: [
    candidate(id: 1, layer: 25, bundleIdentifier: "com.example.dictation-hud"),
    candidate(id: 2, layer: 3),
    candidate(id: 3, bundleIdentifier: "com.example.browser"),
  ])

  #expect(selection?.id == 3)
}

@Test func frontmostWindowPolicySkipsTinyWindows() {
  let selection = FrontmostWindowPolicy.select(from: [
    candidate(id: 1, width: 40, height: 40),
    candidate(id: 2, width: 900, height: 60),
    candidate(id: 3),
  ])

  #expect(selection?.id == 3)
}

@Test func frontmostWindowPolicySkipsExcludedBundleIDs() {
  let selection = FrontmostWindowPolicy.select(
    from: [
      candidate(id: 1, bundleIdentifier: "com.example.gif-it"),
      candidate(id: 2, bundleIdentifier: "com.example.editor"),
    ],
    excludingBundleIDs: ["com.example.gif-it"]
  )

  #expect(selection?.id == 2)
}

@Test func frontmostWindowPolicyReturnsNilWhenNothingQualifies() {
  #expect(FrontmostWindowPolicy.select(from: []) == nil)
  #expect(FrontmostWindowPolicy.select(from: [candidate(id: 1, layer: 25)]) == nil)
}
