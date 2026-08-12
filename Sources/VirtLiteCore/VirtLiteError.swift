import Foundation

/// Errors the engine reports to the interface.
///
/// Every case carries the numbers needed to explain itself. Requirement NFR-06 asks for messages
/// that say what went wrong and what the acceptable value is, which is impossible if the error
/// only carries a description.
public enum VirtLiteError: Error, Equatable, Sendable {
    case emptyName
    case noDisks
    case duplicateSharedFolderTag
    case emptySharedFolderTag

    case cpuCountOutOfRange(requested: Int, minimum: Int, maximum: Int)
    case memoryOutOfRange(requested: UInt64, minimum: UInt64, maximum: UInt64)

    case bundleFormatTooNew(found: Int, supported: Int)
    case bundleNotFound(URL)
    case bundleAlreadyExists(URL)
    case bundleCorrupted(reason: String)

    case insufficientDiskSpace(requiredBytes: UInt64, availableBytes: UInt64)
    case unsupportedImageArchitecture
}

extension VirtLiteError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "The virtual machine needs a name."

        case .noDisks:
            return "The virtual machine has no disks attached."

        case .duplicateSharedFolderTag:
            return "Two shared folders use the same tag. Tags must be unique, or the guest cannot tell the mounts apart."

        case .emptySharedFolderTag:
            return "A shared folder has an empty tag."

        case let .cpuCountOutOfRange(requested, minimum, maximum):
            return "\(requested) CPU cores is outside the supported range of \(minimum) to \(maximum) on this Mac."

        case let .memoryOutOfRange(requested, minimum, maximum):
            let format = { (bytes: UInt64) in
                ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
            }
            return "\(format(requested)) of memory is outside the supported range of \(format(minimum)) to \(format(maximum)) on this Mac."

        case let .bundleFormatTooNew(found, supported):
            return "This virtual machine was created by a newer version of VirtLite (format \(found), this version reads up to \(supported)). Update VirtLite to open it."

        case let .bundleNotFound(url):
            return "No virtual machine found at \(url.path)."

        case let .bundleAlreadyExists(url):
            return "A virtual machine already exists at \(url.path)."

        case let .bundleCorrupted(reason):
            return "The virtual machine bundle is damaged: \(reason)"

        case let .insufficientDiskSpace(required, available):
            let format = { (bytes: UInt64) in
                ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            }
            return "Not enough disk space: \(format(required)) needed, \(format(available)) available."

        case .unsupportedImageArchitecture:
            return "This image is built for x86_64 and cannot run on Apple Silicon. Rosetta translates individual x86_64 binaries inside an ARM guest, but it cannot run an x86_64 operating system."
        }
    }
}
