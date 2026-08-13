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
    var seed: URL?
    var exercise = false
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
    if let index = arguments.firstIndex(of: "--exercise") {
        options.exercise = true
        arguments.remove(at: index)
    }
    if let seed = value(after: "--seed") {
        options.seed = URL(fileURLWithPath: seed)
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
        seedISO: options.seed,
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

// The tool drives VZMachine rather than VZVirtualMachine directly, so a run here exercises the
// same code path the app uses. A backend bug reproduces in both or neither.
let machine = VZMachine(configuration: vzConfiguration, name: configuration.name)

Task {
    // Watching the stream rather than polling: this is how the interface will follow a machine
    // too, so a missing transition shows up here first (LC-04).
    for await state in machine.stateUpdates {
        print("[virtlite-boot] state: \(state.rawValue)")
        if state == .stopped {
            exit(0)
        }
        if state == .error {
            exit(1)
        }
    }
}

Task {
    do {
        try await machine.start()

        if options.exercise {
            print("[virtlite-boot] exercising the lifecycle")
            print("[virtlite-boot] saved state supported: \(machine.supportsSavedState)")

            try await Task.sleep(for: .seconds(20))
            try await machine.pause()
            try await Task.sleep(for: .seconds(3))
            try await machine.resume()
            try await Task.sleep(for: .seconds(5))
            try await machine.forceStop()
        }
    } catch {
        fail("\(error.localizedDescription)")
    }
}

RunLoop.main.run()
