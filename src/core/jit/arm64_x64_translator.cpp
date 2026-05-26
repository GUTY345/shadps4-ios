// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include "core/jit/arm64_x64_translator.h"

#include <algorithm>
#include <cstddef>

namespace Core::JIT::ARM64 {
namespace {

constexpr std::uint32_t Arm64Ret = 0xd65f03c0U;

std::uint32_t EncodeMovzX0(std::uint16_t imm, unsigned shift) {
    return 0xd2800000U | (static_cast<std::uint32_t>(shift / 16U) << 21U) |
           (static_cast<std::uint32_t>(imm) << 5U);
}

std::uint32_t EncodeMovkX0(std::uint16_t imm, unsigned shift) {
    return 0xf2800000U | (static_cast<std::uint32_t>(shift / 16U) << 21U) |
           (static_cast<std::uint32_t>(imm) << 5U);
}

void EmitMoveX0Immediate(std::uint64_t value, std::vector<std::uint32_t>& out) {
    out.push_back(EncodeMovzX0(static_cast<std::uint16_t>(value), 0));
    for (unsigned shift = 16; shift < 64; shift += 16) {
        const auto part = static_cast<std::uint16_t>(value >> shift);
        if (part != 0) {
            out.push_back(EncodeMovkX0(part, shift));
        }
    }
}

std::uint32_t ReadU32(std::span<const std::uint8_t> code, std::size_t offset) {
    return static_cast<std::uint32_t>(code[offset]) |
           (static_cast<std::uint32_t>(code[offset + 1]) << 8U) |
           (static_cast<std::uint32_t>(code[offset + 2]) << 16U) |
           (static_cast<std::uint32_t>(code[offset + 3]) << 24U);
}

} // namespace

TranslationResult TranslateX64BasicBlockToArm64(std::span<const std::uint8_t> x64_code) {
    TranslationResult result{};
    std::size_t pc = 0;
    bool saw_return = false;
    bool wrote_return_value = false;

    while (pc < x64_code.size()) {
        const std::uint8_t opcode = x64_code[pc];

        if (opcode == 0x90) {
            pc += 1;
            continue;
        }

        if (opcode == 0xc3) {
            saw_return = true;
            result.arm64_words.push_back(Arm64Ret);
            pc += 1;
            break;
        }

        if (opcode == 0xb8) {
            if (pc + 5 > x64_code.size()) {
                result.blocker = "Truncated x86_64 MOV EAX, imm32 instruction.";
                return result;
            }
            EmitMoveX0Immediate(ReadU32(x64_code, pc + 1), result.arm64_words);
            wrote_return_value = true;
            pc += 5;
            continue;
        }

        if (opcode == 0x31 && pc + 1 < x64_code.size() && x64_code[pc + 1] == 0xc0) {
            EmitMoveX0Immediate(0, result.arm64_words);
            wrote_return_value = true;
            pc += 2;
            continue;
        }

        if (opcode == 0x48 && pc + 2 < x64_code.size() && x64_code[pc + 1] == 0x31 &&
            x64_code[pc + 2] == 0xc0) {
            EmitMoveX0Immediate(0, result.arm64_words);
            wrote_return_value = true;
            pc += 3;
            continue;
        }

        result.blocker = "Unsupported x86_64 opcode reached by the ARM64 translator.";
        return result;
    }

    if (!saw_return) {
        result.blocker = "Translated block did not terminate with RET.";
        return result;
    }

    if (!wrote_return_value) {
        EmitMoveX0Immediate(0, result.arm64_words);
        std::rotate(result.arm64_words.rbegin(), result.arm64_words.rbegin() + 1,
                    result.arm64_words.rend());
    }

    result.success = true;
    result.summary = "Translated a minimal x86_64 basic block into executable ARM64 code.";
    return result;
}

} // namespace Core::JIT::ARM64
