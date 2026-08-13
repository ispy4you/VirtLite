import Foundation
import Virtualization
import VirtLiteCore

/// A running virtual machine, backed by `VZVirtualMachine`.
///
/// Everything the framework touches happens on `queue`. This is not a stylistic choice: the
/// framework requires it, and breaking the rule produces crashes that only appear under load,
/// long after the code that caused them (ARC-03). The rest of the app never sees that queue —
/// it awaits, and the hop happens here.
///
/// That queue is the main one. A machine that shows a screen has to be, because
/// `VZVirtualMachineView` binds to the machine from the main thread, and a machine cannot live
/// on two queues at once. The framework does its actual work off-thread regardless; what runs
/// here is bookkeeping and completion handlers.
public final class VZMachine: NSObject, VMLifecycle, @unchecked Sendable {

    private let queue: DispatchQueue
    private let configuration: VZVirtualMachineConfiguration

    /// Only ever touched on `queue`.
    private var machine: VZVirtualMachine!

    private let stateLock = NSLock()
    private var currentState: VMState = .stopped

    private let updates: AsyncStream<VMState>
    private let updateContinuation: AsyncStream<VMState>.Continuation

    public init(configuration: VZVirtualMachineConfiguration, name: String) {
        self.configuration = configuration
        self.queue = .main

        let (stream, continuation) = AsyncStream<VMState>.makeStream(
            bufferingPolicy: .bufferingNewest(16)
        )
        self.updates = stream
        self.updateContinuation = continuation

        super.init()

        // The machine is created on its queue as well — the framework is particular about this
        // from the moment the object exists, not merely once it is running.
        if Thread.isMainThread {
            self.machine = VZVirtualMachine(configuration: configuration, queue: queue)
            self.machine.delegate = self
        } else {
            queue.sync {
                self.machine = VZVirtualMachine(configuration: configuration, queue: queue)
                self.machine.delegate = self
            }
        }
    }

    /// A view showing the guest's screen.
    ///
    /// This is the one place a framework type crosses into the interface, and the exception is
    /// deliberate: `VZVirtualMachineView` is an NSView handing over a framebuffer and input, and
    /// wrapping it in an abstraction would buy nothing (ARC-02). The interface receives an
    /// NSView and never names a VZ type.
    @MainActor
    public func makeScreenView() -> NSView {
        let view = VZVirtualMachineView()
        view.virtualMachine = machine
        // Without this the guest never receives a keystroke — the view has to be told it is
        // allowed to take over input (HW-05).
        view.capturesSystemKeys = true
        return view
    }

    deinit {
        updateContinuation.finish()
    }

    // MARK: - State

    public var state: VMState {
        get async {
            stateLock.withLock { currentState }
        }
    }

    public var stateUpdates: AsyncStream<VMState> { updates }

    /// Records a transition and publishes it.
    ///
    /// An unexpected transition is logged rather than swallowed: it means the model and the
    /// framework disagree, which is worth knowing about before it becomes a bug report about
    /// buttons doing nothing.
    private func transition(to next: VMState) {
        let changed: Bool = stateLock.withLock {
            guard currentState != next else { return false }
            if !currentState.canTransition(to: next) {
                print("[VirtLite] unexpected transition \(currentState) -> \(next)")
            }
            currentState = next
            return true
        }

        if changed {
            updateContinuation.yield(next)
        }
    }

    // MARK: - Lifecycle

    public func start() async throws {
        transition(to: .starting)
        do {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    self.machine.start { result in
                        continuation.resume(with: result)
                    }
                }
            }
            transition(to: .running)
        } catch {
            transition(to: .error)
            throw error
        }
    }

    public func requestStop() async throws {
        transition(to: .stopping)
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                queue.async {
                    do {
                        // Only a request. The guest decides whether and when to honour it, and
                        // the state only reaches .stopped when the delegate says so.
                        try self.machine.requestStop()
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            transition(to: .error)
            throw error
        }
    }

    public func forceStop() async throws {
        transition(to: .stopping)
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                queue.async {
                    self.machine.stop { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            }
            transition(to: .stopped)
        } catch {
            transition(to: .error)
            throw error
        }
    }

    public func pause() async throws {
        transition(to: .pausing)
        do {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    self.machine.pause { result in
                        continuation.resume(with: result)
                    }
                }
            }
            transition(to: .paused)
        } catch {
            transition(to: .error)
            throw error
        }
    }

    public func resume() async throws {
        transition(to: .resuming)
        do {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    self.machine.resume { result in
                        continuation.resume(with: result)
                    }
                }
            }
            transition(to: .running)
        } catch {
            transition(to: .error)
            throw error
        }
    }

    // MARK: - Saved state

    public var supportsSavedState: Bool {
        (try? configuration.validateSaveRestoreSupport()) != nil
    }

    public func saveState(to url: URL) async throws {
        // Saving a running machine fails inside the framework. Pausing first is part of the
        // operation, not something to ask the caller to remember (LC-05).
        let wasRunning = await state == .running
        if wasRunning {
            try await pause()
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.machine.saveMachineStateTo(url: url) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    public func restoreState(from url: URL) async throws {
        transition(to: .starting)
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                queue.async {
                    self.machine.restoreMachineStateFrom(url: url) { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            }
            // Restoring leaves the machine paused; running it again is a separate step.
            transition(to: .paused)
            try await resume()
        } catch {
            transition(to: .error)
            throw error
        }
    }
}

// MARK: - VZVirtualMachineDelegate

extension VZMachine: VZVirtualMachineDelegate {

    /// The guest shut itself down. Not an error, and not something the app asked for.
    public func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        transition(to: .stopped)
    }

    public func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        print("[VirtLite] guest stopped with an error: \(error.localizedDescription)")
        transition(to: .error)
    }

    public func virtualMachine(
        _ virtualMachine: VZVirtualMachine,
        networkDevice: VZNetworkDevice,
        attachmentWasDisconnectedWithError error: Error
    ) {
        // The machine keeps running without a network, so this is reported rather than fatal.
        print("[VirtLite] network detached: \(error.localizedDescription)")
    }
}
