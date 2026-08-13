# VirtLite

A lightweight virtual machine manager for Apple Silicon Macs, built on Apple's native
`Virtualization.framework`.

VirtLite runs Linux guests at native speed — no emulation layer, no heavyweight desktop
suite. Pick an image, set CPU and memory, start the machine. That's the whole flow.

> **Status: early development.** Nothing here is usable yet. The specification is written
> and the project skeleton is in place; the first milestone is a Linux VM booting from an
> `.iso`. See [Roadmap](#roadmap).

**Русская версия README:** [README.ru.md](README.ru.md)

## Requirements

| | |
|---|---|
| Host | Apple Silicon Mac (arm64) |
| macOS | 26.0 or later |
| Xcode | 26.0 or later (to build from source) |

macOS 26 is a deliberate floor. It is where the Apple Sparse Image Format (ASIF) and
`VZVmnetNetworkDeviceAttachment` arrived — compact disk images and port forwarding are
central to what VirtLite is for, and supporting older releases would mean maintaining two
parallel code paths through the disk and network layers indefinitely.

## What it does

- Create and run Linux VMs from a local `.iso` or a verified distribution template
- Configure CPU cores, memory and disks, with limits read from the framework itself
- Internet access over NAT, plus TCP/UDP port forwarding into the guest
- Share host folders with the guest, and the clipboard where the guest supports it
- Run x86_64 Linux binaries inside an ARM guest through Rosetta
- Save and restore machine state
- Export, import and clone VM bundles

## What it does not do

These are permanent constraints of the platform, not gaps waiting to be filled:

- **Windows guests.** `Virtualization.framework` runs Linux and macOS guests only. Tools that
  run Windows on Apple Silicon (UTM, Parallels) use QEMU or their own hypervisor on top of the
  lower-level `Hypervisor.framework`. Supporting Windows would mean a different product.
- **x86_64 guest systems.** Rosetta translates individual x86_64 binaries inside an ARM guest;
  it does not run an x86_64 operating system.
- **Intel Macs as hosts.**
- **Bridged networking.** The API exists but requires the `com.apple.vm.networking` entitlement,
  which Apple grants on individual request. Port forwarding covers most of what people need it for.
- **3D acceleration for Linux guests.** The framework gives Linux a display without hardware 3D.
  Heavy desktop environments will feel slow; lightweight ones are fine.

## Roadmap

| Stage | Scope |
|---|---|
| 0 | Research, entitlements, headless proof of concept |
| 1 | **MVP** — create, run and stop a Linux VM from `.iso`; CPU/RAM/disk; NAT; VM list and screen |
| 2 | Snapshots, shared folders, clipboard, Rosetta, port forwarding, serial console |
| 3 | Distribution templates, extra disks, audio, macOS guests |
| 4 | Export, import, clone; ru/en localization; accessibility |
| 5 | Performance and energy testing, signing, notarization, release |

The full specification lives in [Docs/SPEC.ru.md](Docs/SPEC.ru.md). Requirements carry stable
IDs (`VM-01`, `HW-05`, `NET-02`) — issues and pull requests reference them.

## Building

```sh
git clone https://github.com/ispy4you/VirtLite.git
cd VirtLite
swift build
swift test
```

To run the app, build the signed bundle with `Scripts/build-app.sh`. `swift run` will not do:
starting a guest needs an entitlement, and entitlements come from a code signature.
See [CONTRIBUTING.md](CONTRIBUTING.md) for the layer boundaries and what belongs where.

## Architecture

Three layers, split along the VM lifecycle:

- **`VirtLiteCore`** — bundle format, configuration, validation, import/export. Imports only
  Foundation. Never imports `Virtualization`; CI enforces this.
- **`VirtLiteVZ`** — the `Virtualization.framework` backend implementing the lifecycle protocol.
- **`VirtLite`** — the SwiftUI application.

The split exists so the engine can be tested in CI without launching a VM, and so a CLI stays
cheap to add later. It is not there for cross-platform portability: there are no plans for a
Windows port.

## License

[Apache License 2.0](LICENSE).

## Trademarks

macOS, Apple Silicon, Rosetta and Xcode are trademarks of Apple Inc. Ubuntu, Debian, Fedora and
openSUSE are trademarks of their respective owners. VirtLite is an independent project and is not
affiliated with, endorsed by, or sponsored by any of them.
