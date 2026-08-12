## What this changes

<!-- One or two sentences. Reference requirement IDs where they apply, e.g. (INS-01, HW-05). -->

## How it was verified

<!-- What you actually ran. For anything touching VirtLiteVZ, describe the manual test:
     which guest, which image, what you observed. "Works" is not a verification. -->

## Checklist

- [ ] `swift build` and `swift test` pass locally
- [ ] New behaviour in `VirtLiteCore` is covered by tests
- [ ] `VirtLiteCore` still does not import `Virtualization`
- [ ] VM bundle format unchanged, or `formatVersion` bumped and migration described
- [ ] User-facing strings are localizable, not hardcoded
