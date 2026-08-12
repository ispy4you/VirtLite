import Foundation

/// A virtual machine on disk: a package directory holding configuration, disks and firmware state.
///
/// Layout (BND-01):
/// ```
/// Ubuntu 24.04.virtlite/
/// ├── config.json
/// ├── Disk.asif
/// ├── NVRAM
/// └── State.vzvmsave      (present only while a snapshot exists)
/// ```
public struct VMBundle: Sendable, Equatable {
    public static let fileExtension = "virtlite"

    public enum Entry {
        public static let configuration = "config.json"
        public static let primaryDisk = "Disk.asif"
        public static let nvram = "NVRAM"
        public static let savedState = "State.vzvmsave"
        /// macOS guests keep their auxiliary storage, machine identifier and hardware model here.
        public static let macOSSupport = "macOS"
    }

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var configurationURL: URL { url.appending(path: Entry.configuration) }
    public var primaryDiskURL: URL { url.appending(path: Entry.primaryDisk) }
    public var nvramURL: URL { url.appending(path: Entry.nvram) }
    public var savedStateURL: URL { url.appending(path: Entry.savedState) }

    public var hasSavedState: Bool {
        FileManager.default.fileExists(atPath: savedStateURL.path(percentEncoded: false))
    }

    // MARK: - Reading and writing

    public func loadConfiguration() throws -> VMConfiguration {
        let data: Data
        do {
            data = try Data(contentsOf: configurationURL)
        } catch {
            throw VirtLiteError.bundleNotFound(url)
        }

        do {
            return try JSONDecoder().decode(VMConfiguration.self, from: data)
        } catch let error as DecodingError {
            // A configuration written by a newer VirtLite deserves its own message rather than a
            // decoding failure, so the version is checked before blaming the file (BND-02).
            if let version = try? Self.formatVersion(in: data),
               version > VMConfiguration.currentFormatVersion {
                throw VirtLiteError.bundleFormatTooNew(
                    found: version,
                    supported: VMConfiguration.currentFormatVersion
                )
            }
            throw VirtLiteError.bundleCorrupted(reason: String(describing: error))
        }
    }

    public func save(_ configuration: VMConfiguration) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)

        // Written atomically: a configuration truncated by a crash would take the whole VM with it.
        try data.write(to: configurationURL, options: .atomic)
    }

    private static func formatVersion(in data: Data) throws -> Int? {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["formatVersion"] as? Int
    }

    // MARK: - Creating

    /// Creates the bundle directory and writes its configuration.
    ///
    /// Disk images are not created here — that belongs to the backend, which knows how to make an
    /// ASIF image. This only lays out the package.
    @discardableResult
    public static func create(
        at url: URL,
        configuration: VMConfiguration,
        fileManager: FileManager = .default
    ) throws -> VMBundle {
        guard !fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw VirtLiteError.bundleAlreadyExists(url)
        }

        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)

        let bundle = VMBundle(url: url)
        try bundle.save(configuration)
        return bundle
    }
}
