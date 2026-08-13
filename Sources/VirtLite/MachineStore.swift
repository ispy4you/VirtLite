import Foundation
import Observation
import VirtLiteCore
import VirtLiteVZ

/// One machine as the interface sees it: its configuration, and what it is doing right now.
@Observable
@MainActor
final class MachineEntry: Identifiable {
    let machine: Machine
    var state: VMState = .stopped

    /// Present only while the machine is running. A stopped machine is a bundle on disk and
    /// nothing more.
    var running: (any VMLifecycle)?

    /// Attached until the user ejects it (INS-01).
    ///
    /// Deliberately not dropped when the machine stops: a guest that failed to boot, or that was
    /// shut down halfway through installation, still needs its installer next time.
    var installerISO: URL?

    /// Set when a machine stops so quickly that it plainly had nothing to boot.
    ///
    /// Without this the interface shows a machine going straight back to Stopped and says
    /// nothing, which reads as the app being broken (NFR-06, NFR-11).
    var hint: String?

    fileprivate var startedAt: Date?

    // Identifiable is reached from outside the main actor, and both of these read an immutable
    // Sendable value, so they are safe to expose without isolation.
    nonisolated var id: URL { machine.id }
    nonisolated var name: String { machine.name }

    init(machine: Machine) {
        self.machine = machine
    }
}

/// Everything the interface knows about machines on this Mac.
@Observable
@MainActor
final class MachineStore {

    private(set) var entries: [MachineEntry] = []
    private(set) var damagedBundles: [URL] = []
    var lastError: String?

    private let library: MachineLibrary
    private let backend = VZBackend()
    private let installers = InstallerImageStore()

    var hardwareLimits: HardwareLimits { backend.hardwareLimits }

    init(library: MachineLibrary = MachineLibrary()) {
        self.library = library
        reload()
    }

    func reload() {
        do {
            let found = try library.machines()

            // Keep the entries that already exist, so a running machine survives a reload
            // rather than being replaced by a fresh stopped one.
            let existing = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
            entries = found.map { machine in
                if let entry = existing[machine.id], entry.state.isActive {
                    return entry
                }
                let entry = MachineEntry(machine: machine)
                // An installer outlives the app session; forgetting it leaves a machine that
                // cannot boot and cannot say why.
                entry.installerISO = installers.installer(for: machine.id)
                return entry
            }

            damagedBundles = (try? library.unreadableBundles()) ?? []
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Creating

    func create(
        name: String,
        cpuCount: Int,
        memoryInBytes: UInt64,
        diskSizeInBytes: UInt64,
        installerISO: URL?
    ) throws -> MachineEntry {
        let configuration = VMConfiguration(
            name: name,
            guest: .linux,
            cpuCount: cpuCount,
            memoryInBytes: memoryInBytes,
            disks: [
                DiskConfiguration(
                    fileName: VMBundle.Entry.primaryDisk,
                    sizeInBytes: diskSizeInBytes
                )
            ]
        )

        // Validated before anything touches the disk, so a rejected machine leaves nothing
        // behind to clean up (VM-06, VM-07).
        try configuration.validate(against: backend.hardwareLimits)

        let machine = try library.create(configuration)
        try VZDiskImage.create(at: machine.bundle.primaryDiskURL, sizeInBytes: diskSizeInBytes)

        let entry = MachineEntry(machine: machine)
        entry.installerISO = installerISO
        if let installerISO {
            installers.remember(installerISO, for: machine.id)
        }
        entries.append(entry)
        entries.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return entry
    }

    // MARK: - Running

    func start(_ entry: MachineEntry) async {
        do {
            let machine: any VMLifecycle

            // An installer image stays attached only until the guest has a system of its own.
            // Forgetting to drop it means booting the installer forever (INS-01).
            if let iso = entry.installerISO {
                machine = try backend.makeMachineForInstallation(
                    for: entry.machine.bundle,
                    configuration: entry.machine.configuration,
                    installerISO: iso
                )
            } else {
                machine = try backend.makeMachine(
                    for: entry.machine.bundle,
                    configuration: entry.machine.configuration
                )
            }

            entry.running = machine
            entry.hint = nil
            entry.startedAt = Date()
            follow(machine, for: entry)
            try await machine.start()
        } catch {
            entry.state = .error
            lastError = error.localizedDescription
        }
    }

    /// Mirrors the machine's own state into the entry the interface observes.
    private func follow(_ machine: any VMLifecycle, for entry: MachineEntry) {
        Task { @MainActor in
            for await state in machine.stateUpdates {
                entry.state = state

                if state == .stopped || state == .error {
                    entry.running = nil
                    noteImmediateStop(entry)
                }
            }
        }
    }

    /// A guest that powers off within a couple of seconds did not boot — it found nothing to
    /// boot from. Saying so is the difference between a bug report and a shrug.
    private func noteImmediateStop(_ entry: MachineEntry) {
        guard let startedAt = entry.startedAt else { return }
        entry.startedAt = nil

        guard Date().timeIntervalSince(startedAt) < 5 else { return }

        if entry.installerISO == nil {
            entry.hint = "The guest powered off immediately. This machine has no operating system on its disk and no installer image attached — choose one to install a system."
        } else {
            entry.hint = "The guest powered off immediately. The attached image may not be bootable here: it has to be built for ARM64, since Apple Silicon cannot run x86_64 systems."
        }
    }

    /// Detaches the installer once a system is installed (INS-01).
    ///
    /// Explicit rather than automatic: nothing on the host can reliably tell a finished
    /// installation from an abandoned one, and guessing wrong leaves a machine unable to boot.
    func ejectInstaller(from entry: MachineEntry) {
        entry.installerISO = nil
        installers.forget(for: entry.id)
    }

    func attachInstaller(_ url: URL, to entry: MachineEntry) {
        entry.installerISO = url
        entry.hint = nil
        installers.remember(url, for: entry.id)
    }

    func requestStop(_ entry: MachineEntry) async {
        await perform(on: entry) { try await $0.requestStop() }
    }

    func forceStop(_ entry: MachineEntry) async {
        await perform(on: entry) { try await $0.forceStop() }
    }

    func pause(_ entry: MachineEntry) async {
        await perform(on: entry) { try await $0.pause() }
    }

    func resume(_ entry: MachineEntry) async {
        await perform(on: entry) { try await $0.resume() }
    }

    private func perform(
        on entry: MachineEntry,
        _ action: (any VMLifecycle) async throws -> Void
    ) async {
        guard let machine = entry.running else { return }
        do {
            try await action(machine)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Removing

    func sizeOnDisk(of entry: MachineEntry) -> UInt64 {
        library.sizeOnDisk(of: entry.machine)
    }

    func delete(_ entry: MachineEntry, removingFiles: Bool) {
        do {
            if removingFiles {
                try library.delete(entry.machine)
            }
            installers.forget(for: entry.id)
            entries.removeAll { $0.id == entry.id }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
