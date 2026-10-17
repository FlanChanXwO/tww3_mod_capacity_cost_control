-- 固定运行时常量，集中维护引擎标识、精度参数和配置默认值。
-- 同时提供派系、模式及 MCT 分组顺序，供运行时与设置页面读取。
-- 调用方按只读约定使用；可扩展的仪式列表与基础费用由 data/rituals.json 维护。
return {
    effect_scope = "faction_to_faction_own_unseen",
    cost_effect_suffix = "_cost_mod",
    -- 四倍 float32 相对精度；费用修正和旧历史匹配使用同一误差尺度。
    precision_divisor = 2 ^ 22,

    faction_order = {"nagash", "chaos_dwarfs", "bhashiva", "beastmen", "amethyst"},
    other_sections = {"debug", "links"},
    mode_order = {"no_scaling", "light", "medium", "custom"},
    preset_rates = {
        no_scaling = 0,
        light = 0.05,
        medium = 0.10,
    },
    defaults = {
        enabled = true,
        mode = "no_scaling",
        custom_percent = 1,
        debug_logging = false,
    },
    legacy = {
        mod_key = "wh3_capacity_cost_control",
        purchase_prefix = "wh3_ccc_",
        purchase_factions = {amethyst = "amethyst", shangyang = "bhashiva", beastmen = "beastmen"},
    },

    chaos_dwarfs = {
        ritual_prefix = "wh3_dlc23_chd_ritual_unit_cap_",
        warmachine_effect = "wh3_dlc23_chd_ritual_unit_cap_warmachines_cost_mod",
        -- 原版增量和 bundle 继续读取 hellforge 的当前字段，避免复制后与原版脱节。
    },
    shangyang = {
        army_ritual = "wh3_cp1_ritual_cth_aosy_army_capacity",
        army_bundle = "wh3_cp1_ritual_cth_army_capacity_bundle",
        army_effect = "wh2_dlc09_effect_increase_army_capacity",
    },
    amethyst = {
        panel_key = "dlc25_don_main",
    },
    beastmen = {
        unit_bundle = "wh2_dlc17_bundle_bst_unit_cap_ritual_cost_mods",
        hero_bundle = "wh2_dlc17_bundle_bst_hero_cap_ritual_cost_mods",
        -- 原版递推 v[n+1] = 1.1*v[n] + I；闭式解中的因子为 1/(1.1-1)。
        compound_multiplier = 1.1,
        compound_base_factor = 10,
    },
}
