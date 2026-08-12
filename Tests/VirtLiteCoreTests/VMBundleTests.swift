import Foundation
import Testing
@testable import VirtLiteCore

@Suite("VM bundle on disk")
struct VMBundleTests {

    /// Each test gets its own directory under the system temporary folder, removed afterwards.
    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "VirtLiteTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try body(directory)
    }

    private func makeConfiguration() -> VMConfiguration {
        VMConfiguration(
            name: "Debian 12",
            guest: .linux,
            cpuCount: 2,
            memoryInBytes: 2 * 1024 * 1024 * 1024,
            disks: [DiskConfiguration(fileName: "Disk.asif", sizeInBytes: 32 * 1024 * 1024 * 1024)]
        )
    }

    @Test("Creating a bundle writes a readable configuration")
    func createAndLoad() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "Debian 12.virtlite")
            let configuration = makeConfiguration()

            let bundle = try VMBundle.create(at: url, configuration: configuration)
            let loaded = try bundle.loadConfiguration()

            #expect(loaded == configuration)
        }
    }

    @Test("Refuses to overwrite an existing bundle")
    func refusesToOverwrite() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "Debian 12.virtlite")
            try VMBundle.create(at: url, configuration: makeConfiguration())

            #expect(throws: VirtLiteError.bundleAlreadyExists(url)) {
                try VMBundle.create(at: url, configuration: makeConfiguration())
            }
        }
    }

    @Test("Reports a missing bundle rather than failing to decode")
    func missingBundle() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "Nothing.virtlite")
            let bundle = VMBundle(url: url)

            #expect(throws: VirtLiteError.bundleNotFound(url)) {
                _ = try bundle.loadConfiguration()
            }
        }
    }

    /// BND-02: a bundle from a newer VirtLite must say so, not report a corrupt file.
    @Test("Names the version when the format is too new")
    func rejectsNewerFormat() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "Future.virtlite")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

            let future = VMConfiguration.currentFormatVersion + 5
            let json = """
            { "formatVersion": \(future), "unknownField": true }
            """
            try Data(json.utf8).write(to: url.appending(path: VMBundle.Entry.configuration))

            #expect(throws: VirtLiteError.bundleFormatTooNew(
                found: future,
                supported: VMConfiguration.currentFormatVersion
            )) {
                _ = try VMBundle(url: url).loadConfiguration()
            }
        }
    }

    @Test("Reports damage for unreadable configuration")
    func reportsCorruption() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "Broken.virtlite")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("{ not json".utf8)
                .write(to: url.appending(path: VMBundle.Entry.configuration))

            #expect(throws: VirtLiteError.self) {
                _ = try VMBundle(url: url).loadConfiguration()
            }
        }
    }

    @Test("Knows whether a snapshot exists")
    func detectsSavedState() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "Snap.virtlite")
            let bundle = try VMBundle.create(at: url, configuration: makeConfiguration())

            #expect(bundle.hasSavedState == false)

            try Data("state".utf8).write(to: bundle.savedStateURL)
            #expect(bundle.hasSavedState == true)
        }
    }
}
