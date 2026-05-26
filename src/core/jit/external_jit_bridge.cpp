// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include "core/jit/external_jit_bridge.h"

#include <cstdlib>
#include <string_view>

#if defined(__APPLE__)
#include <dlfcn.h>
#include <sys/mman.h>
#include <unistd.h>
#endif

namespace Core::JIT {
namespace {

#if defined(__APPLE__)
using ExternalJitHook = bool (*)();

ExternalJitHook FindExternalJitHook(const char* name) {
    return reinterpret_cast<ExternalJitHook>(dlsym(RTLD_DEFAULT, name));
}

bool ProbeExecutableMemoryMapping() {
    const long page_size = sysconf(_SC_PAGESIZE);
    if (page_size <= 0) {
        return false;
    }

    void* page = mmap(nullptr, static_cast<size_t>(page_size), PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANON, -1, 0);
    if (page == MAP_FAILED) {
        return false;
    }

    const bool executable = mprotect(page, static_cast<size_t>(page_size), PROT_READ | PROT_EXEC) == 0;
    munmap(page, static_cast<size_t>(page_size));
    return executable;
}
#endif

} // namespace

ExternalJitStatus QueryExternalJitStatus() {
#if defined(__APPLE__)
    if (const auto hook = FindExternalJitHook("shadps4_external_jit_is_ready");
        hook != nullptr && hook()) {
        return {true, "dynamic external hook"};
    }

    if (ProbeExecutableMemoryMapping()) {
        return {true, "SideStore-compatible executable memory probe"};
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
