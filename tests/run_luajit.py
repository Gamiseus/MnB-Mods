"""Runs a Lua test file with the game's own LuaJIT (game/lua51.dll), so the mods are tested
on the Lua version they run on.

    python tests/run_luajit.py tests/perfkit_test.lua [path/to/lua51.dll]

Run it from the MnB-Mods folder. Exit code 0 when the file ran without an error.
"""
import ctypes
import os
import sys


def main():
    test = sys.argv[1]
    dll = sys.argv[2] if len(sys.argv) > 2 else os.path.join("..", "game", "lua51.dll")
    dll = os.path.abspath(dll)
    if not os.path.isfile(dll):
        print("lua51.dll not found at", dll)
        return 2
    os.add_dll_directory(os.path.dirname(dll))
    lua = ctypes.CDLL(dll)
    lua.luaL_newstate.restype = ctypes.c_void_p
    lua.lua_tolstring.restype = ctypes.c_char_p
    lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
    state = ctypes.c_void_p(lua.luaL_newstate())
    lua.luaL_openlibs(state)
    chunk = ('local ok, err = xpcall(function() dofile(%r) end, debug.traceback) '
             'if not ok then error(err, 0) end' % test.replace("\\", "/")).encode()
    if lua.luaL_loadstring(state, chunk) != 0 or lua.lua_pcall(state, 0, 0, 0) != 0:
        print(lua.lua_tolstring(state, -1, None).decode(errors="replace"))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
