import Foundation
import Testing
@testable import VirtLiteCore

@Suite("Machine library")
struct MachineLibraryTests {

    private func withLibrary(_ body: (MachineLibrary) throws -> Void) throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "VirtLiteLibrary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try body(MachineLibrary(directory: directory))
    }

    private func configuration(named name: String) -> VMConfiguration {
        VMConfiguration(
            name: name,
            guest: .linux,
            cpuCount: 2,
            memoryInBytes: 2 * 1024 * 1024 * 1024,
            disks: [DiskConfiguration(fileName: "Disk.asif", sizeInBytes: 16 * 1024 * 1024 * 1024)]
        )
    }

    @Test("An empty library lists nothing rather than failing")
    func emptyLibrary() throws {
        try withLibrary { library in
            try #expect(library.machines().isEmpty)
        }
    }

    @Test("A library directory that does not exist yet is not an error")
    func missingDirectory() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "VirtLiteMissing-\(UUID().uuidString)")
        let library = MachineLibrary(directory: directory)

        try #expect(library.machines().isEmpty)
    }

    @Test("Created machines appear in the listing")
    func createAndList() throws {
        try withLibrary { library in
            _ = try library.create(configuration(named: "Ubuntu"))
            _ = try library.create(configuration(named: "Debian"))

            let machines = try library.machines()
            #expect(machines.count == 2)
            // Sorted by name, so the list does not reshuffle itself between launches.
            #expect(machines.map(\.name) == ["Debian", "Ubuntu"])
        }
    }

    @Test("Two machines may share a name but not a path")
    func duplicateNames() throws {
        try withLibrary { library in
            let first = try library.create(configuration(named: "Ubuntu"))
            let second = try library.create(configuration(named: "Ubuntu"))

            #expect(first.bundle.url != second.bundle.url)
            #expect(second.bundle.url.lastPathComponent == "Ubuntu 2.virtlite")
            try #expect(library.machines().count == 2)
        }
    }

    @Test("Names that would break a path are cleaned up")
    func sanitizesNames() throws {
        try withLibrary { library in
            #expect(library.sanitized("Ubuntu/24.04") == "Ubuntu-24.04")
            #expect(library.sanitized("  ") == "Virtual Machine")
            #expect(library.sanitized("Fedora") == "Fedora")
        }
    }

    /// One damaged bundle must not hide the healthy ones.
    @Test("A damaged bundle is skipped, not fatal")
    func damagedBundleIsSkipped() throws {
        try withLibrary { library in
            _ = try library.create(configuration(named: "Healthy"))

            let broken = library.directory.appending(path: "Broken.virtlite")
            try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
            try Data("not json".utf8)
                .write(to: broken.appending(path: VMBundle.Entry.configuration))

            try #expect(library.machines().map(\.name) == ["Healthy"])
            try #expect(library.unreadableBundles().count == 1)
        }
    }

    @Test("Directories that are not bundles are ignored")
    func ignoresOtherDirectories() throws {
        try withLibrary { library in
            _ = try library.create(configuration(named: "Ubuntu"))
            try FileManager.default.createDirectory(
                at: library.directory.appending(path: "notes"),
                withIntermediateDirectories: true
            )

            try #expect(library.machines().count == 1)
        }
    }

    @Test("Renaming keeps the bundle where it is")
    func renameKeepsPath() throws {
        try withLibrary { library in
            let machine = try library.create(configuration(named: "Ubuntu"))
            let renamed = try library.rename(machine, to: "Ubuntu 24.04")

            #expect(renamed.name == "Ubuntu 24.04")
            #expect(renamed.bundle.url == machine.bundle.url)

            // And it survives a reload, rather than living only in memory.
            try #expect(library.machines().map(\.name) == ["Ubuntu 24.04"])
        }
    }

    @Test("Renaming to nothing is refused")
    func renameToEmpty() throws {
        try withLibrary { library in
            let machine = try library.create(configuration(named: "Ubuntu"))

            #expect(throws: VirtLiteError.emptyName) {
                _ = try library.rename(machine, to: "   ")
            }
        }
    }

    @Test("Deleting removes the bundle from disk")
    func deleteRemovesBundle() throws {
        try withLibrary { library in
            let machine = try library.create(configuration(named: "Ubuntu"))
            try library.delete(machine)

            try #expect(library.machines().isEmpty)
            #expect(!FileManager.default.fileExists(
                atPath: machine.bundle.url.path(percentEncoded: false)
            ))
        }
    }

    @Test("Size on disk reflects what is actually occupied")
    func sizeOnDisk() throws {
        try withLibrary { library in
            let machine = try library.create(configuration(named: "Ubuntu"))
            try Data(repeating: 0xAB, count: 128 * 1024).write(to: machine.bundle.primaryDiskURL)

            // Allocated size, not the size a sparse image claims — the confirmation dialog
            // should not promise space that deleting will not return.
            #expect(library.sizeOnDisk(of: machine) >= 128 * 1024)
        }
    }
}
