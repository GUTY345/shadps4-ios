// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <string>

namespace Core::IOSPort {

struct MoltenVKRuntimeStatus {
    bool icd_packaged{};
    bool runtime_linked{};
    bool runtime_loadable{};
    std::string provider;
    std::string summary;
    std::string blocker;
};

MoltenVKRuntimeStatus QueryMoltenVKRuntimeStatus();

} // namespace Core::IOSPort
