import Foundation
import Testing
@testable import VirtLiteCore

private let testLimits = HardwareLimits(
    minimumMemoryInBytes: 128 * 1024 * 1024,
    maximumMemoryInBytes: 32 * 1024 * 1024 * 1024,
    minimumCPUCount: 1,
    maximumCPUCount: 12
)

private func makeConfiguration(
    cpuCount: Int = 4,
    memoryInBytes: UInt64 = 4 * 1024 * 1024 * 1024,
    sharedFolders: [SharedFolder] = []
) -> VMConfiguration {
    VMConfiguration(
        name: "Ubuntu 24.04",
        guest: .linux,
        cpuCount: cpuCount,
        memoryInBytes: memoryInBytes,
        disks: [DiskConfiguration(fileName: "Disk.asif", sizeInBytes: 64 * 1024 * 1024 * 1024)],
        sharedFolders: sharedFolders
    )
}

@Suite("Configuration encoding")
struct ConfigurationCodingTests {

    @Test("Survives a round trip unchanged")
    func roundTrip() throws {
        let original = makeConfiguration(
            sharedFolders: [SharedFolder(tag: "downloads", isReadOnly: true)]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VMConfiguration.self, from: data)

        #expect(decoded == original)
    }

    @Test("Writes the current format version")
    func formatVersionIsStamped() throws {
        let data = try JSONEncoder().encode(makeConfiguration())
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(object?["formatVersion"] as? Int == VMConfiguration.currentFormatVersion)
    }

    /// BND-03: absolute paths and bookmarks inside a bundle break export to another Mac.
    @Test("Holds no absolute paths")
    func noAbsolutePaths() throws {
        let configuration = makeConfiguration(
            sharedFolders: [SharedFolder(tag: "projects")]
        )
        let data = try JSONEncoder().encode(configuration)
        let json = String(decoding: data, as: UTF8.self)

        #expect(!json.contains("/Users/"))
        #expect(!json.contains("file://"))
    }
}

@Suite("Configuration validation")
struct ConfigurationValidationTests {

    @Test("Accepts a configuration within limits")
    func acceptsValid() throws {
        try makeConfiguration().validate(against: testLimits)
    }

    @Test("Rejects a CPU count above the maximum")
    func rejectsTooManyCores() {
        let configuration = makeConfiguration(cpuCount: 64)

        #expect(throws: VirtLiteError.cpuCountOutOfRange(requested: 64, minimum: 1, maximum: 12)) {
            try configuration.validate(against: testLimits)
        }
    }

    @Test("Rejects memory below the minimum")
    func rejectsTooLittleMemory() {
        let configuration = makeConfiguration(memoryInBytes: 1024)

        #expect(throws: VirtLiteError.self) {
            try configuration.validate(against: testLimits)
        }
    }

    @Test("Rejects an empty name")
    func rejectsEmptyName() {
        var configuration = makeConfiguration()
        configuration.name = "   "

        #expect(throws: VirtLiteError.emptyName) {
            try configuration.validate(against: testLimits)
        }
    }

    @Test("Rejects duplicate shared folder tags")
    func rejectsDuplicateTags() {
        let configuration = makeConfiguration(sharedFolders: [
            SharedFolder(tag: "shared"),
            SharedFolder(tag: "shared"),
        ])

        #expect(throws: VirtLiteError.duplicateSharedFolderTag) {
            try configuration.validate(against: testLimits)
        }
    }

    @Test("Rejects a bundle written by a newer VirtLite")
    func rejectsFutureFormat() {
        var configuration = makeConfiguration()
        configuration.formatVersion = VMConfiguration.currentFormatVersion + 1

        #expect(throws: VirtLiteError.bundleFormatTooNew(
            found: VMConfiguration.currentFormatVersion + 1,
            supported: VMConfiguration.currentFormatVersion
        )) {
            try configuration.validate(against: testLimits)
        }
    }

    @Test("Every error explains itself")
    func errorsAreDescribed() {
        let errors: [VirtLiteError] = [
            .emptyName,
            .noDisks,
            .cpuCountOutOfRange(requested: 64, minimum: 1, maximum: 12),
            .memoryOutOfRange(requested: 1024, minimum: 128, maximum: 4096),
            .unsupportedImageArchitecture,
        ]

        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }
}
