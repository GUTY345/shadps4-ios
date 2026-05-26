// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <string>

#include "common/types.h"
#include "core/libraries/pad/pad.h"
#include "frontend/window_system_info.h"
#include "input/controller.h"

struct SDL_Window;
struct SDL_Gamepad;
union SDL_Event;

namespace Input {
class GameController;
}

namespace Frontend {

class WindowSDL {
    int keyboard_grab = 0;

public:
    explicit WindowSDL(s32 width, s32 height, Input::GameControllers* controllers,
                       std::string_view window_title);
    ~WindowSDL();

    s32 GetWidth() const {
        return width;
    }

    s32 GetHeight() const {
        return height;
    }

    bool IsOpen() const {
        return is_open;
    }

    [[nodiscard]] SDL_Window* GetSDLWindow() const {
        return window;
    }

    WindowSystemInfo GetWindowInfo() const {
        return window_info;
    }

    void WaitEvent();
    void InitTimers();

    void RequestKeyboard();
    void ReleaseKeyboard();

private:
    void OnResize();
    void OnKeyboardMouseInput(const SDL_Event* event);
    void OnGamepadEvent(const SDL_Event* event);

private:
    s32 width;
    s32 height;
    Input::GameControllers controllers{};
    WindowSystemInfo window_info{};
    SDL_Window* window{};
    bool is_shown{};
    bool is_open{true};
};

} // namespace Frontend
