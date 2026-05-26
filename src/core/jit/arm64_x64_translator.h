// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstdint>
#include <span>
#include <string>
#include <vector>

namespace Core::JIT::ARM64 {

struct TranslationResult {
    bool success{};
    std::vector<std::uint32_t> arm64_words;
    std::string summary;
    std::string blocker;
};

TranslationResult TranslateX64BasicBlockToArm64(std::span<const std::uint8_t> x64_code);

} // namespace Core::JIT::ARM64
