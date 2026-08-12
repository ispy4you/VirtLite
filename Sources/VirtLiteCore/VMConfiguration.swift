import Foundation

/// The kind of operating system a virtual machine hosts.
public enum GuestType: String, Codable, Sendable, CaseIterable {
    case linux
    case macOS
}

/// One virtual disk inside a VM bundle.
///
/// Paths are stored as file names relative to the bundle, never as absolute paths — a bundle
/// must stay valid after being exported to another Mac (BND-03).
public struct DiskConfiguration: Codable, Sendable, Equatable {
    public var fileName: String
    public var sizeInBytes: UInt64
    public var isReadOnly: Bool

    public init(fileName: String, sizeInBytes: UInt64, isReadOnly: Bool = false) {
        self.fileName = fileName
        self.sizeInBytes = sizeInBytes
        self.isReadOnly = isReadOnly
    }
}

/// A single host-to-guest port forwarding rule (NET-02).
public struct PortForward: Codable, Sendable, Equatable {
    public enum NetworkProtocol: String, Codable, Sendable {
        case tcp
        case udp
    }

    public var networkProtocol: NetworkProtocol
    public var hostPort: UInt16
    public var guestPort: UInt16

    public init(networkProtocol: NetworkProtocol = .tcp, hostPort: UInt16, guestPort: UInt16) {
        self.networkProtocol = networkProtocol
        self.hostPort = hostPort
        self.guestPort = guestPort
    }
}

public struct NetworkConfiguration: Codable, Sendable, Equatable {
    public enum Mode: String, Codable, Sendable {
        /// Shared networking with internet access through the host (NET-01).
        case nat
        /// A network visible only to other virtual machines (NET-03).
        case isolated
    }

    public var mode: Mode
    public var portForwards: [PortForward]

    public init(mode: Mode = .nat, portForwards: [PortForward] = []) {
        self.mode = mode
        self.portForwards = portForwards
    }
}

/// A folder shared with the guest, identified only by its virtiofs tag.
///
/// The host path deliberately lives outside the bundle: it is a security-scoped bookmark tied to
/// one machine and one user, and storing it here would break export in a way that is hard to
/// diagnose (BND-03). On import the user re-binds each tag to a real folder (BND-05).
public struct SharedFolder: Codable, Sendable, Equatable {
    public var tag: String
    public var isReadOnly: Bool

    public init(tag: String, isReadOnly: Bool = false) {
        self.tag = tag
        self.isReadOnly = isReadOnly
    }
}

/// The persisted configuration of a virtual machine — the contents of `config.json` (BND-01).
public struct VMConfiguration: Codable, Sendable, Equatable {
    /// Bumped whenever the on-disk format changes in a way older versions cannot read (BND-02).
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var name: String
    public var guest: GuestType
    public var cpuCount: Int
    public var memoryInBytes: UInt64
    public var disks: [DiskConfiguration]
    public var network: NetworkConfiguration
    public var sharedFolders: [SharedFolder]
    public var isRosettaEnabled: Bool

    public init(
        formatVersion: Int = VMConfiguration.currentFormatVersion,
        name: String,
        guest: GuestType,
        cpuCount: Int,
        memoryInBytes: UInt64,
        disks: [DiskConfiguration],
        network: NetworkConfiguration = NetworkConfiguration(),
        sharedFolders: [SharedFolder] = [],
        isRosettaEnabled: Bool = false
    ) {
        self.formatVersion = formatVersion
        self.name = name
        self.guest = guest
        self.cpuCount = cpuCount
        self.memoryInBytes = memoryInBytes
        self.disks = disks
        self.network = network
        self.sharedFolders = sharedFolders
        self.isRosettaEnabled = isRosettaEnabled
    }
}
