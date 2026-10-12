#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run original sink code in an existing Lua 5.1/5.2 library, without installs.

Engine functions are simulated by the Lua tests. Passing this is standalone
lifecycle verification, not proof of a game frame or its live Lua bindings.
"""
from __future__ import annotations

import argparse
import ctypes
import os
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-library", type=Path, required=True)
    parser.add_argument("--module", type=Path, default=Path(__file__).resolve().parents[1] / "lua/data/scripts/mods/minecome.lua")
    parser.add_argument("--tests", type=Path, default=Path(__file__).with_name("lua_sink_tests.lua"))
    args = parser.parse_args()
    for path in (args.lua_library, args.module, args.tests):
        if not path.is_file():
            parser.error(f"File unavailable: {path}")

    # Lua's public API uses cdecl, including on Windows. Load only the explicitly
    # supplied existing library; this runner never searches or installs a DLL.
    lua = ctypes.CDLL(str(args.lua_library.resolve()))
    state_type = ctypes.c_void_p
    lua.luaL_newstate.argtypes = []
    lua.luaL_newstate.restype = state_type
    lua.luaL_openlibs.argtypes = [state_type]
    lua.luaL_openlibs.restype = None
    lua.lua_pushstring.argtypes = [state_type, ctypes.c_char_p]
    lua.lua_pushstring.restype = ctypes.c_void_p
    exported_setglobal = hasattr(lua, "lua_setglobal")
    if exported_setglobal:
        lua.lua_setglobal.argtypes = [state_type, ctypes.c_char_p]
        lua.lua_setglobal.restype = None
    else:
        # Lua 5.1 exposes lua_setglobal as a lua_setfield macro.
        lua.lua_setfield.argtypes = [state_type, ctypes.c_int, ctypes.c_char_p]
        lua.lua_setfield.restype = None
    lua.lua_tolstring.argtypes = [state_type, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
    lua.lua_tolstring.restype = ctypes.c_void_p
    lua.lua_close.argtypes = [state_type]
    lua.lua_close.restype = None

    modern_api = hasattr(lua, "luaL_loadfilex") and hasattr(lua, "lua_pcallk")
    if modern_api:
        lua.luaL_loadfilex.argtypes = [state_type, ctypes.c_char_p, ctypes.c_char_p]
        lua.luaL_loadfilex.restype = ctypes.c_int
        lua.lua_pcallk.argtypes = [state_type, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
        lua.lua_pcallk.restype = ctypes.c_int
    else:
        lua.luaL_loadfile.argtypes = [state_type, ctypes.c_char_p]
        lua.luaL_loadfile.restype = ctypes.c_int
        lua.lua_pcall.argtypes = [state_type, ctypes.c_int, ctypes.c_int, ctypes.c_int]
        lua.lua_pcall.restype = ctypes.c_int

    state = lua.luaL_newstate()
    if not state:
        raise RuntimeError("Lua could not allocate a state")
    try:
        lua.luaL_openlibs(state)
        lua.lua_pushstring(state, os.fsencode(args.module.resolve()))
        if exported_setglobal:
            lua.lua_setglobal(state, b"MINECOME_MODULE_PATH")
        else:
            lua.lua_setfield(state, -10002, b"MINECOME_MODULE_PATH")
        if modern_api:
            result = lua.luaL_loadfilex(state, os.fsencode(args.tests.resolve()), None)
            if result == 0:
                result = lua.lua_pcallk(state, 0, -1, 0, 0, None)
        else:
            result = lua.luaL_loadfile(state, os.fsencode(args.tests.resolve()))
            if result == 0:
                result = lua.lua_pcall(state, 0, -1, 0)
        if result:
            length = ctypes.c_size_t()
            message = lua.lua_tolstring(state, -1, ctypes.byref(length))
            error = ctypes.string_at(message, length.value).decode("utf-8", "replace") if message else "Unknown Lua error"
            print(error)
            return 1
        print("Standalone Lua sink verified; engine bindings were simulated.")
        return 0
    finally:
        lua.lua_close(state)


if __name__ == "__main__":
    raise SystemExit(main())
