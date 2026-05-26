# iOS and iPadOS Port Notes

This branch starts the mobile port as an experimental target. The app policy is intentionally narrow:

- iPhone/iOS requires at least 6 GB RAM and recommends 8 GB RAM.
- iOS/iPadOS 18.0 or newer is required.
- iPadOS requires an M1 iPad or newer.
- The first target test device is iPad Air M3 (`iPad15,3`-`iPad15,6`).
- Mobile rendering presets are limited to 1280x720 and 1600x900.
- JIT is expected to be provided by an external sideload/debug workflow, not by an App Store entitlement inside shadPS4.

## External JIT bridge

The bridge in `src/core/jit/external_jit_bridge.*` exposes two weak C hooks:

- `shadps4_external_jit_is_ready()`
- `shadps4_external_jit_prepare_process()`

An external launcher or injected support library can provide these symbols. Desktop and test builds may also set `SHADPS4_EXTERNAL_JIT_READY=1` to exercise the readiness path without a provider.

The bridge does not bypass iOS code-signing policy by itself. It only gives the emulator a single place to ask whether the outside JIT workflow is ready before CPU execution paths are wired to an ARM64 dynarec.

## Device and resolution policy

`src/core/platform/ios_device_policy.*` checks RAM, iPad class, and the supported resolution presets. Current iPad M-series detection is conservative and uses known `hw.machine` ranges so A-series iPads are not accepted accidentally.

## Configure sketch

An iOS SDK from full Xcode is required. Command Line Tools alone are not enough.

```sh
cmake -S . -B build/ios-device \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
  -DSHADPS4_IOS_PORT=ON \
  -DSHADPS4_ENABLE_EXTERNAL_JIT_BRIDGE=ON
```

Next porting steps:

1. Add an iOS app entry point instead of the current CLI `main.cpp`.
2. Wire the external JIT bridge into the future ARM64 CPU backend.
3. Switch SDL window creation on iOS to a UIKit-backed Metal surface.
4. Package MoltenVK for iOS and validate the Vulkan presenter on device.
