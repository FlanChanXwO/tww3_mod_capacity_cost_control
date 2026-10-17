-- 战役入口，加载配置与五个派系的容量费用适配器。
-- 监听战役初始化、MCT 设置变更及通用仪式事件。
-- 将刷新请求分发给适配器，具体计价与购买历史由各模块处理。
local config = core:load_global_script("capacity_cost_control.config.settings")
local migration = core:load_global_script("capacity_cost_control.store.migration")
migration.initialize()
local nagash = core:load_global_script("capacity_cost_control.adapters.nagash")
local chaos_dwarfs = core:load_global_script("capacity_cost_control.adapters.chaos_dwarfs")
local bhashiva = core:load_global_script("capacity_cost_control.adapters.shangyang")
local amethyst = core:load_global_script("capacity_cost_control.adapters.amethyst")
local beastmen = core:load_global_script("capacity_cost_control.adapters.beastmen")

local adapters = {
    nagash = nagash,
    chaos_dwarfs = chaos_dwarfs,
    bhashiva = bhashiva,
    amethyst = amethyst,
    beastmen = beastmen,
}

local trace_module = core:load_global_script("capacity_cost_control.utils.logger")
local function trace(message)
    trace_module.write("[wh3_ccc] " .. message)
end

trace("module loaded")

local mct_ready = false

local function refresh_all()
    local mct = type(get_mct) == "function" and get_mct()
    if not mct or not mct:get_mod_by_key(config.mod_key) then return end
    migration.apply_settings()
    mct_ready = true
    trace("refresh_all enter")
    for key, adapter in pairs(adapters) do
        local ok, err = pcall(function()
            local setting = config.read_faction_setting(key)
            trace("refresh: " .. key .. " en=" .. tostring(setting.enabled) .. " mode=" .. tostring(setting.mode))
            adapter:refresh(setting)
        end)
        if not ok then trace("refresh: " .. key .. " ERR: " .. tostring(err)) end
    end
    pcall(function() cm:set_saved_value("tww3_mod_capacity_cost_control_debug_logging", config.read_debug_logging()) end)
    trace("refresh_all done")
end

core:add_listener("tww3_mod_capacity_cost_control_mct_init", "MctInitialized", true,
    function(context)
        trace("MctInitialized")
        pcall(refresh_all)
    end, true)

-- MCT 在单个选项确认时发出此事件；延迟读取完整设置。
core:add_listener("tww3_mod_capacity_cost_control_mct_changed", "MctOptionSettingFinalized",
    function(context)
        return context:mod():get_key() == config.mod_key
    end,
    function()
        cm:callback(refresh_all, 0.1)
    end, true)

core:add_listener("tww3_mod_capacity_cost_control_ritual", "RitualCompletedEvent",
    function(context)
        if not mct_ready then return false end
        if not context:succeeded() then return false end
        local faction = context:performing_faction()
        if not faction or faction:is_null_interface() or not faction:is_human() then return false end
        local rk = context:ritual():ritual_key()
        for key, adapter in pairs(adapters) do
            -- 紫晶和虎人独立监听购买，涵盖 AI 和无 MCT；此处不再重复处理。
            if key ~= "amethyst" and key ~= "bhashiva" and adapter:handles_ritual(rk) then
                local f = context:performing_faction()
                if adapter.on_ritual_completed and f then
                    adapter:on_ritual_completed(rk, f)
                end
                return true
            end
        end
        return false
    end,
    function(context)
        local rk = context:ritual():ritual_key()
        -- 原版计时器的 0 秒回调同步执行；正延迟确保读到原版监听器更新后的费用。
        -- CHD 由 hooked modify_ritual_cap_cost 处理，不需要刷新
        if not chaos_dwarfs:handles_ritual(rk) then
            cm:callback(function() pcall(refresh_all) end, 0.1)
        end
    end, true)

cm:add_first_tick_callback(function()
    trace("first_tick")
    -- 延迟到下一 tick，确保 hellforge 已被 required.lua 加载
    cm:callback(function()
        trace("delayed refresh")
        pcall(refresh_all)
    end, 0.1)
end)

trace("listeners registered")
