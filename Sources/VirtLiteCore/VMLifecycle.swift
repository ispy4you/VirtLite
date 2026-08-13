import Foundation

/// What a virtual machine is doing right now (LC-04, UI-04).
public enum VMState: String, Sendable, Equatable, CaseIterable {
    case stopped
    case starting
    case running
    case pausing
    case paused
    case resuming
    case stopping
    case error
}

extension VMState {
    /// Whether the machine is doing something that will finish on its own.
    ///
    /// The interface uses this to show progress and to refuse commands that would arrive
    /// mid-transition — the framework rejects them anyway, but with an error the user did not
    /// ask for.
    public var isTransitional: Bool {
        switch self {
        case .starting, .pausing, .resuming, .stopping: return true
        case .stopped, .running, .paused, .error: return false
        }
    }

    /// Whether the guest is executing. Settings that cannot change under a running machine key
    /// off this (UI-06).
    public var isActive: Bool {
        switch self {
        case .running, .paused, .starting, .pausing, .resuming, .stopping: return true
        case .stopped, .error: return false
        }
    }

    /// The transitions a machine may legitimately make.
    ///
    /// This is the model's own rule, not the framework's: it exists so the interface can decide
    /// what to offer without asking the backend, and so an out-of-order transition shows up as a
    /// bug here rather than as a puzzling framework error later.
    public func canTransition(to next: VMState) -> Bool {
        switch (self, next) {
        case (.stopped, .starting),
             (.starting, .running),
             (.running, .pausing),
             (.pausing, .paused),
             (.paused, .resuming),
             (.resuming, .running),
             (.running, .stopping),
             (.paused, .stopping),
             (.stopping, .stopped),
             (.starting, .stopped):
            return true

        // A guest can stop on its own at any moment — it was shut down from inside, or it
        // crashed. Nothing about that is invalid.
        case (_, .stopped) where self.isActive:
            return true

        // Failure can interrupt anything.
        case (_, .error):
            return true

        // Recovering from failure starts over.
        case (.error, .starting):
            return true

        default:
            return false
        }
    }
}

/// The contract between the interface and a virtualization backend.
///
/// This protocol is the whole reason the core and the backend are separate targets. It is drawn at
/// the lifecycle, not at individual devices: anything finer would be an abstraction over one
/// framework pretending to be general (ARC-02).
public protocol VMLifecycle: AnyObject, Sendable {
    var state: VMState { get async }

    /// State changes as they happen, including ones nobody asked for — a guest shutting itself
    /// down, or failing.
    var stateUpdates: AsyncStream<VMState> { get }

    func start() async throws
    /// Asks the guest to shut down. The guest may refuse or take its time.
    func requestStop() async throws
    /// Cuts the power. Equivalent to pulling the plug on real hardware (LC-02).
    func forceStop() async throws

    func pause() async throws
    func resume() async throws

    /// Whether this machine's configuration can be saved at all.
    ///
    /// Not every configuration can: the framework decides, and it decides at runtime. Asking
    /// before offering the command is the difference between a feature and a broken promise.
    var supportsSavedState: Bool { get }

    /// Writes machine state so the VM can resume after the app quits (LC-05).
    ///
    /// The machine must be paused first. The resulting file is encrypted against this host and
    /// cannot be moved to another Mac (LC-11).
    func saveState(to url: URL) async throws
    /// Restores previously saved state instead of cold-booting (LC-06).
    func restoreState(from url: URL) async throws
}

/// A backend capable of producing running machines from bundles.
public protocol VMBackendProviding: Sendable {
    /// The hardware ranges this host supports, read from the platform rather than hardcoded (HW-01).
    var hardwareLimits: HardwareLimits { get }

    func makeMachine(for bundle: VMBundle, configuration: VMConfiguration) throws -> any VMLifecycle
}
