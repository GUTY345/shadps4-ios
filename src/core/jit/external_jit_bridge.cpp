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

Arm64DynarecStatus QueryArm64DynarecStatus() {
    const auto jit_status = QueryExternalJitStatus();
    Arm64DynarecStatus status{
#if defined(__arm64__) || defined(__aarch64__)
        .arm64_build = true,
#else
        .arm64_build = false,
#endif
        .external_jit_available = jit_status.available,
        .dynarec_backend_linked = false,
        .executable_memory_ready = jit_status.available,
    };

    if (!status.arm64_build) {
        status.summary = "ARM64 dynarec path is inactive on this architecture.";
        status.blocker = "Build the iOS port for arm64 device hardware.";
        return status;
    }

    if (!status.external_jit_available) {
        status.summary = "ARM64 dynarec gate is waiting for SideStore JIT.";
        status.blocker = "Enable JIT for this app in SideStore, then return and refresh runtime state.";
        return status;
    }

    status.summary = "SideStore JIT gate is open for ARM64 executable memory.";
    status.blocker =
        "The executable-memory gate is ready, but the PS4 x86_64-to-ARM64 dynarec backend is not linked yet.";
    return status;
}

bool PrepareArm64Dynarec() {
    if (!PrepareExternalJit()) {
        return false;
    }

#if defined(__APPLE__)
    if (const auto hook = FindExternalJitHook("shadps4_arm64_dynarec_prepare");
        hook != nullptr) {
        return hook();
    }
#endif

    return QueryArm64DynarecStatus().dynarec_backend_linked;
}

} // namespace Core::JIT
