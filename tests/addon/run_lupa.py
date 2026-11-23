"""Run tests/addon/run.lua inside Lua 5.1 provided by the Python package `lupa`.

Usage (from the repo root):
    python tests/addon/run_lupa.py            # run tests
    python tests/addon/run_lupa.py --fixture  # also rewrite tests/fixtures/GreenFangToolkit.sample.lua
    python tests/addon/run_lupa.py --only GF-002  # only the tests whose name has the text

Install once: python -m pip install --user lupa
A standalone Lua 5.1 / LuaJIT works too: lua tests/addon/run.lua
"""
import os
import sys

from lupa import lua51

root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")).replace("\\", "/")
lua = lua51.LuaRuntime(unpack_returned_tuples=True)
g = lua.globals()
g.GF_ROOT = root
g.GF_WRITE_FIXTURE = "--fixture" in sys.argv[1:]
if "--only" in sys.argv[1:]:
    g.GF_ONLY = sys.argv[sys.argv.index("--only") + 1]
lua.execute("arg = {}")
lua.execute('dofile(GF_ROOT .. "/tests/addon/run.lua")')
result = g.GF_TEST_RESULT
sys.exit(0 if result is not None and result.failed == 0 else 1)
