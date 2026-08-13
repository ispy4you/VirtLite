# VirtLite

A virtual machine manager for Apple Silicon built on Apple's `Virtualization.framework`. Linux
guests today; macOS guests later. **Windows guests are impossible on this stack** — the framework
runs Linux and macOS only, and that is settled, not pending.

Minimum macOS 26.0, Apple Silicon only. Not sandboxed, distributed outside the App Store.

## Building and running

```sh
swift build && swift test      # libraries and the core test suite
Scripts/build-app.sh           # assembles and signs VirtLite.app
Scripts/build-boot.sh          # signs virtlite-boot, the headless tool
open .build/arm64-apple-macosx/debug/VirtLite.app
```

**`swift run` cannot start a guest.** Not because of the bundle — entitlements come from the
*signature*, and `swift run` launches an unsigned binary. A bare signed executable works fine,
which is how `virtlite-boot` runs. Corollary that bites: **rebuilding replaces the binary and
drops its signature**, so re-run the script before running anything that touches a VM. The error
is `VZErrorDomain Code=2`.

There is no `.xcodeproj` and there should not be one — plain SwiftPM keeps the project usable
from any editor and avoids a file format that conflicts on every merge.

## Layers

| Target | May import | Holds |
|---|---|---|
| `VirtLiteCore` | Foundation only | Bundle format, configuration, validation, machine library |
| `VirtLiteVZ` | Virtualization | The backend: configuration building, disks, lifecycle |
| `VirtLite` | SwiftUI, AppKit | The app |
| `virtlite-boot` | — | Headless tool: boots a guest with no interface |

**`VirtLiteCore` must never import `Virtualization`** (`ARC-01`). `Scripts/check-core-boundary.sh`
enforces it in CI. This is not about portability — there is no Windows port planned. It is so the
engine is testable without a hypervisor, which is the only reason anything here has tests at all.

The UI does not name `VZ` types either. The one exception is the guest screen: the backend hands
over an `NSView` from `VZMachine.makeScreenView()`, and the app wraps it.

Machines run on the **main queue**. `VZVirtualMachineView` binds from the main thread and a
machine cannot live on two queues, so this is the framework's constraint.

## Requirement IDs

Every requirement in `Docs/SPEC.ru.md` has a stable ID — `VM-01`, `HW-05`, `NET-02`. Reference
them in issues, pull requests and commit messages. IDs are never reused; a dropped requirement
retires its ID with it.

`Docs/api-verification.md` records what was checked against the SDK headers and takes precedence
over the specification where they disagree. `Docs/stage-0.md` is how to boot a guest locally.

## Things that cost time once already

**ASIF disks** are made with `diskutil image create blank --format ASIF --size N --fs none`. There
is no API for this on macOS 26 (`DiskImageKit` arrives in 27). `--fs none` is not optional — the
default puts an APFS volume inside a disk the Linux guest is about to partition itself.

**The Ubuntu installer asks for confirmation** before wiping a disk, and skipping it needs
`autoinstall` on the kernel command line, which EFI booting an unmodified ISO cannot set. Answer
it over the console — and answer it *when it appears*, since anything sent earlier is discarded.
A cloud-init seed volume must be named `CIDATA` or NoCloud will not find it. See `Docs/stage-0.md`.

**The installer image is detached explicitly, never automatically.** Nothing on the host can tell
a finished installation from an abandoned one, and guessing wrong leaves a machine that cannot
boot and cannot explain why. It is remembered as a bookmark in app storage — never in the bundle,
which holds no absolute paths so it survives being copied to another Mac (`BND-03`).

**vmnet returns `VMNET_MEM_FAILURE` when it means "permission denied".** A memory error for a
signing problem. `com.apple.security.virtualization` is enough; the restricted
`com.apple.vm.networking` is only needed for bridged networking.

**Saving machine state** requires a paused machine, is gated on `validateSaveRestoreSupport` at
runtime, and produces a file encrypted against this host — it cannot move to another Mac, and a
system update can invalidate it, so restore has to fall back to a cold boot rather than error.

**A guest that powers off within a second did not fail to run — it found nothing to boot.** Empty
disk with no installer attached, or an x86_64 image. Say so; do not leave the user staring at
"Stopped".

## Testing, and what is not tested

`swift test` covers `VirtLiteCore` only, and runs in CI on `macos-26`.

Nothing automatic verifies **a guest actually booting** (hosted runners have no virtualization
entitlement) or **any of the interface**. Both bugs that reached the user came from the untested
half: the guest screen never took keyboard focus, and a machine that could not boot said nothing.
When claiming something in the app works, say whether a human looked.

`virtlite-boot --exercise` is the fastest way to check the backend end to end without the UI in
the way.
