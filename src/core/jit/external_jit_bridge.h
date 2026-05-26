// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <string>

namespace Core::JIT {

struct ExternalJitStatus {
    bool available;
    std::string provider;
};

ExternalJitStatus QueryExternalJitStatus();
bool PrepareExternalJit();

} // namespace Core::JIT
