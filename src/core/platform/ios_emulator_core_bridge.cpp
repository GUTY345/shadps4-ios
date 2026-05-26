// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include "core/platform/ios_emulator_core_bridge.h"

#include "core/emulator_state.h"
#include "core/platform/ios_moltenvk_runtime.h"

namespace Core::IOSPort {

EmulatorCoreStatus QueryEmulatorCoreStatus() {
    auto state = EmulatorState::GetInstance();
    state->SetGameRunning(false);

    return {
        .bridge_linked = true,
        .state_core_linked = state != nullptr,
        .full_emulator_linked = false,
        .summary = "iOS launcher is linked to EmulatorState core surface.",
        .blocker =
            "Full Core::Emulator::Run is still blocked by desktop SDL/Vulkan/window dependencies.",
    };
}

AppleRuntimeReuseStatus QueryAppleRuntimeReuseStatus() {
    AppleRuntimeReuseStatus status{};

#if defined(__APPLE__)
    status.apple_platform = true;
#endif

#if defined(__arm64__) || defined(__aarch64__)
    status.arm64_build = true;
#endif

    status.macos_arm_reuse_candidate = status.apple_platform && status.arm64_build;
    status.metal_surface_candidate = status.apple_platform;

#if defined(SHADPS4_IOS_PORT)
    status.ui_kit_metal_surface_linked = true;
    status.desktop_window_blocked = true;
#endif

    const auto moltenvk = QueryMoltenVKRuntimeStatus();
    status.moltenvk_icd_packaged = moltenvk.icd_packaged;
    status.moltenvk_runtime_linked = moltenvk.runtime_linked || moltenvk.runtime_loadable;

#if !defined(__x86_64__) && !defined(_M_X64)
    status.x86_dynarec_blocked = true;
#endif

    if (status.macos_arm_reuse_candidate) {
        status.summary = "Apple Silicon path detected; macOS ARM code can guide the iPadOS port.";
        status.reusable =
            "Reusable now: Apple arm64 build flags, shared C++ state surfaces, controller mapping ideas, "
            "UIKit CAMetalLayer surface, and the Metal/MoltenVK presentation strategy.";
    } else if (status.apple_platform) {
        status.summary = "Apple platform detected, but this build is not arm64.";
        status.reusable = "Reusable now: Apple platform guards and shared C++ core surfaces.";
    } else {
        status.summary = "Non-Apple build; macOS ARM reuse path is not active.";
        status.reusable = "Reusable now: portable core scaffolding only.";
    }

    status.blocker =
        "Not reusable directly yet: the desktop SDL window, macOS app lifecycle, bundled MoltenVK dylib "
        "layout, and x86/xbyak CPU backend. iPadOS still needs MoltenVK runtime linkage and a PS4 "
        "x86_64-to-ARM64 dynarec backend after SideStore opens executable memory.";

    return status;
}

EmulatorCoreStatus QueryRendererSurfaceStatus(bool has_metal_layer, bool has_metal_device) {
    if (!has_metal_layer) {
        return {
            .bridge_linked = true,
            .state_core_linked = true,
            .full_emulator_linked = false,
            .summary = "UIKit renderer surface is not attached.",
            .blocker = "The app did not expose a CAMetalLayer for the renderer.",
        };
    }

    if (!has_metal_device) {
        return {
            .bridge_linked = true,
            .state_core_linked = true,
            .full_emulator_linked = false,
            .summary = "CAMetalLayer is attached, but Metal device creation failed.",
            .blocker = "The iPad must provide a Metal-capable GPU before MoltenVK can present.",
        };
    }

    return {
        .bridge_linked = true,
        .state_core_linked = true,
        .full_emulator_linked = false,
        .summary = "UIKit CAMetalLayer renderer surface is ready.",
        .blocker =
            "Renderer surface is ready; next blocker is connecting Vulkan/MoltenVK presenter and the "
            "ARM64 dynarec backend to Core::Emulator::Run.",
    };
}

EmulatorCoreStatus PrepareEmulatorCoreLaunch(const EmulatorCoreLaunchRequest& request) {
    auto status = QueryEmulatorCoreStatus();
    auto state = EmulatorState::GetInstance();
    state->SetGameRunning(false);
    state->SetAutoPatchesLoadEnabled(true);
    state->SetGameSpecifigConfigUsed(false);

    if (request.game_path.empty()) {
        status.summary = "Core bridge rejected launch request.";
        status.blocker = "No game path was provided.";
        return status;
    }

    if (!request.external_jit_available) {
        status.summary = "Core bridge prepared launch request, then stopped before execution.";
        status.blocker = "External JIT provider is not detected.";
        return status;
    }

    status.summary = "Core bridge accepted the launch request.";
    return status;
}

} // namespace Core::IOSPort
