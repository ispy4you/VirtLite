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

    /// Attached until the guest has a system of its own, then dropped (INS-01).
    var installerISO: URL?

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
                return MachineEntry(machine: machine)
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
                    // The installer has done its job; from here the machine boots its own disk.
                    entry.installerISO = nil
                }
            }
        }
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
            entries.removeAll { $0.id == entry.id }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
