import Foundation
import GifItCore
import Testing

@Test func happyPathMovesThroughEveryCapturePhase() {
  var machine = CaptureStateMachine()

  var accepted = machine.handle(.requestPicker)
  #expect(accepted)
  #expect(machine.phase == .picking)
  accepted = machine.handle(.pickerSelected)
  #expect(accepted)
  #expect(machine.phase == .starting)
  accepted = machine.handle(.recordingStarted)
  #expect(accepted)
  #expect(machine.phase == .recording)
  accepted = machine.handle(.stopRequested)
  #expect(accepted)
  accepted = machine.handle(.recordingFinalized)
  #expect(accepted)
  accepted = machine.handle(.conversionProgress(0.5))
  #expect(accepted)
  #expect(machine.phase == .converting(progress: 0.5))
  accepted = machine.handle(.conversionFinished)
  #expect(accepted)
  #expect(machine.phase == .delivering)
  accepted = machine.handle(.deliveryFinished)
  #expect(accepted)
  #expect(machine.phase == .idle)
}

@Test func startupCancellationAndLateCallbacksCannotRestartWorkflow() {
  var machine = CaptureStateMachine()

  var accepted = machine.handle(.requestPicker)
  #expect(accepted)
  accepted = machine.handle(.pickerSelected)
  #expect(accepted)
  #expect(machine.phase == .starting)
  accepted = machine.handle(.pickerCancelled)
  #expect(accepted)
  #expect(machine.phase == .idle)
  accepted = machine.handle(.recordingStarted)
  #expect(!accepted)
  accepted = machine.handle(.stopRequested)
  #expect(!accepted)
  #expect(machine.phase == .idle)
}

@Test func unexpectedFinishDuringStartupOwnsFinalizationAndRejectsLateStart() {
  var machine = CaptureStateMachine()

  var accepted = machine.handle(.requestPicker)
  #expect(accepted)
  accepted = machine.handle(.pickerSelected)
  #expect(accepted)
  accepted = machine.handle(.stopRequested)
  #expect(accepted)
  #expect(machine.phase == .finalizing)
  accepted = machine.handle(.recordingStarted)
  #expect(!accepted)
  accepted = machine.handle(.recordingFinalized)
  #expect(accepted)
  accepted = machine.handle(.recordingFinalized)
  #expect(!accepted)
}

@Test func invalidDuplicateEventsAreIgnored() {
  var machine = CaptureStateMachine()

  var accepted = machine.handle(.stopRequested)
  #expect(!accepted)
  accepted = machine.handle(.requestPicker)
  #expect(accepted)
  accepted = machine.handle(.requestPicker)
  #expect(!accepted)
  #expect(machine.phase == .picking)
}

@Test func cancellationAndFailureRecover() {
  var machine = CaptureStateMachine()

  var accepted = machine.handle(.requestPicker)
  #expect(accepted)
  accepted = machine.handle(.pickerCancelled)
  #expect(accepted)
  #expect(machine.phase == .idle)
  accepted = machine.handle(.failed("Capture stopped"))
  #expect(accepted)
  #expect(machine.phase == .failed(message: "Capture stopped"))
  accepted = machine.handle(.requestPicker)
  #expect(accepted)
  #expect(machine.phase == .picking)
}

@Test func recoveryPolicyPreservesOnlyPlausibleFailureOutputAndCleansWorkingFile() {
  let working = URL(fileURLWithPath: "/tmp/working.mp4")
  let recorderOutput = URL(fileURLWithPath: "/tmp/recovery.mp4")
  let plan = ArtifactRecoveryPolicy.plan(
    currentWorkingURL: working,
    existingLastArtifact: nil,
    recorderOutputURL: recorderOutput,
    explicitRecoveryURL: nil,
    isPlausible: { $0 == recorderOutput }
  )

  #expect(plan.preservedArtifact == recorderOutput)
  #expect(plan.abandonedArtifacts == [working])

  let emptyOutputPlan = ArtifactRecoveryPolicy.plan(
    currentWorkingURL: working,
    existingLastArtifact: nil,
    recorderOutputURL: working,
    explicitRecoveryURL: nil,
    isPlausible: { _ in false }
  )
  #expect(emptyOutputPlan.preservedArtifact == nil)
  #expect(emptyOutputPlan.abandonedArtifacts == [working])
}

@Test func recoveryPolicyKeepsPriorArtifactAcrossDeliveryFailure() {
  let working = URL(fileURLWithPath: "/tmp/working.mp4")
  let deliveredArtifact = URL(fileURLWithPath: "/tmp/Capture.gif")
  let plan = ArtifactRecoveryPolicy.plan(
    currentWorkingURL: working,
    existingLastArtifact: deliveredArtifact,
    recorderOutputURL: nil,
    explicitRecoveryURL: nil,
    isPlausible: { $0 == deliveredArtifact }
  )

  #expect(plan.preservedArtifact == deliveredArtifact)
  #expect(plan.abandonedArtifacts == [working])
}

@Test func recoveryPolicyPreservesSourceAfterExportFailure() {
  let source = URL(fileURLWithPath: "/tmp/working.mp4")
  let staleRecorderOutput = URL(fileURLWithPath: "/tmp/stale.mp4")
  let plan = ArtifactRecoveryPolicy.plan(
    currentWorkingURL: source,
    existingLastArtifact: nil,
    recorderOutputURL: staleRecorderOutput,
    explicitRecoveryURL: source,
    isPlausible: { $0 == source }
  )

  #expect(plan.preservedArtifact == source)
  #expect(plan.abandonedArtifacts.isEmpty)
}

@Test func terminationActionsCoverEveryInFlightWorkflowBoundary() {
  #expect(TerminationAction(phase: .idle) == .teardown)
  #expect(TerminationAction(phase: .failed(message: "failed")) == .teardown)
  #expect(TerminationAction(phase: .picking) == .dismissPicker)
  #expect(TerminationAction(phase: .starting) == .cancelStartupAndRecover)
  #expect(TerminationAction(phase: .recording) == .finalizeRecording)
  #expect(TerminationAction(phase: .finalizing) == .awaitFinalization)
  #expect(TerminationAction(phase: .converting(progress: 0.5)) == .awaitFinalization)
  #expect(TerminationAction(phase: .delivering) == .awaitFinalization)
}
