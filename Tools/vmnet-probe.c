// Spike for issue #20: can an ordinary Developer ID app create a vmnet network?
//
// VZVmnetNetworkDeviceAttachment.h states that vmnet "requires an entitlement to create or
// configure a network" without naming it. If that entitlement is com.apple.vm.networking —
// the restricted one that also gates bridged networking — then port forwarding (NET-02) and
// isolated networks (NET-03) are not available to this project.
//
// Build:  clang -framework vmnet -o vmnet-probe vmnet-probe.c
// Sign:   codesign --force --sign - --entitlements <plist> vmnet-probe

#include <stdio.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <vmnet/vmnet.h>

static const char *describe(vmnet_return_t status) {
    switch (status) {
        case VMNET_SUCCESS:                return "VMNET_SUCCESS";
        case VMNET_FAILURE:                return "VMNET_FAILURE";
        case VMNET_MEM_FAILURE:            return "VMNET_MEM_FAILURE";
        case VMNET_INVALID_ARGUMENT:       return "VMNET_INVALID_ARGUMENT";
        case VMNET_SETUP_INCOMPLETE:       return "VMNET_SETUP_INCOMPLETE";
        case VMNET_INVALID_ACCESS:         return "VMNET_INVALID_ACCESS (permission denied)";
        case VMNET_PACKET_TOO_BIG:         return "VMNET_PACKET_TOO_BIG";
        case VMNET_BUFFER_EXHAUSTED:       return "VMNET_BUFFER_EXHAUSTED";
        case VMNET_TOO_MANY_PACKETS:       return "VMNET_TOO_MANY_PACKETS";
        default:                           return "unknown";
    }
}

int main(void) {
    vmnet_return_t status = VMNET_SUCCESS;

    printf("uid: %d\n\n", (int)getuid());

    vmnet_network_configuration_ref configuration =
        vmnet_network_configuration_create(VMNET_SHARED_MODE, &status);
    printf("vmnet_network_configuration_create: %s\n", describe(status));
    if (configuration == NULL) {
        printf("  -> no configuration object, stopping\n");
        return 1;
    }

    // The rule this project actually wants: forward a host port into the guest (NET-02).
    // Signature is (protocol, family, internal_port, external_port, internal_address), so this
    // reads as "host 2222 reaches guest 22 at 192.168.64.10".
    struct in_addr guest;
    inet_pton(AF_INET, "192.168.64.10", &guest);
    status = vmnet_network_configuration_add_port_forwarding_rule(
        configuration, IPPROTO_TCP, AF_INET, 22, 2222, &guest);
    printf("add_port_forwarding_rule (host 2222 -> guest 22): %s\n", describe(status));

    vmnet_network_ref network = vmnet_network_create(configuration, &status);
    printf("vmnet_network_create: %s\n", describe(status));

    if (network == NULL) {
        printf("\n-> cannot create a vmnet network with this signature.\n");
        return 1;
    }

    printf("\n-> vmnet network created successfully.\n");
    return 0;
}
