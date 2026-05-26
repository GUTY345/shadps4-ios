// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include "core/jit/external_jit_bridge.h"

#include <cstdlib>
#include <string_view>

#if defined(__APPLE__)
extern "C" bool shadps4_external_jit_is_ready() __attribute__((weak_import));
extern "C" bool shadps4_external_jit_prepare_process() __attribute__((weak_import));
#endif

namespace Core::JIT {

ExternalJitStatus QueryExternalJitStatus() {
#if defined(__APPLE__)
    if (&shadps4_external_jit_is_ready != nullptr && shadps4_external_jit_is_ready()) {
        return {true, "weak external hook"};
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
    if (&shadps4_external_jit_prepare_process != nullptr) {
        return shadps4_external_jit_prepare_process();
    }
#endif
    return QueryExternalJitStatus().available;
}

} // namespace Core::JIT
