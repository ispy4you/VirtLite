import Foundation
import VirtLiteCore

/// Creates the disk images a virtual machine boots from.
///
/// ASIF is not a `Virtualization.framework` concept — the framework simply opens a file, and the
/// sparse format is the system's. There is no API for creating one on macOS 26, so this shells
/// out to `diskutil`. `DiskImageKit`, which would replace this, only arrives in macOS 27.
public enum VZDiskImage {

    public enum Format: String, Sendable {
        case asif = "ASIF"
        case raw = "RAW"
    }

    /// Creates an empty image with no filesystem inside it.
    ///
    /// `--fs none` matters: the default puts an APFS volume in the image, which is meaningless
    /// for a disk a Linux guest is about to partition itself.
    public static func create(
        at url: URL,
        sizeInBytes: UInt64,
        format: Format = .asif
    ) throws {
        guard !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return
        }

        try checkFreeSpace(for: sizeInBytes, near: url, format: format)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = [
            "image", "create", "blank",
            "--format", format.rawValue,
            "--size", String(sizeInBytes),
            "--fs", "none",
            url.path(percentEncoded: false),
        ]

        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe

        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw VirtLiteError.bundleCorrupted(
                reason: "could not create the disk image: \(message.isEmpty ? "diskutil failed" : message)"
            )
        }
    }

    /// A sparse image reports its full size but occupies far less, so free space is checked
    /// against what the image actually needs rather than what it claims (VM-07).
    private static func checkFreeSpace(
        for sizeInBytes: UInt64,
        near url: URL,
        format: Format
    ) throws {
        let directory = url.deletingLastPathComponent()
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        guard let available = values?.volumeAvailableCapacity.map({ UInt64($0) }) else { return }

        // A sparse image starts near empty; a raw one is written out in full.
        let required: UInt64 = format == .asif ? 64 * 1024 * 1024 : sizeInBytes
        guard available > required else {
            throw VirtLiteError.insufficientDiskSpace(
                requiredBytes: required,
                availableBytes: available
            )
        }
    }
}
