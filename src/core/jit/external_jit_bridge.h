// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <string>

namespace Core::JIT {

struct ExternalJitStatus {
    bool available;
    std::string provider;
};

struct Arm64DynarecStatus {
    bool arm64_build;
    bool external_jit_available;
    bool dynarec_backend_linked;
    bool executable_memory_ready;
    bool validation_stub_ran;
    bool guest_translator_ready;
    std::string summary;
    std::string blocker;
};

ExternalJitStatus QueryExternalJitStatus();
bool PrepareExternalJit();
Arm64DynarecStatus QueryArm64DynarecStatus();
bool PrepareArm64Dynarec();

} // namespace Core::JIT
