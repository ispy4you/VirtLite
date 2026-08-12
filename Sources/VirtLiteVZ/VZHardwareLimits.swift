import Virtualization
import VirtLiteCore

/// Hardware ranges reported by `Virtualization.framework` on this Mac.
///
/// These values differ between machines, which is exactly why HW-01 forbids constants: a
/// configuration hardcoded against one Mac fails validation on another.
public enum VZHardwareLimits {
    public static var current: HardwareLimits {
        HardwareLimits(
            minimumMemoryInBytes: VZVirtualMachineConfiguration.minimumAllowedMemorySize,
            maximumMemoryInBytes: VZVirtualMachineConfiguration.maximumAllowedMemorySize,
            minimumCPUCount: VZVirtualMachineConfiguration.minimumAllowedCPUCount,
            maximumCPUCount: VZVirtualMachineConfiguration.maximumAllowedCPUCount
        )
    }
}
