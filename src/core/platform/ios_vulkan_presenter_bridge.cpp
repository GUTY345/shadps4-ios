// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include "core/platform/ios_vulkan_presenter_bridge.h"

#include "core/platform/ios_moltenvk_runtime.h"

#if defined(__APPLE__)
#define VK_USE_PLATFORM_METAL_EXT
#include <vulkan/vulkan.h>

#include <dlfcn.h>
#include <mach-o/dyld.h>

#include <array>
#include <cstdint>
#include <string>
#endif

namespace Core::IOSPort {
namespace {

#if defined(__APPLE__)

using VkGetInstanceProcAddrFn = PFN_vkGetInstanceProcAddr;

std::string GetExecutableBundleDir() {
    std::array<char, 4096> executable_path{};
    std::uint32_t size = static_cast<std::uint32_t>(executable_path.size());
    if (_NSGetExecutablePath(executable_path.data(), &size) != 0) {
        return {};
    }

    std::string path = executable_path.data();
    const auto slash = path.find_last_of('/');
    if (slash == std::string::npos) {
        return {};
    }

    return path.substr(0, slash);
}

VkGetInstanceProcAddrFn LoadVkGetInstanceProcAddr() {
#if defined(SHADPS4_IOS_MOLTENVK_RUNTIME_LINKED)
    return &vkGetInstanceProcAddr;
#endif

    if (auto* symbol = dlsym(RTLD_DEFAULT, "vkGetInstanceProcAddr"); symbol != nullptr) {
        return reinterpret_cast<VkGetInstanceProcAddrFn>(symbol);
    }

    const std::string bundle_dir = GetExecutableBundleDir();
    const std::array<std::string, 5> candidates{
        bundle_dir + "/Frameworks/MoltenVK.framework/MoltenVK",
        bundle_dir + "/Frameworks/libMoltenVK.dylib",
        bundle_dir + "/libMoltenVK.dylib",
        "MoltenVK.framework/MoltenVK",
        "libMoltenVK.dylib",
    };

    for (const auto& candidate : candidates) {
        void* handle = dlopen(candidate.c_str(), RTLD_NOW | RTLD_LOCAL);
        if (handle == nullptr) {
            continue;
        }
        if (auto* symbol = dlsym(handle, "vkGetInstanceProcAddr"); symbol != nullptr) {
            return reinterpret_cast<VkGetInstanceProcAddrFn>(symbol);
        }
    }

    return nullptr;
}

#endif

} // namespace

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
    const auto moltenvk = QueryMoltenVKRuntimeStatus();
    VulkanPresenterBridgeStatus status{
        .has_metal_layer = window_info.render_surface != nullptr,
        .uses_shared_window_info_contract = true,
        .uses_macos_metal_surface_path = window_info.type == Frontend::WindowSystemType::Metal,
        .moltenvk_runtime_loadable = moltenvk.runtime_loadable,
        .ready_for_vulkan_presenter = window_info.type == Frontend::WindowSystemType::Metal &&
                                      window_info.render_surface != nullptr &&
                                      moltenvk.runtime_loadable,
    };

    if (status.ready_for_vulkan_presenter) {
        status.summary =
            "UIKit CAMetalLayer is using the same WindowSystemInfo::Metal contract as macOS ARM.";
        status.blocker =
            "MoltenVK runtime is loadable; run the Vulkan surface probe before Core::Emulator::Run.";
        return status;
    }

    if (window_info.type != Frontend::WindowSystemType::Metal || window_info.render_surface == nullptr) {
        status.summary = "UIKit CAMetalLayer is not ready for the shared Vulkan presenter path.";
        status.blocker = "Attach a CAMetalLayer before entering the Vulkan/MoltenVK presenter.";
        return status;
    }

    status.summary = "UIKit CAMetalLayer is ready, but MoltenVK runtime is not loadable.";
    status.blocker = moltenvk.blocker;
    return status;
}

VulkanPresenterBridgeStatus ProbeVulkanMetalSurface(const Frontend::WindowSystemInfo& window_info) {
    auto status = QueryVulkanPresenterBridgeStatus(window_info);
    if (window_info.type != Frontend::WindowSystemType::Metal || window_info.render_surface == nullptr) {
        return status;
    }

#if defined(__APPLE__)
    auto* get_instance_proc_addr = LoadVkGetInstanceProcAddr();
    if (get_instance_proc_addr == nullptr) {
        status.summary = "Vulkan loader entry point is not available.";
        status.blocker =
            "MoltenVK must be linked or bundled before vkGetInstanceProcAddr can be resolved.";
        status.ready_for_vulkan_presenter = false;
        return status;
    }

    const auto vk_create_instance = reinterpret_cast<PFN_vkCreateInstance>(
        get_instance_proc_addr(nullptr, "vkCreateInstance"));
    if (vk_create_instance == nullptr) {
        status.summary = "vkCreateInstance is not available from the MoltenVK loader.";
        status.blocker = "MoltenVK runtime loaded, but Vulkan instance creation entry point is missing.";
        status.ready_for_vulkan_presenter = false;
        return status;
    }

    const char* extensions[] = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_EXT_METAL_SURFACE_EXTENSION_NAME,
    };
    const VkApplicationInfo app_info{
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "shadPS4 iOS surface probe",
        .applicationVersion = VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "shadPS4 Vulkan",
        .engineVersion = VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = VK_API_VERSION_1_1,
    };
    const VkInstanceCreateInfo instance_info{
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = 2,
        .ppEnabledExtensionNames = extensions,
    };

    VkInstance instance = VK_NULL_HANDLE;
    VkResult result = vk_create_instance(&instance_info, nullptr, &instance);
    if (result != VK_SUCCESS || instance == VK_NULL_HANDLE) {
        status.summary = "MoltenVK Vulkan instance creation failed.";
        status.blocker = "vkCreateInstance failed before VK_EXT_metal_surface could be tested.";
        status.ready_for_vulkan_presenter = false;
        return status;
    }
    status.vulkan_instance_created = true;

    const auto vk_create_metal_surface = reinterpret_cast<PFN_vkCreateMetalSurfaceEXT>(
        get_instance_proc_addr(instance, "vkCreateMetalSurfaceEXT"));
    const auto vk_destroy_surface = reinterpret_cast<PFN_vkDestroySurfaceKHR>(
        get_instance_proc_addr(instance, "vkDestroySurfaceKHR"));
    const auto vk_destroy_instance = reinterpret_cast<PFN_vkDestroyInstance>(
        get_instance_proc_addr(instance, "vkDestroyInstance"));

    if (vk_create_metal_surface == nullptr) {
        if (vk_destroy_instance != nullptr) {
            vk_destroy_instance(instance, nullptr);
        }
        status.summary = "VK_EXT_metal_surface entry point is not available.";
        status.blocker = "MoltenVK runtime must expose vkCreateMetalSurfaceEXT for the macOS ARM path.";
        status.ready_for_vulkan_presenter = false;
        return status;
    }

    const VkMetalSurfaceCreateInfoEXT surface_info{
        .sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT,
        .pLayer = window_info.render_surface,
    };
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    result = vk_create_metal_surface(instance, &surface_info, nullptr, &surface);
    status.metal_surface_created = result == VK_SUCCESS && surface != VK_NULL_HANDLE;

    if (surface != VK_NULL_HANDLE && vk_destroy_surface != nullptr) {
        vk_destroy_surface(instance, surface, nullptr);
    }
    if (vk_destroy_instance != nullptr) {
        vk_destroy_instance(instance, nullptr);
    }

    if (status.metal_surface_created) {
        status.ready_for_vulkan_presenter = true;
        status.summary = "MoltenVK created VK_EXT_metal_surface from the UIKit CAMetalLayer.";
        status.blocker =
            "Surface probe passed; next step is wiring this shared presenter path into Core::Emulator::Run.";
        return status;
    }

    status.ready_for_vulkan_presenter = false;
    status.summary = "MoltenVK instance exists, but VK_EXT_metal_surface creation failed.";
    status.blocker = "The CAMetalLayer reached the macOS ARM Vulkan path, but surface creation failed.";
    return status;
#else
    status.summary = "Vulkan Metal surface probing is only available on Apple platforms.";
    status.blocker = "Run this probe on iOS/iPadOS or macOS.";
    return status;
#endif
}

} // namespace Core::IOSPort
