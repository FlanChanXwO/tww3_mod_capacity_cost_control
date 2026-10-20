-- 配置读取模块，将各派系的 MCT 选项解析为覆盖开关和递增费率。
-- 从常量与生成元数据读取默认值、费率预设、选项键和模组身份。
-- 配置不可用时返回调用方默认值，无效费率不启用费用覆盖。
local constants = core:load_global_script("capacity_cost_control.config.constants")
local metadata = core:load_global_script("capacity_cost_control.config.metadata")
local defaults = constants.defaults
local config = {}

config.mod_key = metadata.mod_key
config.factions = {}
for _, prefix in ipairs(constants.faction_order) do
    config.factions[prefix] = {
        enabled_option = prefix .. "_enabled",
        mode_option = prefix .. "_mode",
        custom_option = prefix .. "_custom",
        base_cost_option = prefix .. "_base_cost_percent",
    }
end
config.preset_rates = constants.preset_rates

-- 实时从 MCT 读取单个选项值，参考 wolfy_chaos_confederation 模式。
-- MCT 未就绪时返回 fallback。
function config.get_mct_option(option_key, fallback)
    if get_mct then
        local mct = get_mct()
        if mct then
            local mod = mct:get_mod_by_key(config.mod_key)
            if mod then
                local opt = mod:get_option_by_key(option_key)
                if opt then
                    return opt:get_finalized_setting()
                end
            end
        end
    end
    return fallback
end

-- 实时读取某个阵营的完整设置。
function config.read_faction_setting(faction_key)
    local opts = config.factions[faction_key]
    if not opts then
        return { enabled = false, mode = defaults.mode, custom_percent = defaults.custom_percent }
    end
    return {
        enabled = config.get_mct_option(opts.enabled_option, defaults.enabled),
        mode = config.get_mct_option(opts.mode_option, defaults.mode),
        custom_percent = config.get_mct_option(opts.custom_option, defaults.custom_percent),
        base_cost_percent = config.get_mct_option(opts.base_cost_option, defaults.base_cost_percent),
        necromancy_progress_percent = faction_key == "nagash"
            and config.get_mct_option("nagash_necromancy_progress_percent", defaults.necromancy_progress_percent) or nil,
    }
end

function config.read_debug_logging()
    return config.get_mct_option("debug_logging", defaults.debug_logging)
end

function config.default_settings()
    local settings = {debug_logging = defaults.debug_logging}
    for _, prefix in ipairs(constants.faction_order) do
        -- 返回独立设置表，避免调用方修改共享默认值或另一派系的设置。
        settings[prefix] = {
            enabled = defaults.enabled,
            mode = defaults.mode,
            custom_percent = defaults.custom_percent,
            base_cost_percent = defaults.base_cost_percent,
        }
        if prefix == "nagash" then
            settings[prefix].necromancy_progress_percent = defaults.necromancy_progress_percent
        end
    end
    return settings
end

function config.resolve_percent(value, fallback)
    if value == nil then value = fallback end
    value = tonumber(value)
    if value and value >= 0 and value - value == 0 then return value / 100 end
end

function config.resolve_base_multiplier(setting)
    return config.resolve_percent(setting.base_cost_percent, defaults.base_cost_percent)
end

function config.resolve_rate(setting)
    if not setting.enabled then
        return nil
    end
    if config.resolve_base_multiplier(setting) == nil then return nil end
    local preset = config.preset_rates[setting.mode]
    if preset ~= nil then
        return preset
    end
    if setting.mode == "custom" then
        local value = tonumber(setting.custom_percent)
        -- WH3 未提供 math.huge；有限数减去自身为 0，无穷和 NaN 均不满足。
        if value and value > 0 and value - value == 0 then
            return value / 100
        end
    end
    return nil
end

return config
