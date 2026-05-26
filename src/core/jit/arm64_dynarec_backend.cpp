// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include "core/jit/arm64_dynarec_backend.h"

#include "core/jit/arm64_x64_translator.h"

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
bool g_translation_validation_passed = false;

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

bool EmitAndRunTranslatedValidationBlock(std::uint64_t* result) {
    if (result == nullptr) {
        return false;
    }

    // x86_64: mov eax, 0x345; ret
    constexpr std::array<std::uint8_t, 6> x64_code{
        0xb8U, 0x45U, 0x03U, 0x00U, 0x00U, 0xc3U,
    };
    const auto translated = TranslateX64BasicBlockToArm64(x64_code);
    if (!translated.success || translated.arm64_words.empty()) {
        return false;
    }

    const auto code_size = translated.arm64_words.size() * sizeof(std::uint32_t);
    ExecutablePage page{code_size};
    if (!page.IsValid()) {
        return false;
    }

    using JitWriteProtect = void (*)(int);
    const auto jit_write_protect =
        reinterpret_cast<JitWriteProtect>(dlsym(RTLD_DEFAULT, "pthread_jit_write_protect_np"));
    if (jit_write_protect != nullptr) {
        jit_write_protect(0);
    }
    std::memcpy(page.Data(), translated.arm64_words.data(), code_size);
    sys_icache_invalidate(page.Data(), code_size);
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
        .validation_stub_ran = g_translation_validation_passed,
        .guest_translator_ready = g_translation_validation_passed,
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

    if (g_translation_validation_passed) {
        status.summary = "ARM64 x86_64-to-ARM64 translator pipeline executed successfully.";
        status.blocker =
            "Translator bootstrap is live; more x86_64 opcodes and Core::Emulator::Run integration are next.";
    } else {
        status.summary = "ARM64 dynarec backend is linked and SideStore JIT is available.";
        status.blocker =
            "Translator backend is linked; run preparation to translate and execute the validation block.";
    }
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
    status.validation_stub_ran = EmitAndRunTranslatedValidationBlock(&result);
    status.validation_result = result;
    if (status.validation_stub_ran) {
        g_translation_validation_passed = true;
        status.guest_translator_ready = true;
        status.summary = "ARM64 dynarec translated and executed an x86_64 validation block.";
        status.blocker =
            "Translator bootstrap is ready; extend opcode coverage and connect it to PS4 basic blocks.";
    } else {
        g_translation_validation_passed = false;
        status.guest_translator_ready = false;
        status.summary = "ARM64 dynarec translator validation could not execute.";
        status.blocker =
            "SideStore JIT is reported ready, but x86_64-to-ARM64 translation or code execution failed.";
    }
#else
    status.summary = "ARM64 dynarec validation is not available on this platform.";
    status.blocker = "Run on an Apple arm64 device build.";
#endif

    return status;
}

} // namespace Core::JIT::ARM64
