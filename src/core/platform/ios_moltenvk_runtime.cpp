// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include "core/platform/ios_moltenvk_runtime.h"

#if defined(__APPLE__)
#include <dlfcn.h>
#include <mach-o/dyld.h>

#include <array>
#include <cstdint>
#endif

namespace Core::IOSPort {
namespace {

#if defined(__APPLE__)

bool TryDlopen(const char* path) {
    void* handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (handle == nullptr) {
        return false;
    }
    dlclose(handle);
    return true;
}

bool TryLoadBundledRuntime(std::string* provider) {
    std::array<char, 4096> executable_path{};
    std::uint32_t size = static_cast<std::uint32_t>(executable_path.size());
    if (_NSGetExecutablePath(executable_path.data(), &size) != 0) {
        return false;
    }

    std::string path = executable_path.data();
    const auto slash = path.find_last_of('/');
    if (slash == std::string::npos) {
        return false;
    }

    const std::string bundle_dir = path.substr(0, slash);
    const std::array<std::string, 3> candidates{
        bundle_dir + "/Frameworks/MoltenVK.framework/MoltenVK",
        bundle_dir + "/Frameworks/libMoltenVK.dylib",
        bundle_dir + "/libMoltenVK.dylib",
    };

    for (const auto& candidate : candidates) {
        if (TryDlopen(candidate.c_str())) {
            if (provider != nullptr) {
                *provider = candidate;
            }
            return true;
        }
    }

    return false;
}

#endif

} // namespace

MoltenVKRuntimeStatus QueryMoltenVKRuntimeStatus() {
    MoltenVKRuntimeStatus status{
#if defined(SHADPS4_IOS_MOLTENVK_ICD_PACKAGED)
        .icd_packaged = true,
#else
        .icd_packaged = false,
#endif
#if defined(SHADPS4_IOS_MOLTENVK_RUNTIME_LINKED)
        .runtime_linked = true,
#else
        .runtime_linked = false,
#endif
    };

#if defined(__APPLE__)
    status.runtime_loadable = status.runtime_linked || TryLoadBundledRuntime(&status.provider);
#else
    status.runtime_loadable = status.runtime_linked;
#endif

    if (status.runtime_loadable) {
        if (status.provider.empty()) {
            status.provider = "linked MoltenVK runtime";
        }
        status.summary = "MoltenVK runtime is available for the iOS app.";
        status.blocker = "Next step is creating the Vulkan instance with VK_EXT_metal_surface.";
        return status;
    }

    if (status.icd_packaged) {
        status.provider = "MoltenVK ICD packaged";
        status.summary = "MoltenVK ICD is packaged, but the runtime binary is not loadable.";
        status.blocker =
            "Place MoltenVK.xcframework, MoltenVK.framework, or libMoltenVK.dylib in the configured "
            "iOS runtime path so CMake can link or bundle it.";
        return status;
    }

    status.provider = "missing";
    status.summary = "MoltenVK runtime is not packaged for iOS yet.";
    status.blocker =
        "Add an iOS MoltenVK runtime binary or set SHADPS4_IOS_MOLTENVK_XCFRAMEWORK when configuring.";
    return status;
}

} // namespace Core::IOSPort
