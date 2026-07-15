import Testing
@testable import GifItMac

@Test func recorderLifecycleRejectsOverlappingSessionsAndStaleEvents() {
  var lifecycle = RecorderLifecycle()

  let beganFirst = lifecycle.begin(41)
  let beganSecond = lifecycle.begin(42)
  #expect(beganFirst)
  #expect(!beganSecond)
  #expect(lifecycle.accepts(41))
  #expect(!lifecycle.accepts(42))
  let startedStale = lifecycle.captureStarted(42)
  let startedActive = lifecycle.captureStarted(41)
  #expect(!startedStale)
  #expect(startedActive)
  #expect(lifecycle.phase == .recording(41))
}

@Test func recorderLifecycleMakesStopIdempotent() {
  var lifecycle = RecorderLifecycle()
  let began = lifecycle.begin(1)
  let started = lifecycle.captureStarted(1)
  #expect(began)
  #expect(started)

  let firstStop = lifecycle.requestStop(1)
  let secondStop = lifecycle.requestStop(1)
  #expect(firstStop == .begin)
  #expect(secondStop == .join)
  #expect(lifecycle.phase == .stopping(1))
  let staleStop = lifecycle.requestStop(2)
  #expect(staleStop == .unavailable)
}

@Test func recorderLifecycleRetainsSessionThroughTeardown() {
  var lifecycle = RecorderLifecycle()
  let began = lifecycle.begin(7)
  let started = lifecycle.captureStarted(7)
  let stopped = lifecycle.requestStop(7)
  #expect(began)
  #expect(started)
  #expect(stopped == .begin)

  let beganTeardown = lifecycle.beginTeardown(7)
  #expect(beganTeardown)
  #expect(lifecycle.accepts(7))
  #expect(lifecycle.phase == .tearingDown(7))
  let finishedStale = lifecycle.finishTeardown(8)
  #expect(!finishedStale)
  #expect(lifecycle.accepts(7))
  let finishedActive = lifecycle.finishTeardown(7)
  #expect(finishedActive)
  #expect(lifecycle.phase == .idle)
  #expect(!lifecycle.accepts(7))
}

@Test func recorderLifecycleCanTeardownDuringStartup() {
  var lifecycle = RecorderLifecycle()
  let began = lifecycle.begin(99)
  #expect(began)

  let beganTeardown = lifecycle.beginTeardown(99)
  let lateStart = lifecycle.captureStarted(99)
  let finished = lifecycle.finishTeardown(99)
  #expect(beganTeardown)
  #expect(!lateStart)
  #expect(finished)
  #expect(lifecycle.isIdle)
}
