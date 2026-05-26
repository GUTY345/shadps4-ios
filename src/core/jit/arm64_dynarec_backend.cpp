// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include "core/jit/arm64_dynarec_backend.h"

#include <array>
#include <cstddef>
#include <cstring>

#if defined(__APPLE__)
#include <dlfcn.h>
#include <sys/mman.h>
#include <unistd.h>

#if defined(__arm64__) || defined(__aarch64__)
extern "C" void sys_icache_invalidate(void* start, size_t len);
#endif
#endif

namespace Core::JIT::ARM64 {
namespace {

constexpr std::uint64_t ValidationValue = 0x345;

#if defined(__APPLE__) && (defined(__arm64__) || defined(__aarch64__))

class ExecutablePage {
public:
    explicit ExecutablePage(std::size_t size) : size_{RoundToPageSize(size)} {
        memory_ = mmap(nullptr, size_, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    }

    ~ExecutablePage() {
        if (IsValid()) {
            munmap(memory_, size_);
        }
    }

    ExecutablePage(const ExecutablePage&) = delete;
    ExecutablePage& operator=(const ExecutablePage&) = delete;

    bool IsValid() const {
        return memory_ != MAP_FAILED && memory_ != nullptr;
    }

    void* Data() const {
        return memory_;
    }

    std::size_t Size() const {
        return size_;
    }

    bool ProtectExecutable() {
        return IsValid() && mprotect(memory_, size_, PROT_READ | PROT_EXEC) == 0;
    }

private:
    static std::size_t RoundToPageSize(std::size_t size) {
        const long page_size = sysconf(_SC_PAGESIZE);
        const std::size_t granularity = page_size > 0 ? static_cast<std::size_t>(page_size) : 16384U;
        return ((size + granularity - 1U) / granularity) * granularity;
    }

    void* memory_{MAP_FAILED};
    std::size_t size_{};
};

bool EmitAndRunValidationStub(std::uint64_t* result) {
    if (result == nullptr) {
        return false;
    }

    // movz x0, #0x345; ret
    constexpr std::array<std::uint32_t, 2> code{
        0xd28068a0U,
        0xd65f03c0U,
    };

    ExecutablePage page{code.size() * sizeof(std::uint32_t)};
    if (!page.IsValid()) {
        return false;
    }

    using JitWriteProtect = void (*)(int);
    const auto jit_write_protect =
        reinterpret_cast<JitWriteProtect>(dlsym(RTLD_DEFAULT, "pthread_jit_write_protect_np"));
    if (jit_write_protect != nullptr) {
        jit_write_protect(0);
    }
    std::memcpy(page.Data(), code.data(), code.size() * sizeof(std::uint32_t));
    sys_icache_invalidate(page.Data(), code.size() * sizeof(std::uint32_t));
    if (jit_write_protect != nullptr) {
        jit_write_protect(1);
    }

    if (!page.ProtectExecutable()) {
        return false;
    }

    using Stub = std::uint64_t (*)();
    const auto stub = reinterpret_cast<Stub>(page.Data());
    *result = stub();
    return *result == ValidationValue;
}

#endif

BackendStatus MakeBaseStatus(bool external_jit_available) {
    BackendStatus status{
#if defined(__arm64__) || defined(__aarch64__)
        .compiled_for_arm64 = true,
#else
        .compiled_for_arm64 = false,
#endif
        .backend_linked = true,
        .executable_memory_ready = external_jit_available,
        .validation_stub_ran = false,
        .guest_translator_ready = false,
        .validation_result = 0,
    };

    if (!status.compiled_for_arm64) {
        status.summary = "ARM64 dynarec backend is linked, but this build is not arm64.";
        status.blocker = "Build for an iOS arm64 device target.";
        return status;
    }

    if (!external_jit_available) {
        status.summary = "ARM64 dynarec backend is linked and waiting for SideStore JIT.";
        status.blocker = "Enable JIT for this app in SideStore before executable code pages are used.";
        return status;
    }

    status.summary = "ARM64 dynarec backend is linked and SideStore JIT is available.";
    status.blocker =
        "Validation codegen is available; the full PS4 x86_64 instruction translator is still being built.";
    return status;
}

} // namespace

BackendStatus QueryBackendStatus(bool external_jit_available) {
    return MakeBaseStatus(external_jit_available);
}

BackendStatus PrepareBackend(bool external_jit_available) {
    auto status = MakeBaseStatus(external_jit_available);
    if (!status.compiled_for_arm64 || !external_jit_available) {
        return status;
    }

#if defined(__APPLE__) && (defined(__arm64__) || defined(__aarch64__))
    std::uint64_t result = 0;
    status.validation_stub_ran = EmitAndRunValidationStub(&result);
    status.validation_result = result;
    if (status.validation_stub_ran) {
        status.summary = "ARM64 dynarec validation stub executed successfully.";
        status.blocker =
            "The executable ARM64 code path works; next step is translating PS4 x86_64 basic blocks.";
    } else {
        status.summary = "ARM64 dynarec validation stub could not execute.";
        status.blocker =
            "SideStore JIT is reported ready, but executable page allocation or code execution failed.";
    }
#else
    status.summary = "ARM64 dynarec validation is not available on this platform.";
    status.blocker = "Run on an Apple arm64 device build.";
#endif

    return status;
}

} // namespace Core::JIT::ARM64
