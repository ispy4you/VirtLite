import Foundation

/// The hardware ranges a virtual machine may be configured within.
///
/// The core does not know these values: they come from the virtualization backend, which reads
/// them from the framework at runtime rather than hardcoding constants (HW-01). The core only
/// validates a configuration against whatever limits it is given.
public struct HardwareLimits: Sendable, Equatable {
    public var minimumMemoryInBytes: UInt64
    public var maximumMemoryInBytes: UInt64
    public var minimumCPUCount: Int
    public var maximumCPUCount: Int

    public init(
        minimumMemoryInBytes: UInt64,
        maximumMemoryInBytes: UInt64,
        minimumCPUCount: Int,
        maximumCPUCount: Int
    ) {
        self.minimumMemoryInBytes = minimumMemoryInBytes
        self.maximumMemoryInBytes = maximumMemoryInBytes
        self.minimumCPUCount = minimumCPUCount
        self.maximumCPUCount = maximumCPUCount
    }
}

extension VMConfiguration {
    /// Checks the configuration against the limits reported by the backend.
    ///
    /// Errors are deliberately specific: a message that names the allowed range is the difference
    /// between a user fixing the problem and filing an issue (NFR-06).
    public func validate(against limits: HardwareLimits) throws {
        guard formatVersion <= VMConfiguration.currentFormatVersion else {
            throw VirtLiteError.bundleFormatTooNew(
                found: formatVersion,
                supported: VMConfiguration.currentFormatVersion
            )
        }

        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VirtLiteError.emptyName
        }

        guard (limits.minimumCPUCount...limits.maximumCPUCount).contains(cpuCount) else {
            throw VirtLiteError.cpuCountOutOfRange(
                requested: cpuCount,
                minimum: limits.minimumCPUCount,
                maximum: limits.maximumCPUCount
            )
        }

        guard (limits.minimumMemoryInBytes...limits.maximumMemoryInBytes).contains(memoryInBytes) else {
            throw VirtLiteError.memoryOutOfRange(
                requested: memoryInBytes,
                minimum: limits.minimumMemoryInBytes,
                maximum: limits.maximumMemoryInBytes
            )
        }

        guard !disks.isEmpty else {
            throw VirtLiteError.noDisks
        }

        let tags = sharedFolders.map(\.tag)
        if Set(tags).count != tags.count {
            throw VirtLiteError.duplicateSharedFolderTag
        }

        // A shared folder whose tag collides with another mount silently races in the guest,
        // so this is caught here rather than at mount time (SHR-03).
        for folder in sharedFolders where folder.tag.isEmpty {
            throw VirtLiteError.emptySharedFolderTag
        }
    }
}
