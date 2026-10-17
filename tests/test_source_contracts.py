from __future__ import annotations

import re
import xml.etree.ElementTree as ET
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class SourceContractTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_mct_link_templates_use_native_click_commands(self) -> None:
        for kind in ("icon", "action"):
            root = ET.parse(ROOT / f"src/ui/tww3_mod_capacity_cost_control/{kind}_link.twui.xml").getroot()
            callbacks = root.findall(".//callback_with_context[@callback_id='ContextCommandLeftClick']")
            self.assertEqual(len(callbacks), 1)
            self.assertEqual(callbacks[0].get("context_object_id"), "CcoScriptObject")
            self.assertEqual(callbacks[0].get("context_function_id"), "OpenOverlayToUrl(StringValue, true)")

    def test_mct_settings_has_defensive_guard(self) -> None:
        # MCT settings 文件必须以防御性检查开头，MCT 未加载时静默退出。
        text = self.read("src/script/mct/settings/tww3_mod_capacity_cost_control_mct.lua")
        self.assertIn("if not get_mct then return end", text)
        self.assertLess(text.index("get_mct"), text.index("register_mod"))

    def test_mct_exposes_all_factions_and_modes(self) -> None:
        text = self.read("src/script/mct/settings/tww3_mod_capacity_cost_control_mct.lua")

        self.assertIn("ipairs(constants.faction_order)", text)
        self.assertIn("ipairs(constants.mode_order)", text)
        self.assertIn('prefix .. "_enabled"', text)
        self.assertIn('prefix .. "_mode"', text)
        self.assertIn('prefix .. "_custom"', text)

        self.assertIn('"text_input"', text)
        self.assertIn("value <= 0", text)

    def test_runtime_listens_for_ritual_and_mct_events(self) -> None:
        text = self.read("src/script/campaign/mod/tww3_mod_capacity_cost_control_main.lua")

        self.assertIn('"MctInitialized"', text)
        self.assertIn('"RitualCompletedEvent"', text)
        # 不再依赖 MctFinalized——改为实时读取 MCT 设置。
        self.assertNotIn('"MctFinalized"', text)

    def test_runtime_uses_new_mod_identity_without_legacy_fallback(self) -> None:
        config = self.read("src/script/campaign/capacity_cost_control/config/settings.lua")
        mct = self.read("src/script/mct/settings/tww3_mod_capacity_cost_control_mct.lua")
        self.assertIn('core:load_global_script("capacity_cost_control.config.metadata")', config)
        self.assertIn('config.mod_key = metadata.mod_key', config)
        self.assertNotIn("legacy_mod_key", config)
        self.assertIn('loadfile("script/campaign/capacity_cost_control/config/metadata.lua")', mct)
        self.assertIn('register_mod(metadata.mod_key)', mct)

    def test_ritual_adapters_preserve_vanilla_use_tracking(self) -> None:
        text = self.read("src/script/campaign/capacity_cost_control/adapters/nagash.lua")

        self.assertIn("get_tracked_cost_uses", text)
        self.assertIn("calculate_post_modifier", text)
        self.assertNotIn("percentage_cost_increase_per_use =", text)

    def test_handles_ritual_avoids_four_arg_string_find(self) -> None:
        # WH3 的 Lua 绑定不支持 string.find 的第 4 个 plain 参数：
        # CA 自己的 lib_core.lua 把该写法注释为 "uncomment if we move to a
        # later version of lua"。传 true 会触发
        # "expected data type 'string' but was supplied type 'boolean'"
        # 并判定 Lua 栈已损坏，引擎随即 __fastfail（0xc0000409）崩溃。
        text = self.read("src/script/campaign/capacity_cost_control/adapters/chaos_dwarfs.lua")
        self.assertIsNone(
            re.search(r"string\.find\([^)\n]*,\s*true\s*\)", text),
            "string.find 的 plain 参数在 WH3 Lua 上不可用",
        )
    def test_chaos_dwarfs_monkey_patches_hellforge(self) -> None:
        text = self.read("src/script/campaign/capacity_cost_control/adapters/chaos_dwarfs.lua")
        text = self.read("src/script/campaign/capacity_cost_control/adapters/chaos_dwarfs.lua")
        self.assertIn("hellforge.modify_ritual_cap_cost", text)
        self.assertIn("original_modify", text)

if __name__ == "__main__":
    unittest.main()


