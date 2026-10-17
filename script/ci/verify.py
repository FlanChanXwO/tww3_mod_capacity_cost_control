"""Run local, non-game validation for the mod project."""

from __future__ import annotations

import subprocess
import sys
import argparse
import importlib.util
import unittest
from pathlib import Path

from luaparser import ast

ROOT = Path(__file__).resolve().parents[2]
BUILD_SCRIPTS = ROOT / "script" / "build"
sys.path.insert(0, str(BUILD_SCRIPTS))


def run(*args: str) -> None:
    subprocess.run(args, cwd=ROOT, check=True)


def run_tests(directory: Path) -> None:
    # 显式收集顶层文件，临时目录即使含 __init__.py 也不会进入默认验证。
    sys.path.insert(0, str(directory))
    suite = unittest.TestSuite(
        unittest.defaultTestLoader.loadTestsFromName(path.stem)
        for path in sorted(directory.glob("test_*.py"))
    )
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip-pack", action="store_true", help="Skip RPFM pack creation while keeping all other checks.")
    args = parser.parse_args()
    run_tests(ROOT / "tests")
    run_tests(ROOT / "script" / "ci" / "tests")
    run(sys.executable, "-m", "py_compile", *(str(path) for path in (ROOT / "script").rglob("*.py")))
    if not args.skip_pack:
        run(sys.executable, "script/build/build_mod.py")
    else:
        spec = importlib.util.spec_from_file_location("build_mod", BUILD_SCRIPTS / "build_mod.py")
        assert spec and spec.loader
        build_mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(build_mod)
        metadata = build_mod.load_metadata()
        build_mod.generate_lua(metadata)
        build_mod.generate_i18_lua()
        build_mod.generate_project_metadata()
        build_mod.generate_tsv(metadata)
        build_mod.generate_bundles_tsv(metadata)

    lua_files = list((ROOT / "src").rglob("*.lua")) + list((ROOT / "tests" / "lua").rglob("*.lua"))
    lua_files.extend(ROOT / "build" / "generated" / name for name in ("generated_data.lua", "i18.lua", "metadata.lua"))
    for path in lua_files:
        print(f"Parsing Lua: {path.relative_to(ROOT)}")
        ast.parse(path.read_text(encoding="utf-8"))

    print(f"Lua parsed: {len(lua_files)}")
    if not args.skip_pack:
        print(f"Pack: {ROOT / 'build' / 'tww3_mod_capacity_cost_control.pack'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
