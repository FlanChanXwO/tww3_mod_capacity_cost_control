from __future__ import annotations

import os
import shutil
import subprocess
import unittest
from pathlib import Path

from test_build_outputs import load_build_module

ROOT = Path(__file__).resolve().parents[1]
LUA = os.environ.get("LUA") or shutil.which("lua")


@unittest.skipUnless(LUA, "Set LUA to a Lua interpreter to run campaign regressions")
class CampaignRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        build_mod = load_build_module()
        build_mod.generate_lua(build_mod.load_metadata())
        build_mod.generate_project_metadata()
        build_mod.generate_i18_lua()

    def run_scenario(self, scenario: str) -> None:
        result = subprocess.run(
            [LUA, "tests/lua/campaign_runtime.lua", scenario],
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_base_cost_multipliers(self) -> None:
        for faction in ("chaos_dwarfs", "nagash", "amethyst", "bhashiva"):
            with self.subTest(faction=faction):
                self.run_scenario("base_cost_" + faction)
        self.run_beastmen_scenario("base_cost_percent")
        self.run_scenario("percent_settings")

    def test_chaos_dwarfs_free_cost_labels(self) -> None:
        self.run_scenario("chaos_dwarfs_free_cost_labels")

    def test_nagash_progress_uses_vanilla_cost_independently(self) -> None:
        result = subprocess.run(
            [LUA, "tests/lua/nagash_sigils.lua"], cwd=ROOT,
            capture_output=True, text=True, encoding="utf-8",
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_real_mct_pages_render_without_global_campaign_interfaces(self) -> None:
        result = subprocess.run(
            [LUA, "tests/lua/mct_ui.lua"], cwd=ROOT,
            capture_output=True, text=True, encoding="utf-8",
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_campaign_environment_applies_no_scaling(self) -> None:
        self.run_scenario("campaign_environment")

    def test_mct_custom_input_validation_without_math_huge(self) -> None:
        self.run_scenario("mct_custom_input_validation")

    def test_logger_uses_project_mod_id(self) -> None:
        self.run_scenario("logger_uses_mod_id")

    def test_mct_native_links_bind_destinations_without_duplicate_wrapping(self) -> None:
        self.run_scenario("mct_external_links")

    def test_custom_100_applies_without_math_huge(self) -> None:
        self.run_scenario("custom_100_without_math_huge")

    def test_mct_change_updates_purchase_rate(self) -> None:
        self.run_scenario("mct_change")

    def test_existing_campaign_is_repriced_without_losing_capacity(self) -> None:
        self.run_scenario("existing_campaign")

    def test_without_mct_preserves_vanilla(self) -> None:
        self.run_scenario("without_mct")

    def test_initial_disabled_state_preserves_vanilla(self) -> None:
        self.run_scenario("initial_disabled")

    def test_multiple_purchases_preserve_other_categories(self) -> None:
        self.run_scenario("multiple_purchases")

    def test_ritual_adapters_share_campaign_environment(self) -> None:
        self.run_scenario("ritual_adapters")

    def test_ritual_purchases_and_setting_changes_preserve_history(self) -> None:
        self.run_scenario("ritual_purchase_history")

    def test_purchase_store_import_reload_and_independent_counts(self) -> None:
        self.run_scenario("purchase_store")

    def test_legacy_settings_and_purchase_history_migrate_once(self) -> None:
        self.run_scenario("legacy_migration")

    def test_ai_preserves_vanilla_prices(self) -> None:
        self.run_scenario("ai_preserved")


    def test_bhashiva_history_and_army_capacity_native_first(self) -> None:
        self.run_scenario("bhashiva_history_native_first")

    def test_bhashiva_history_and_army_capacity_mod_first(self) -> None:
        self.run_scenario("bhashiva_history_mod_first")

    def test_bhashiva_new_campaign_army_capacity(self) -> None:
        self.run_scenario("bhashiva_new_campaign")

    def test_bhashiva_without_mct_preserves_vanilla(self) -> None:
        self.run_scenario("bhashiva_without_mct")

    def test_bhashiva_ai_preserves_vanilla(self) -> None:
        self.run_scenario("bhashiva_ai")

    def test_bhashiva_initial_disabled_preserves_vanilla(self) -> None:
        self.run_scenario("bhashiva_initial_disabled")

    def test_amethyst_history_rates_reload_and_disable(self) -> None:
        self.run_scenario("amethyst_history")

    def test_amethyst_without_mct_preserves_vanilla_prices(self) -> None:
        self.run_scenario("amethyst_without_mct")

    def test_amethyst_ai_preserves_vanilla_prices(self) -> None:
        self.run_scenario("amethyst_ai")

    def test_amethyst_initial_disabled_preserves_vanilla_prices(self) -> None:
        self.run_scenario("amethyst_initial_disabled")

    def test_amethyst_engine_logging_is_read_only(self) -> None:
        self.run_scenario("amethyst_engine_logging")

    def run_beastmen_scenario(self, scenario: str) -> None:
        result = subprocess.run(
            [LUA, "tests/lua/beastmen_runtime.lua", scenario], cwd=ROOT,
            capture_output=True, text=True, encoding="utf-8",
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_beastmen_existing_history_and_reload(self) -> None:
        self.run_beastmen_scenario("existing_campaign")

    def test_beastmen_ungor_purchase_timing(self) -> None:
        self.run_beastmen_scenario("ungor_purchase_timing")

    def test_beastmen_heroes_and_separate_human_factions(self) -> None:
        self.run_beastmen_scenario("heroes_and_players")

    def test_beastmen_failed_and_excluded_rituals_do_not_count(self) -> None:
        self.run_beastmen_scenario("failed_and_excluded")

    def test_beastmen_legacy_history_and_without_mct(self) -> None:
        self.run_beastmen_scenario("legacy_and_without_mct")

    def test_beastmen_large_compound_history(self) -> None:
        self.run_beastmen_scenario("deep_history")

    def test_beastmen_initial_disabled_preserves_history(self) -> None:
        self.run_beastmen_scenario("initial_disabled")

    def test_ritual_prices_preserve_integer_costs(self) -> None:
        result = subprocess.run(
            [LUA, "tests/lua/ritual_prices.lua"], cwd=ROOT,
            capture_output=True, text=True, encoding="utf-8",
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
