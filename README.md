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

Instead, the branch adds an external JIT bridge in:

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

The normal desktop shadPS4 build path is inherited from upstream. See the
original build documentation:

- [Windows](https://github.com/shadps4-emu/shadPS4/blob/main/documents/building-windows.md)
- [Linux](https://github.com/shadps4-emu/shadPS4/blob/main/documents/building-linux.md)
- [macOS](https://github.com/shadps4-emu/shadPS4/blob/main/documents/building-macos.md)

## Port Status

Implemented in this branch:

- iOS/iPadOS CMake scaffolding
- iOS deployment target set to 18.0
- Device policy for RAM, iPad M-series support, and iPad Air M3
- Resolution clamp to 720p or 900p
- External JIT readiness bridge
- SDL Metal surface path extended for iOS
- Port notes in `docs/ios-ipados-port.md`

Still needed:

- Native iOS app entry point
- UIKit app lifecycle integration
- File picker and sandbox storage flow
- Controller and touch overlay work
- ARM64 CPU backend integration
- External JIT provider integration
- MoltenVK packaging and on-device Vulkan presenter validation

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
