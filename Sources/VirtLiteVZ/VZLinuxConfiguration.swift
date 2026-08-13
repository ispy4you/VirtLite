import Foundation
import Virtualization
import VirtLiteCore

/// Builds a `VZVirtualMachineConfiguration` for a Linux guest.
///
/// Everything the framework needs that the stored configuration does not describe — boot media,
/// firmware storage, console attachment — is passed in here rather than persisted, because it
/// changes between runs while the bundle does not.
public enum VZLinuxConfiguration {

    public struct BootMedia: Sendable {
        /// Installer image to boot from. Detached once the guest is installed (INS-01).
        public var installerISO: URL?
        /// The machine's own disk.
        public var disk: URL
        /// EFI variable storage, created on first boot and kept in the bundle.
        public var nvram: URL

        public init(installerISO: URL? = nil, disk: URL, nvram: URL) {
            self.installerISO = installerISO
            self.disk = disk
            self.nvram = nvram
        }
    }

    /// Where guest console output goes. Headless runs send it to the terminal; the app will
    /// attach it to a console window instead (DIA-01).
    public enum Console: Sendable {
        case none
        case standardIO
    }

    public static func make(
        from configuration: VMConfiguration,
        media: BootMedia,
        console: Console = .none,
        graphics: Bool = true
    ) throws -> VZVirtualMachineConfiguration {
        try configuration.validate(against: VZHardwareLimits.current)

        let vzConfiguration = VZVirtualMachineConfiguration()
        vzConfiguration.cpuCount = configuration.cpuCount
        vzConfiguration.memorySize = configuration.memoryInBytes

        vzConfiguration.bootLoader = try makeBootLoader(nvram: media.nvram)
        vzConfiguration.platform = VZGenericPlatformConfiguration()
        vzConfiguration.storageDevices = try makeStorageDevices(media: media)
        vzConfiguration.networkDevices = [makeNetworkDevice(configuration.network)]
        vzConfiguration.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        vzConfiguration.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]

        // A Linux guest ignores the mouse entirely without these, which reads as a frozen app
        // rather than a missing device (HW-05).
        if graphics {
            vzConfiguration.graphicsDevices = [makeGraphicsDevice()]
            vzConfiguration.keyboards = [VZUSBKeyboardConfiguration()]
            vzConfiguration.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]
        }

        if case .standardIO = console {
            vzConfiguration.serialPorts = [makeStandardIOSerialPort()]
        }

        try vzConfiguration.validate()
        return vzConfiguration
    }

    // MARK: - Devices

    private static func makeBootLoader(nvram: URL) throws -> VZEFIBootLoader {
        let bootLoader = VZEFIBootLoader()

        // The variable store holds the boot entries the guest writes during installation. Losing
        // it means the installed system becomes unbootable, so it lives in the bundle.
        if FileManager.default.fileExists(atPath: nvram.path(percentEncoded: false)) {
            bootLoader.variableStore = VZEFIVariableStore(url: nvram)
        } else {
            bootLoader.variableStore = try VZEFIVariableStore(creatingVariableStoreAt: nvram)
        }

        return bootLoader
    }

    private static func makeStorageDevices(
        media: BootMedia
    ) throws -> [VZStorageDeviceConfiguration] {
        var devices: [VZStorageDeviceConfiguration] = []

        // The installer is attached as USB mass storage, which is what EFI firmware expects to
        // find bootable removable media on.
        if let iso = media.installerISO {
            let attachment = try VZDiskImageStorageDeviceAttachment(url: iso, readOnly: true)
            devices.append(VZUSBMassStorageDeviceConfiguration(attachment: attachment))
        }

        let diskAttachment = try VZDiskImageStorageDeviceAttachment(
            url: media.disk,
            readOnly: false,
            cachingMode: .automatic,
            // Guest writes reach the image before the write is acknowledged. This is what keeps a
            // crash of the host app from corrupting the disk (NFR-04).
            synchronizationMode: .full
        )
        devices.append(VZVirtioBlockDeviceConfiguration(attachment: diskAttachment))

        return devices
    }

    private static func makeNetworkDevice(
        _ network: NetworkConfiguration
    ) -> VZVirtioNetworkDeviceConfiguration {
        let device = VZVirtioNetworkDeviceConfiguration()

        switch network.mode {
        case .nat, .isolated:
            // NAT is all the MVP needs (NET-01). Custom vmnet topologies, which is where
            // isolated networks and port forwarding live, wait on the entitlement question.
            device.attachment = VZNATNetworkDeviceAttachment()
        }

        return device
    }

    private static func makeGraphicsDevice() -> VZVirtioGraphicsDeviceConfiguration {
        let device = VZVirtioGraphicsDeviceConfiguration()
        device.scanouts = [
            VZVirtioGraphicsScanoutConfiguration(widthInPixels: 1280, heightInPixels: 800)
        ]
        return device
    }

    private static func makeStandardIOSerialPort() -> VZVirtioConsoleDeviceSerialPortConfiguration {
        let port = VZVirtioConsoleDeviceSerialPortConfiguration()
        port.attachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: FileHandle.standardInput,
            fileHandleForWriting: FileHandle.standardOutput
        )
        return port
    }
}
