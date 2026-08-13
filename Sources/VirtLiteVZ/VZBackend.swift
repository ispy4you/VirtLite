import Foundation
import Virtualization
import VirtLiteCore

/// Turns bundles into running machines.
///
/// This is the only type the interface needs to know about to start a guest — everything
/// framework-shaped stays behind it (ARC-02).
public struct VZBackend: VMBackendProviding {

    public init() {}

    public var hardwareLimits: HardwareLimits { VZHardwareLimits.current }

    public func makeMachine(
        for bundle: VMBundle,
        configuration: VMConfiguration
    ) throws -> any VMLifecycle {
        let media = VZLinuxConfiguration.BootMedia(
            installerISO: nil,
            disk: bundle.primaryDiskURL,
            nvram: bundle.nvramURL
        )

        let vzConfiguration = try VZLinuxConfiguration.make(
            from: configuration,
            media: media,
            console: .none,
            graphics: true
        )

        return VZMachine(configuration: vzConfiguration, name: configuration.name)
    }

    /// Boots from an installer image. Separate from `makeMachine` on purpose: attaching an
    /// installer is a one-time state of a machine, not a property of it, and forgetting to
    /// detach it means the guest reinstalls itself forever (INS-01).
    public func makeMachineForInstallation(
        for bundle: VMBundle,
        configuration: VMConfiguration,
        installerISO: URL
    ) throws -> any VMLifecycle {
        let media = VZLinuxConfiguration.BootMedia(
            installerISO: installerISO,
            disk: bundle.primaryDiskURL,
            nvram: bundle.nvramURL
        )

        let vzConfiguration = try VZLinuxConfiguration.make(
            from: configuration,
            media: media,
            console: .none,
            graphics: true
        )

        return VZMachine(configuration: vzConfiguration, name: configuration.name)
    }
}
