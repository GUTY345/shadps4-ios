// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include "core/jit/external_jit_bridge.h"

#include "core/jit/arm64_dynarec_backend.h"

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
    const auto backend_status = ARM64::QueryBackendStatus(jit_status.available);
    Arm64DynarecStatus status{
#if defined(__arm64__) || defined(__aarch64__)
        .arm64_build = true,
#else
        .arm64_build = false,
#endif
        .external_jit_available = jit_status.available,
        .dynarec_backend_linked = backend_status.backend_linked,
        .executable_memory_ready = backend_status.executable_memory_ready,
        .validation_stub_ran = backend_status.validation_stub_ran,
        .guest_translator_ready = backend_status.guest_translator_ready,
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

    status.summary = backend_status.summary;
    status.blocker = backend_status.blocker;
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

    const auto jit_status = QueryExternalJitStatus();
    const auto backend_status = ARM64::PrepareBackend(jit_status.available);
    return backend_status.backend_linked && backend_status.validation_stub_ran;
}

} // namespace Core::JIT
