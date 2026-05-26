// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include "core/platform/ios_device_policy.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <sys/sysctl.h>

#include <array>
#include <cmath>
#include <cstdlib>

namespace Core::IOSPort {
namespace {

constexpr u64 GiB = 1024ULL * 1024ULL * 1024ULL;
constexpr u64 MinimumMemoryBytes = 6ULL * GiB;
constexpr u64 RecommendedMemoryBytes = 8ULL * GiB;
constexpr int MinimumOSMajorVersion = 18;

std::string QuerySysctlString(const char* key) {
    size_t size = 0;
    if (sysctlbyname(key, nullptr, &size, nullptr, 0) != 0 || size == 0) {
        return {};
    }

    std::string value(size, '\0');
    if (sysctlbyname(key, value.data(), &size, nullptr, 0) != 0) {
        return {};
    }
    if (!value.empty() && value.back() == '\0') {
        value.pop_back();
    }
    return value;
}

u64 QueryPhysicalMemoryBytes() {
    return static_cast<u64>([[NSProcessInfo processInfo] physicalMemory]);
}

bool MachineIdentifierInRange(const std::string& machine, int major, int min_minor,
                              int max_minor) {
    const std::string prefix = "iPad" + std::to_string(major) + ",";
    if (!machine.starts_with(prefix)) {
        return false;
    }

    char* end = nullptr;
    const long minor = std::strtol(machine.c_str() + prefix.size(), &end, 10);
    return end != nullptr && *end == '\0' && minor >= min_minor && minor <= max_minor;
}

bool IsKnownMSeriesIPad(const std::string& machine) {
    // M1 iPad Pro 2021: iPad13,4-iPad13,11. M1 iPad Air: iPad13,16-iPad13,17.
    // Later M-series iPads use explicit allow ranges so A-series iPads are not admitted by accident.
    // iPad Air M3 test devices are iPad15,3-iPad15,6.
    return MachineIdentifierInRange(machine, 13, 4, 11) ||
           MachineIdentifierInRange(machine, 13, 16, 17) ||
           MachineIdentifierInRange(machine, 14, 3, 6) ||
           MachineIdentifierInRange(machine, 14, 8, 11) ||
           MachineIdentifierInRange(machine, 15, 3, 6) ||
           MachineIdentifierInRange(machine, 16, 3, 6);
}

} // namespace

ResolutionPreset ClampResolution(u32 width, u32 height) {
    const auto score = [width, height](ResolutionPreset preset) {
        return std::abs(static_cast<int>(width) - static_cast<int>(preset.width)) +
               std::abs(static_cast<int>(height) - static_cast<int>(preset.height));
    };

    return score(Resolution900p) < score(Resolution720p) ? Resolution900p : Resolution720p;
}

DevicePolicy QueryDevicePolicy() {
    DevicePolicy policy{};
    policy.machine_identifier = QuerySysctlString("hw.machine");
    policy.physical_memory_bytes = QueryPhysicalMemoryBytes();
    policy.is_ipad = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;
    policy.is_ipad_m1_or_newer = policy.is_ipad && IsKnownMSeriesIPad(policy.machine_identifier);
    const NSOperatingSystemVersion os_version = [[NSProcessInfo processInfo] operatingSystemVersion];
    policy.os_major_version = static_cast<int>(os_version.majorVersion);
    policy.os_minor_version = static_cast<int>(os_version.minorVersion);
    policy.os_patch_version = static_cast<int>(os_version.patchVersion);
    policy.os_version_supported = policy.os_major_version >= MinimumOSMajorVersion;

    if (!policy.os_version_supported) {
        policy.tier = SupportTier::Unsupported;
        policy.reason = "iOS/iPadOS 18 or newer is required.";
        return policy;
    }

    if (policy.is_ipad && !policy.is_ipad_m1_or_newer) {
        policy.tier = SupportTier::Unsupported;
        policy.reason = "iPadOS requires an M1 iPad or newer.";
        return policy;
    }

    if (policy.physical_memory_bytes < MinimumMemoryBytes) {
        policy.tier = SupportTier::Unsupported;
        policy.reason = "iOS/iPadOS requires at least 6 GB RAM.";
        return policy;
    }

    policy.tier =
        policy.physical_memory_bytes >= RecommendedMemoryBytes ? SupportTier::Recommended
                                                               : SupportTier::Minimum;
    policy.reason =
        policy.tier == SupportTier::Recommended ? "Recommended device." : "Minimum RAM device.";
    return policy;
}

} // namespace Core::IOSPort
