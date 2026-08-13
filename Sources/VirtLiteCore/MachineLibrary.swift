import Foundation

/// A virtual machine as the interface knows it: where it lives and how it is configured.
public struct Machine: Sendable, Identifiable, Equatable {
    /// The bundle path is the identity. Renaming changes the display name, not the location,
    /// so a machine keeps its identity across a rename (LC-08).
    public var id: URL { bundle.url }

    public var bundle: VMBundle
    public var configuration: VMConfiguration

    public init(bundle: VMBundle, configuration: VMConfiguration) {
        self.bundle = bundle
        self.configuration = configuration
    }

    public var name: String { configuration.name }
}

/// The machines on this Mac.
///
/// The library owns discovery and the file operations that go with it. It deliberately knows
/// nothing about running machines — that belongs to the backend, and keeping them apart is what
/// lets all of this be tested without a hypervisor (ARC-04).
public struct MachineLibrary: Sendable {

    public let directory: URL

    // FileManager is not Sendable, so it is used where needed rather than stored. Tests work
    // against real temporary directories instead of injecting a fake one.
    private var fileManager: FileManager { .default }

    /// Machines live in Application Support by default. Somewhere in the user's home, so Finder
    /// can reach them, but not scattered across the desktop.
    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appending(path: "VirtLite/Machines")
    }

    public init(directory: URL = MachineLibrary.defaultDirectory) {
        self.directory = directory
    }

    // MARK: - Discovery

    /// Everything in the library, sorted by name.
    ///
    /// A bundle whose configuration cannot be read is skipped rather than thrown: one damaged
    /// machine must not stop the other ten from appearing.
    public func machines() throws -> [Machine] {
        guard fileManager.fileExists(atPath: directory.path(percentEncoded: false)) else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return contents
            .filter { $0.pathExtension == VMBundle.fileExtension }
            .compactMap { url in
                let bundle = VMBundle(url: url)
                guard let configuration = try? bundle.loadConfiguration() else { return nil }
                return Machine(bundle: bundle, configuration: configuration)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Bundles that exist but could not be read, so the interface can say so instead of
    /// pretending they are not there.
    public func unreadableBundles() throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path(percentEncoded: false)) else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return contents
            .filter { $0.pathExtension == VMBundle.fileExtension }
            .filter { (try? VMBundle(url: $0).loadConfiguration()) == nil }
    }

    // MARK: - Creating

    /// Creates a machine, giving it a bundle name that does not collide with an existing one.
    public func create(_ configuration: VMConfiguration) throws -> Machine {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = availableURL(for: configuration.name)
        let bundle = try VMBundle.create(at: url, configuration: configuration)
        return Machine(bundle: bundle, configuration: configuration)
    }

    /// `Ubuntu.virtlite`, then `Ubuntu 2.virtlite`, and so on.
    ///
    /// Two machines may share a display name — people do call things "test" twice — but they
    /// cannot share a path.
    func availableURL(for name: String) -> URL {
        let base = sanitized(name)
        var candidate = directory.appending(path: "\(base).\(VMBundle.fileExtension)")
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = directory.appending(path: "\(base) \(suffix).\(VMBundle.fileExtension)")
            suffix += 1
        }

        return candidate
    }

    /// Keeps a display name usable as a file name without mangling it beyond recognition.
    func sanitized(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Virtual Machine" }

        let forbidden = CharacterSet(charactersIn: "/:\\")
        let cleaned = trimmed.components(separatedBy: forbidden).joined(separator: "-")
        return cleaned.isEmpty ? "Virtual Machine" : cleaned
    }

    // MARK: - Removing

    /// How much space deleting a machine would free, so the confirmation can say (LC-09).
    public func sizeOnDisk(of machine: Machine) -> UInt64 {
        guard let enumerator = fileManager.enumerator(
            at: machine.bundle.url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        ) else { return 0 }

        var total: UInt64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
            )
            // Allocated size, not file size: a sparse image claims far more than it occupies,
            // and quoting the claim would promise space that deleting will not return.
            let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0
            total += UInt64(size)
        }

        return total
    }

    public func delete(_ machine: Machine) throws {
        try fileManager.removeItem(at: machine.bundle.url)
    }

    // MARK: - Renaming

    /// Renames a machine without moving its bundle.
    ///
    /// The path stays put on purpose (LC-08): moving it would break saved state, which is
    /// encrypted against a specific machine, and any window already open on it.
    public func rename(_ machine: Machine, to newName: String) throws -> Machine {
        var configuration = machine.configuration
        configuration.name = newName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !configuration.name.isEmpty else { throw VirtLiteError.emptyName }

        try machine.bundle.save(configuration)
        return Machine(bundle: machine.bundle, configuration: configuration)
    }
}
