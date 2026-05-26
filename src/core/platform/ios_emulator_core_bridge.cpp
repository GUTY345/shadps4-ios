// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include "core/platform/ios_emulator_core_bridge.h"

#include "core/emulator_state.h"

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
