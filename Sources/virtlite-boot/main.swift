import Foundation
import Virtualization
import VirtLiteCore
import VirtLiteVZ

// Headless proof of concept (issue #3). Boots a Linux guest from an .iso with no interface and
// streams its console to the terminal, which is the point where the whole approach either works
// or does not.
//
// This is not the app. It exists so the backend can be exercised without any UI in the way, and
// so a failure to boot is unambiguous about where it came from.

// MARK: - Arguments

struct Options {
    var iso: URL?
    var bundle: URL
    var cpuCount = 2
    var memoryInBytes: UInt64 = 4 * 1024 * 1024 * 1024
    var diskSizeInBytes: UInt64 = 32 * 1024 * 1024 * 1024
}

func parseArguments() -> Options {
    var arguments = Array(CommandLine.arguments.dropFirst())
    var options = Options(bundle: URL(fileURLWithPath: "PoC.virtlite"))

    func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            return nil
        }
        let value = arguments[index + 1]
        arguments.removeSubrange(index...(index + 1))
        return value
    }

    if let iso = value(after: "--iso") {
        options.iso = URL(fileURLWithPath: iso)
    }
    if let bundle = value(after: "--bundle") {
        options.bundle = URL(fileURLWithPath: bundle)
    }
    if let cpus = value(after: "--cpus"), let count = Int(cpus) {
        options.cpuCount = count
    }
    if let memory = value(after: "--memory-gb"), let gigabytes = UInt64(memory) {
        options.memoryInBytes = gigabytes * 1024 * 1024 * 1024
    }
    if let disk = value(after: "--disk-gb"), let gigabytes = UInt64(disk) {
        options.diskSizeInBytes = gigabytes * 1024 * 1024 * 1024
    }

    return options
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("virtlite-boot: \(message)\n".utf8))
    exit(1)
}

// MARK: - Delegate

/// Keeps the process alive while the guest runs and reports why it stopped.
final class BootObserver: NSObject, VZVirtualMachineDelegate, @unchecked Sendable {
    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        print("\n[virtlite-boot] guest powered off")
        exit(0)
    }

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        print("\n[virtlite-boot] guest stopped with an error: \(error.localizedDescription)")
        exit(1)
    }

    func virtualMachine(
        _ virtualMachine: VZVirtualMachine,
        networkDevice: VZNetworkDevice,
        attachmentWasDisconnectedWithError error: Error
    ) {
        print("[virtlite-boot] network detached: \(error.localizedDescription)")
    }
}

// MARK: - Run

let options = parseArguments()

let bundle = VMBundle(url: options.bundle)
let configuration: VMConfiguration

if FileManager.default.fileExists(atPath: bundle.configurationURL.path(percentEncoded: false)) {
    configuration = try bundle.loadConfiguration()
    print("[virtlite-boot] reusing \(options.bundle.lastPathComponent)")
} else {
    configuration = VMConfiguration(
        name: options.bundle.deletingPathExtension().lastPathComponent,
        guest: .linux,
        cpuCount: options.cpuCount,
        memoryInBytes: options.memoryInBytes,
        disks: [
            DiskConfiguration(
                fileName: VMBundle.Entry.primaryDisk,
                sizeInBytes: options.diskSizeInBytes
            )
        ]
    )
    try VMBundle.create(at: options.bundle, configuration: configuration)
    print("[virtlite-boot] created \(options.bundle.lastPathComponent)")
}

guard let disk = configuration.disks.first else {
    fail("the configuration has no disks")
}

try VZDiskImage.create(
    at: bundle.primaryDiskURL,
    sizeInBytes: disk.sizeInBytes
)

let isoExists = options.iso.map {
    FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
} ?? false

if let iso = options.iso, !isoExists {
    fail("no image at \(iso.path(percentEncoded: false))")
}

let vzConfiguration = try VZLinuxConfiguration.make(
    from: configuration,
    media: VZLinuxConfiguration.BootMedia(
        installerISO: options.iso,
        disk: bundle.primaryDiskURL,
        nvram: bundle.nvramURL
    ),
    console: .standardIO,
    // Headless: no display, no input devices. The console is the only way in, which is exactly
    // what this proof of concept is meant to exercise.
    graphics: false
)

print("""
[virtlite-boot] \(configuration.cpuCount) cores, \
\(ByteCountFormatter.string(fromByteCount: Int64(configuration.memoryInBytes), countStyle: .memory)), \
\(options.iso == nil ? "booting from disk" : "booting from image")
[virtlite-boot] guest console follows — ^C to stop

""")

let observer = BootObserver()
let virtualMachine = VZVirtualMachine(configuration: vzConfiguration)
virtualMachine.delegate = observer

virtualMachine.start { result in
    if case let .failure(error) = result {
        fail("could not start: \(error.localizedDescription)")
    }
}

RunLoop.main.run()
