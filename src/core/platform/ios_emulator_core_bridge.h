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

struct EmulatorCoreLaunchRequest {
    std::string game_path;
    std::string resolution_name;
    std::uint32_t resolution_width{};
    std::uint32_t resolution_height{};
    bool external_jit_available{};
    bool enforce_device_policy{true};
};

EmulatorCoreStatus QueryEmulatorCoreStatus();
EmulatorCoreStatus PrepareEmulatorCoreLaunch(const EmulatorCoreLaunchRequest& request);

} // namespace Core::IOSPort
