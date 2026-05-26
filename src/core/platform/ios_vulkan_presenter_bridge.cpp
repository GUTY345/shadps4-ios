// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include "core/platform/ios_vulkan_presenter_bridge.h"

namespace Core::IOSPort {

Frontend::WindowSystemInfo MakeUIKitMetalWindowSystemInfo(void* metal_layer, float scale) {
    return {
        .display_connection = nullptr,
        .render_surface = metal_layer,
        .render_surface_scale = scale > 0.0f ? scale : 1.0f,
        .type = metal_layer != nullptr ? Frontend::WindowSystemType::Metal
                                       : Frontend::WindowSystemType::Headless,
    };
}

VulkanPresenterBridgeStatus QueryVulkanPresenterBridgeStatus(
    const Frontend::WindowSystemInfo& window_info) {
    VulkanPresenterBridgeStatus status{
        .has_metal_layer = window_info.render_surface != nullptr,
        .uses_shared_window_info_contract = true,
        .uses_macos_metal_surface_path = window_info.type == Frontend::WindowSystemType::Metal,
        .ready_for_vulkan_presenter = window_info.type == Frontend::WindowSystemType::Metal &&
                                      window_info.render_surface != nullptr,
    };

    if (status.ready_for_vulkan_presenter) {
        status.summary =
            "UIKit CAMetalLayer is using the same WindowSystemInfo::Metal contract as macOS ARM.";
        status.blocker =
            "Next step is linking MoltenVK runtime so Vulkan::CreateSurface can create "
            "VK_EXT_metal_surface from this CAMetalLayer.";
        return status;
    }

    status.summary = "UIKit CAMetalLayer is not ready for the shared Vulkan presenter path.";
    status.blocker = "Attach a CAMetalLayer before entering the Vulkan/MoltenVK presenter.";
    return status;
}

} // namespace Core::IOSPort
