// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include "core/jit/external_jit_bridge.h"

#include <cstdlib>
#include <string_view>

#if defined(__APPLE__)
#include <dlfcn.h>
#endif

namespace Core::JIT {
namespace {

#if defined(__APPLE__)
using ExternalJitHook = bool (*)();

ExternalJitHook FindExternalJitHook(const char* name) {
    return reinterpret_cast<ExternalJitHook>(dlsym(RTLD_DEFAULT, name));
}
#endif

} // namespace

ExternalJitStatus QueryExternalJitStatus() {
#if defined(__APPLE__)
    if (const auto hook = FindExternalJitHook("shadps4_external_jit_is_ready");
        hook != nullptr && hook()) {
        return {true, "dynamic external hook"};
    }
#endif

    const char* env = std::getenv("SHADPS4_EXTERNAL_JIT_READY");
    if (env != nullptr && std::string_view{env} == "1") {
        return {true, "environment marker"};
    }

    return {false, "not detected"};
}

bool PrepareExternalJit() {
#if defined(__APPLE__)
    if (const auto hook = FindExternalJitHook("shadps4_external_jit_prepare_process");
        hook != nullptr) {
        return hook();
    }
#endif
    return QueryExternalJitStatus().available;
}

} // namespace Core::JIT
