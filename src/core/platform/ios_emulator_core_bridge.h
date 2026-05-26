// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstdint>
#include <string>

namespace Core::IOSPort {

struct EmulatorCoreStatus {
    bool bridge_linked{};
    bool state_core_linked{};
    bool full_emulator_linked{};
    std::string summary;
    std::string blocker;
};

struct AppleRuntimeReuseStatus {
    bool apple_platform{};
    bool arm64_build{};
    bool macos_arm_reuse_candidate{};
    bool metal_surface_candidate{};
    bool ui_kit_metal_surface_linked{};
    bool moltenvk_icd_packaged{};
    bool moltenvk_runtime_linked{};
    bool desktop_window_blocked{};
    bool x86_dynarec_blocked{};
    std::string summary;
    std::string reusable;
    std::string blocker;
};

struct EmulatorCoreLaunchRequest {
    std::string game_path;
    std::string resolution_name;
    std::uint32_t resolution_width{};
    std::uint32_t resolution_height{};
    bool external_jit_available{};
    bool enforce_device_policy{true};
};

EmulatorCoreStatus QueryEmulatorCoreStatus();
AppleRuntimeReuseStatus QueryAppleRuntimeReuseStatus();
EmulatorCoreStatus QueryRendererSurfaceStatus(bool has_metal_layer, bool has_metal_device);
EmulatorCoreStatus PrepareEmulatorCoreLaunch(const EmulatorCoreLaunchRequest& request);

} // namespace Core::IOSPort
