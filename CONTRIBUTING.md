# Contributing to VirtLite

Thanks for looking. VirtLite is in early development — the specification is settled, the code is
mostly not written yet, so this is a good moment to get involved.

Issues and pull requests in English or Russian are both fine.

## Getting set up

Requirements: an Apple Silicon Mac on macOS 26 or later, and Xcode 26 or later.

```sh
git clone https://github.com/ispy4you/VirtLite.git
cd VirtLite
swift build
swift test
```

To run the app, build the bundle instead of using `swift run`:

```sh
Scripts/build-app.sh          # debug
open .build/arm64-apple-macosx/debug/VirtLite.app
```

`swift run` will not do. Starting a guest requires the `com.apple.security.virtualization`
entitlement, and entitlements come from a code signature — `swift run` launches the binary it
just built, unsigned. The script assembles `VirtLite.app`, applies `Resources/Info.plist` and the
entitlements, and signs ad-hoc, which is enough locally. Debug builds also get `get-task-allow`,
without which no debugger can attach.

The bundle is what makes it an app, not what makes the entitlement work: a bare executable
signed with the same entitlement can start a guest perfectly well, which is how
`Scripts/build-boot.sh` builds the headless tool.

Release builds sign with a real identity:

```sh
VIRTLITE_SIGNING_IDENTITY="Developer ID Application: ..." Scripts/build-app.sh release
```

There is no `.xcodeproj`. The package builds with plain SwiftPM so the project stays usable from
any editor and avoids a file format that conflicts badly on merge. Xcode can still open the
package directory directly.

## How the code is organised

Three layers, and the boundary between them is the one rule worth knowing:

| Target | May import | Responsibility |
|---|---|---|
| `VirtLiteCore` | Foundation only | Bundle format, configuration, validation, import/export |
| `VirtLiteVZ` | Virtualization, VirtLiteCore | The framework backend: create, start, pause, stop, save, restore |
| `VirtLite` | SwiftUI, AppKit, both above | The application |

**`VirtLiteCore` must never import `Virtualization`.** CI fails the build if it does. This is not
about a future Windows port — there isn't one planned. It is so the engine can be tested without
launching a VM, and so a CLI stays cheap to add.

The UI does not touch `VZ*` types directly either. The single exception is
`VZVirtualMachineView`: it is an NSView that hands over a framebuffer and input, and hiding it
behind an abstraction would buy nothing.

Everything that talks to a running VM must do so on the machine's own queue
(`VZVirtualMachine.queue`). Getting this wrong produces crashes that only reproduce under load.

## Requirement IDs

The specification in [Docs/SPEC.ru.md](Docs/SPEC.ru.md) gives every requirement a stable ID —
`VM-01`, `HW-05`, `NET-02`. Reference them in issues, pull requests and commit messages:

```
Add ISO boot with EFI bootloader (INS-01)
```

IDs are never reused. If a requirement is dropped, its ID retires with it.

## Pull requests

- Branch from `main`, keep one topic per pull request.
- `swift build` and `swift test` must pass. CI runs both.
- New behaviour in `VirtLiteCore` needs tests. Behaviour in `VirtLiteVZ` often cannot be tested
  in CI, since it needs a real VM — say so in the description and explain how you verified it
  by hand.
- Describe what you actually tested. "Booted Ubuntu 24.04 from ISO, installed, rebooted from
  disk" is useful. "Works" is not.
- If a change alters the VM bundle format, bump `formatVersion` and say what happens to bundles
  written by older versions. Compatibility breaks are a real cost for anyone with existing VMs.

## Reporting bugs

Include the output of the diagnostic report (once that exists — `DIA-02`), or at minimum: macOS
version, Mac model, guest OS and image, and what you expected against what happened. A serial
console log is worth more than a screenshot when a guest fails to boot.

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).
