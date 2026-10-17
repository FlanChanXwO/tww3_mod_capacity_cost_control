from __future__ import annotations

import csv
import importlib.util
import sys
import tempfile
import unittest
import json
from pathlib import Path
from typing import Any
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[1]
BUILD_PATH = ROOT / "script" / "build" / "build_mod.py"

BUILD_SCRIPTS = ROOT / "script" / "build"
if str(BUILD_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(BUILD_SCRIPTS))


def load_build_module() -> Any:
    # 动态加载的模块，类型检查器无法推断其属性（如 CACHE）。
    spec = importlib.util.spec_from_file_location("build_mod", BUILD_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class BuildOutputTests(unittest.TestCase):
    def test_project_metadata_generates_new_identity(self) -> None:
        build_mod = load_build_module()
        with tempfile.TemporaryDirectory() as temp_dir:
            old_cache = build_mod.CACHE
            build_mod.CACHE = Path(temp_dir)
            try:
                path = build_mod.generate_project_metadata()
                text = path.read_text(encoding="utf-8")
            finally:
                build_mod.CACHE = old_cache
        self.assertIn('technical_name = "tww3_mod_capacity_cost_control"', text)
        self.assertIn('mod_key = "tww3_mod_capacity_cost_control"', text)
        self.assertIn('author = "FlanChanXwO"', text)

    def test_pack_inputs_use_namespaced_modules_and_unique_entries(self) -> None:
        build_mod = load_build_module()
        client = Mock()
        generated = [build_mod.CACHE / name for name in ("generated_data.lua", "i18.lua", "metadata.lua")]
        build_mod.add_source_files(client, "test-pack", *generated)
        paths = set()
        for call in client.call_tool.call_args_list:
            args = call.args[1]
            source = Path(args["source_paths"][0])
            internal = json.loads(args["destination_paths"])[0]["File"]
            paths.add(internal)
            if source not in generated:
                self.assertTrue(source.is_file())
        for relative in ("shared/generated_data.lua", "shared/i18.lua", "config/metadata.lua"):
            self.assertIn("script/campaign/capacity_cost_control/" + relative, paths)
        self.assertIn("script/campaign/capacity_cost_control/store/purchases.lua", paths)
        self.assertIn("script/campaign/capacity_cost_control/config/settings.lua", paths)
        self.assertIn("script/mct/capacity_cost_control/layout.lua", paths)
        self.assertEqual({path for path in paths if path.startswith("script/campaign/mod/")},
                         {"script/campaign/mod/tww3_mod_capacity_cost_control_main.lua"})
        self.assertEqual({path for path in paths if path.startswith("script/mct/settings/")},
                         {"script/mct/settings/tww3_mod_capacity_cost_control_mct.lua"})
        self.assertFalse(any(path.startswith("script/campaign/tww3_mod_") for path in paths))

    def test_amethyst_db_only_disables_growth_for_four_capacity_rituals(self) -> None:
        metadata = load_build_module().load_metadata()
        with (ROOT / "data" / "amethyst_rituals.tsv").open(encoding="utf-8", newline="") as stream:
            reader = csv.DictReader(stream, delimiter="\t")
            next(reader)  # RPFM 表版本行。
            rows = list(reader)
        self.assertEqual({row["key"] for row in rows}, {r[0] for r in metadata["amethyst"]["rituals"]})
        self.assertEqual(len(rows), 4)
        for row in rows:
            with self.subTest(ritual=row["key"]):
                self.assertEqual(float(row["percentage_cost_increase_per_use"]), 0)
                self.assertEqual(row["completion_payload"], row["key"])
                self.assertEqual(row["expended_resources"], row["key"])
                self.assertEqual(row["category"], "DON_AMETHYST_ARMORY_UNITS")
                self.assertEqual(row["flags"], "default")
                self.assertEqual(row["max_times_cost_can_increase"], "2147483647")


    def test_bhashiva_db_only_disables_growth_for_ten_capacity_rituals(self) -> None:
        metadata = load_build_module().load_metadata()["bhashiva"]
        with (ROOT / "data" / "bhashiva_rituals.tsv").open(encoding="utf-8", newline="") as stream:
            reader = csv.DictReader(stream, delimiter="\t")
            next(reader)
            rows = {row["key"]: row for row in reader}
        self.assertEqual(set(rows), {r[0] for r in metadata["rituals"]})
        self.assertEqual(len(rows), 10)
        for key, _effect, _rate, cap, _base in metadata["rituals"]:
            with self.subTest(ritual=key):
                row = rows[key]
                self.assertEqual(row["percentage_cost_increase_per_use"], "0.0000")
                self.assertEqual(row["completion_payload"], key + "_payload")
                self.assertEqual(row["category"], "CP1_TW_ARMIES_CAPACITY")
                self.assertTrue(row["expended_resources"].startswith("wh3_cp1_ritual_cth_shang_yang_"))
                self.assertEqual(row["flags"], "default")
                self.assertEqual(int(row["max_times_cost_can_increase"]), cap)

    def test_generated_db_sources_have_one_row_per_ritual(self) -> None:
        build_mod = load_build_module()
        metadata = build_mod.load_metadata()

        with tempfile.TemporaryDirectory() as temp_dir:
            old_cache = build_mod.CACHE
            build_mod.CACHE = Path(temp_dir)
            try:
                effects_path, junctions_path = build_mod.generate_tsv(metadata)
            finally:
                build_mod.CACHE = old_cache

            with effects_path.open(encoding="utf-8", newline="") as stream:
                effects = list(csv.reader(stream, delimiter="\t"))
            with junctions_path.open(encoding="utf-8", newline="") as stream:
                junctions = list(csv.reader(stream, delimiter="\t"))

        self.assertEqual(len(effects), 83)
        self.assertEqual(len(junctions), 83)
        self.assertTrue(all(row[0] == "percentage_cost_post_mod" for row in junctions[2:]))

    def test_generated_bundles_define_every_custom_bundle_key(self) -> None:
        # create_new_custom_effect_bundle 要求 bundle key 来自 effect_bundles 表；
        # 未定义的 key 拿不到基础记录，运行时会失败（且可能直接崩溃）。
        build_mod = load_build_module()
        metadata = build_mod.load_metadata()

        with tempfile.TemporaryDirectory() as temp_dir:
            old_cache = build_mod.CACHE
            build_mod.CACHE = Path(temp_dir)
            try:
                bundles_path = build_mod.generate_bundles_tsv(metadata)
            finally:
                build_mod.CACHE = old_cache

            with bundles_path.open(encoding="utf-8", newline="") as stream:
                rows = list(csv.reader(stream, delimiter="\t"))

        # 表头 + RPFM 元数据行。
        header, meta = rows[0], rows[1]
        self.assertEqual(
            header,
            [
                "key",
                "localised_description",
                "localised_title",
                "bundle_target",
                "priority",
                "ui_icon",
                "is_global_effect",
                "show_in_3d_space",
                "owner_only",
            ],
        )
        self.assertEqual(
            meta,
            [
                "#effect_bundles_tables;4;db/effect_bundles_tables/wh3_ccc_bundles",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
            ],
        )

        declared = {row[0] for row in rows[2:]}
        expected = {
            faction["bundle_key"]
            for faction in metadata.values()
            if faction.get("bundle_key")
        }
        # 适配器走 Lua bundle 的阵营不应声明 bundle_key，否则会与 Lua 路径冲突。
        self.assertEqual(declared, expected)
        self.assertIn("wh3_ccc_bundle_nagash_capacity_cost", declared)
        self.assertIn("wh3_ccc_bundle_bhashiva_capacity_cost", declared)

        # 定制 bundle 必须带真实目标类型，否则无法应用到阵营。
        # is_global_effect 取 false / priority 与 ui_icon 留空，
        # 均照搬原版同类 bundle wh3_dlc23_bundle_chd_unit_cap_rituals_cost_mods。
        for row in rows[2:]:
            with self.subTest(bundle=row[0]):
                self.assertEqual(row[3], "faction")
                self.assertEqual(row[4], "0")
                self.assertEqual(row[5], "")
                self.assertEqual(row[6], "false")
                self.assertEqual(row[8], "true")

    def test_chaos_dwarfs_metadata_declares_no_custom_bundle(self) -> None:
        # Chaos Dwarfs 复用原版 bundle，不能自建同名或新 bundle 定义。
        build_mod = load_build_module()
        metadata = build_mod.load_metadata()
        self.assertNotIn("chaos_dwarfs", metadata)


if __name__ == "__main__":
    unittest.main()
