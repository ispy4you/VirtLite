import Testing
@testable import VirtLiteCore

@Suite("Machine state transitions")
struct VMStateTests {

    @Test("A stopped machine can only start")
    func fromStopped() {
        #expect(VMState.stopped.canTransition(to: .starting))
        #expect(!VMState.stopped.canTransition(to: .running))
        #expect(!VMState.stopped.canTransition(to: .paused))
        #expect(!VMState.stopped.canTransition(to: .stopping))
    }

    @Test("The pause and resume round trip is legal")
    func pauseRoundTrip() {
        #expect(VMState.running.canTransition(to: .pausing))
        #expect(VMState.pausing.canTransition(to: .paused))
        #expect(VMState.paused.canTransition(to: .resuming))
        #expect(VMState.resuming.canTransition(to: .running))
    }

    /// A guest can shut itself down or crash at any moment. Treating that as an invalid
    /// transition would mean logging a warning every time someone types `poweroff`.
    @Test("An active machine may stop on its own", arguments: [
        VMState.starting, .running, .pausing, .paused, .resuming, .stopping,
    ])
    func guestMayStopItself(from state: VMState) {
        #expect(state.canTransition(to: .stopped))
    }

    @Test("Failure can interrupt anything", arguments: VMState.allCases)
    func failureAlwaysAllowed(from state: VMState) {
        #expect(state.canTransition(to: .error))
    }

    @Test("A failed machine starts over rather than resuming")
    func recoveryFromError() {
        #expect(VMState.error.canTransition(to: .starting))
        #expect(!VMState.error.canTransition(to: .running))
        #expect(!VMState.error.canTransition(to: .resuming))
    }

    @Test("A stopped machine cannot be paused or resumed")
    func noPausingStoppedMachines() {
        #expect(!VMState.stopped.canTransition(to: .pausing))
        #expect(!VMState.stopped.canTransition(to: .resuming))
    }

    @Test("Transitional states are the ones that finish on their own", arguments: [
        VMState.starting, .pausing, .resuming, .stopping,
    ])
    func transitionalStates(state: VMState) {
        #expect(state.isTransitional)
    }

    @Test("Settled states are not transitional", arguments: [
        VMState.stopped, .running, .paused, .error,
    ])
    func settledStates(state: VMState) {
        #expect(!state.isTransitional)
    }

    /// Drives what the inspector may edit: anything with a guest attached is off limits (UI-06).
    @Test("Only stopped and failed machines are inactive")
    func activeStates() {
        #expect(!VMState.stopped.isActive)
        #expect(!VMState.error.isActive)

        for state in VMState.allCases where state != .stopped && state != .error {
            #expect(state.isActive, "\(state) should count as active")
        }
    }
}
