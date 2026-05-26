<!--
SPDX-FileCopyrightText: 2026 shadPS4 Emulator Project
SPDX-License-Identifier: GPL-2.0-or-later
-->

# shadPS4 iOS and iPadOS Port

This repository is an experimental iOS and iPadOS port branch of
[shadPS4](https://github.com/shadps4-emu/shadPS4), an early PlayStation 4
emulator written in C++.

The goal of this fork is to explore a mobile Apple Silicon path for shadPS4,
starting with iPadOS devices powerful enough to make testing realistic.

> [!IMPORTANT]
> This is not a finished iOS app yet. The current work is port scaffolding:
> device policy, resolution limits, external JIT readiness hooks, and build
> configuration for future iOS/iPadOS targets.

## Current Target

The first test device for this branch is:

- iPad Air M3
- `iPad15,3` to `iPad15,6`
- iOS/iPadOS 18.0 or newer

Runtime policy currently requires:

- iOS/iPadOS 18.0 or newer
- iPhone/iOS device with at least 6 GB RAM
- 8 GB RAM recommended
- iPadOS device must be M1 or newer
- iPad Air M3 is explicitly accepted for testing
- Rendering presets are limited to `1280x720` and `1600x900`

## JIT Strategy

iOS and iPadOS do not provide a normal desktop-style JIT environment for apps.
This fork therefore does not assume that the emulator itself owns a JIT
entitlement.

Instead, the branch expects JIT to be enabled from outside the app, for example
with SideStore's JIT workflow during testing. The branch adds an external JIT
bridge in:

- `src/core/jit/external_jit_bridge.h`
- `src/core/jit/external_jit_bridge.cpp`

An external sideload/debug workflow can provide these weak hooks:

```c
bool shadps4_external_jit_is_ready(void);
bool shadps4_external_jit_prepare_process(void);
```

Desktop tests can also set:

```sh
SHADPS4_EXTERNAL_JIT_READY=1
```

On Apple platforms the bridge also performs a lightweight executable-memory
probe. When SideStore has enabled JIT for the app process, the launcher's
External JIT card should change from `Not detected` to a ready provider state.

This only reports readiness. It does not bypass iOS code-signing rules by
itself.

## Build Notes

You need full Xcode with the iPhoneOS SDK installed. Apple Command Line Tools
alone are not enough.

Example configure command:

```sh
cmake -S . -B build/ios-device \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
  -DSHADPS4_IOS_PORT=ON \
  -DSHADPS4_ENABLE_EXTERNAL_JIT_BRIDGE=ON
```

Current on-device testing starts with the smoke-test app:

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

Unsigned compile check:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project build/ios-smoke/shadPS4.xcodeproj \
  -scheme shadps4-ios-smoke \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  clean build CODE_SIGNING_ALLOWED=NO
```

Physical-device install requires an Apple Development signing identity and a
provisioning profile for `dev.guty345.shadps4-ios-smoke`.

The normal desktop shadPS4 build path is inherited from upstream. See the
original build documentation:

- [Windows](https://github.com/shadps4-emu/shadPS4/blob/main/documents/building-windows.md)
- [Linux](https://github.com/shadps4-emu/shadPS4/blob/main/documents/building-linux.md)
- [macOS](https://github.com/shadps4-emu/shadPS4/blob/main/documents/building-macos.md)

## Port Status

Implemented in this branch:

- iOS/iPadOS CMake scaffolding
- iOS smoke-test app target
- Native UIKit launcher UI for on-device testing
- iOS deployment target set to 18.0
- Device policy for RAM, iPad M-series support, and iPad Air M3
- Resolution clamp to 720p or 900p
- External JIT readiness bridge
- SideStore-compatible executable-memory readiness probe
- Game/folder picker with `eboot.bin`, `sce_sys/param.sfo`, and `icon0.png`
  discovery
- GameController.framework detection for DualSense, DualShock 4, Xbox, and MFi
  controllers
- Apple Runtime status panel for tracking which macOS ARM pieces can be reused
- UIKit-owned `CAMetalLayer` renderer surface with a Metal diagnostic clear
- MoltenVK ICD resource packaging when the upstream ICD file is present
- ARM64 dynarec readiness gate tied to external SideStore JIT status
- SDL Metal surface path extended for iOS
- Port notes in `docs/ios-ipados-port.md`

Still needed:

- iOS MoltenVK runtime binary or xcframework linkage
- On-device Vulkan presenter validation through `VK_EXT_metal_surface`
- Touch overlay input for playing without a hardware controller
- PS4 x86_64-to-ARM64 dynarec backend integration
- External JIT provider integration beyond readiness detection
- Real game boot path after renderer, sysmodule, and CPU execution paths are
  connected

## macOS ARM Reuse

The macOS Apple Silicon path is useful, but it cannot be dropped into iPadOS
unchanged. This fork can reuse Apple arm64 build detection, shared C++ state,
controller mapping ideas, and the Metal/MoltenVK rendering direction.

The parts still blocking real game execution are the desktop SDL/macOS window
lifecycle, MoltenVK runtime linkage for iOS, and the x86/xbyak CPU backend. The
app now owns a UIKit `CAMetalLayer` surface and a SideStore-gated ARM64 dynarec
contract, so the next core step is wiring Vulkan/MoltenVK presentation and an
x86_64-to-ARM64 CPU translator into `Core::Emulator::Run`.

## Legal Files and Game Dumps

This repository does not include PlayStation 4 firmware, system modules, games,
keys, or copyrighted Sony content.

Use only files dumped from hardware and games you legally own. Upstream shadPS4
requires supported PS4 firmware modules to be placed in the emulator
`sys_modules` folder when needed.

## Upstream Project

This fork is based on the official shadPS4 emulator:

- Website: [shadps4.net](https://shadps4.net/)
- Upstream repository: [shadps4-emu/shadPS4](https://github.com/shadps4-emu/shadPS4)
- Compatibility tracker: [shadps4-game-compatibility](https://github.com/shadps4-compatibility/shadps4-game-compatibility)
- Discord: [shadPS4 Discord](https://discord.gg/bFJxfftGW6)

Please support and credit the upstream project. This fork exists to explore the
iOS/iPadOS port path, not to replace upstream shadPS4.

## License

This project follows upstream shadPS4 licensing:

- [GPL-2.0-or-later](LICENSE)
