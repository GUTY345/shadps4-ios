# iOS and iPadOS Port Notes

This branch starts the mobile port as an experimental target. The app policy is intentionally narrow:

- iPhone/iOS requires at least 6 GB RAM and recommends 8 GB RAM.
- iOS/iPadOS 18.0 or newer is required.
- iPadOS requires an M1 iPad or newer.
- The first target test device is iPad Air M3 (`iPad15,3`-`iPad15,6`).
- Mobile rendering presets are limited to 1280x720 and 1600x900.
- JIT is expected to be provided by an external sideload/debug workflow such as SideStore, not by an App Store entitlement inside shadPS4.

## External JIT bridge

The bridge in `src/core/jit/external_jit_bridge.*` exposes two weak C hooks:

- `shadps4_external_jit_is_ready()`
- `shadps4_external_jit_prepare_process()`

An external launcher or injected support library can provide these symbols. Desktop and test builds may also set `SHADPS4_EXTERNAL_JIT_READY=1` to exercise the readiness path without a provider. On Apple platforms, the bridge also tries an executable-memory probe so a SideStore-enabled process can be detected even when no custom hook is injected.

The bridge does not bypass iOS code-signing policy by itself. It only gives the emulator a single place to ask whether the outside JIT workflow is ready before CPU execution paths are wired to an ARM64 dynarec.

## Device and resolution policy

`src/core/platform/ios_device_policy.*` checks RAM, iPad class, and the supported resolution presets. Current iPad M-series detection is conservative and uses known `hw.machine` ranges so A-series iPads are not accepted accidentally.

## macOS ARM reuse path

The iOS smoke app now reports an Apple Runtime status from
`src/core/platform/ios_emulator_core_bridge.*`. This is meant to keep the port
honest while reusing as much of the macOS Apple Silicon work as possible.

Reusable pieces from the macOS ARM path:

- Apple/arm64 CMake detection and build configuration.
- Shared C++ state surfaces such as `Core::EmulatorState`.
- Controller mapping ideas from the SDL/GameController side.
- The Metal presentation direction used by the Apple window path.
- A UIKit-owned `CAMetalLayer` smoke surface for iPadOS.
- The MoltenVK-on-Metal renderer strategy, once packaging and surface creation
  are made iOS-friendly.

Pieces that are not directly reusable yet:

- The desktop SDL window lifecycle.
- The macOS app bundle/runtime assumptions.
- The current MoltenVK dylib and ICD packaging path.
- The x86/xbyak CPU backend.

The current smoke app creates a real `CAMetalLayer`, attaches a Metal device,
and clears a diagnostic drawable. That proves the iPadOS app has a presenter
surface that can later be handed to MoltenVK or a future Metal renderer shim.

The smoke target now has CMake wiring and runtime checks for an iOS MoltenVK
runtime. It can consume a `MoltenVK.xcframework`, `MoltenVK.framework`,
`libMoltenVK.dylib`, or `libMoltenVK.a` via these cache variables:

```sh
-DSHADPS4_IOS_MOLTENVK_XCFRAMEWORK=/path/to/MoltenVK.xcframework
-DSHADPS4_IOS_MOLTENVK_FRAMEWORK=/path/to/MoltenVK.framework
-DSHADPS4_IOS_MOLTENVK_DYLIB=/path/to/libMoltenVK.dylib
-DSHADPS4_IOS_MOLTENVK_STATIC=/path/to/libMoltenVK.a
```

If a runtime is present, the smoke app defines
`SHADPS4_IOS_MOLTENVK_RUNTIME_LINKED` and the runtime panel reports whether the
binary is loadable. The remaining renderer work is to pass the UIKit
`CAMetalLayer` into the Vulkan presenter path used by
`video_core/renderer_vulkan/vk_platform.cpp`.

## ARM64 dynarec and SideStore JIT gate

`src/core/jit/external_jit_bridge.*` now exposes a separate ARM64 dynarec status
gate. The gate checks that the app is running as arm64 and that SideStore or
another external workflow has opened executable memory.

`src/core/jit/arm64_dynarec_backend.*` adds the first backend module for iOS. It
allocates an executable page, emits a tiny ARM64 validation stub, flushes the
instruction cache, and executes that stub after SideStore reports JIT readiness.
That proves the process can run generated ARM64 code on device.

This does not implement the full PS4 x86_64-to-ARM64 translator yet. It gives
the CPU backend a strict contract:

1. SideStore must enable JIT for the app process.
2. `QueryArm64DynarecStatus()` must report executable memory readiness.
3. `PrepareArm64Dynarec()` must successfully run the ARM64 validation stub.
4. A future translator must decode PS4 x86_64 basic blocks, lower them to ARM64,
   and mark `guest_translator_ready` before games can boot.

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

For the current on-device smoke test, generate the Xcode project with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer cmake -S . -B build/ios-smoke -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
  -DSHADPS4_IOS_PORT=ON \
  -DSHADPS4_IOS_BUILD_SMOKE_APP=ON \
  -DSHADPS4_ENABLE_EXTERNAL_JIT_BRIDGE=ON
```

The smoke app can be compiled without signing:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project build/ios-smoke/shadPS4.xcodeproj \
  -scheme shadps4-ios-smoke \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  clean build CODE_SIGNING_ALLOWED=NO
```

Installing on a physical device requires an Apple Development signing identity and a matching
provisioning profile for `dev.guty345.shadps4-ios-smoke`.

Next porting steps:

1. Add an actual iOS MoltenVK runtime binary or xcframework to the configured
   path if one is not already present locally.
2. Pass the UIKit `CAMetalLayer` into the Vulkan presenter and create a
   `VK_EXT_metal_surface` surface on device.
3. Build the x86_64 decoder, register model, memory callbacks, and ARM64 block
   emitter behind the SideStore JIT gate.
4. Start loading real dumped game content only after renderer, sysmodule, and
   CPU execution paths are connected.
