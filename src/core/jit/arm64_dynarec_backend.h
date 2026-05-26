// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstdint>
#include <string>

namespace Core::JIT::ARM64 {

struct BackendStatus {
    bool compiled_for_arm64{};
    bool backend_linked{};
    bool executable_memory_ready{};
    bool validation_stub_ran{};
    bool guest_translator_ready{};
    std::uint64_t validation_result{};
    std::string summary;
    std::string blocker;
};

BackendStatus QueryBackendStatus(bool external_jit_available);
BackendStatus PrepareBackend(bool external_jit_available);

} // namespace Core::JIT::ARM64
