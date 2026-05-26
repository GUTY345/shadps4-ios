// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <string>

#include "frontend/window_system_info.h"

namespace Core::IOSPort {

struct VulkanPresenterBridgeStatus {
    bool has_metal_layer{};
    bool uses_shared_window_info_contract{};
    bool uses_macos_metal_surface_path{};
    bool ready_for_vulkan_presenter{};
    std::string summary;
    std::string blocker;
};

Frontend::WindowSystemInfo MakeUIKitMetalWindowSystemInfo(void* metal_layer, float scale);
VulkanPresenterBridgeStatus QueryVulkanPresenterBridgeStatus(
    const Frontend::WindowSystemInfo& window_info);

} // namespace Core::IOSPort
