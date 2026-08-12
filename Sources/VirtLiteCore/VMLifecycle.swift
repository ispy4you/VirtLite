import Foundation

/// What a virtual machine is doing right now (LC-04, UI-04).
public enum VMState: String, Sendable, Equatable {
    case stopped
    case starting
    case running
    case pausing
    case paused
    case resuming
    case stopping
    case error
}

/// The contract between the interface and a virtualization backend.
///
/// This protocol is the whole reason the core and the backend are separate targets. It is drawn at
/// the lifecycle, not at individual devices: anything finer would be an abstraction over one
/// framework pretending to be general (ARC-02).
public protocol VMLifecycle: AnyObject, Sendable {
    var state: VMState { get async }

    func start() async throws
    /// Asks the guest to shut down. The guest may refuse or take its time.
    func requestStop() async throws
    /// Cuts the power. Equivalent to pulling the plug on real hardware (LC-02).
    func forceStop() async throws

    func pause() async throws
    func resume() async throws

    /// Writes machine state so the VM can resume after the app quits (LC-05).
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
