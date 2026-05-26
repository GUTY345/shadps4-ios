// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <string>

#include "common/types.h"

namespace Core::IOSPort {

struct ResolutionPreset {
    u32 width;
    u32 height;
    const char* name;
};

enum class SupportTier {
    Unsupported,
    Minimum,
    Recommended,
};

struct DevicePolicy {
    SupportTier tier;
    bool is_ipad;
    bool is_ipad_m1_or_newer;
    bool os_version_supported;
    int os_major_version;
    int os_minor_version;
    int os_patch_version;
    u64 physical_memory_bytes;
    std::string machine_identifier;
    std::string reason;
};

constexpr ResolutionPreset Resolution720p{1280, 720, "720p"};
constexpr ResolutionPreset Resolution900p{1600, 900, "900p"};

ResolutionPreset ClampResolution(u32 width, u32 height);
DevicePolicy QueryDevicePolicy();

} // namespace Core::IOSPort
