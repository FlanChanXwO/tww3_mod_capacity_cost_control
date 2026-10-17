-- 帝国紫晶兵适配器，按基础费用和购买次数重算四项容量仪式价格。
-- 首次导入原版可读次数，之后独立记录成功购买并写入存档。
-- AI、无 MCT 和关闭覆盖时维持原版曲线，面板读取交给诊断模块。
local definition = core:load_global_script("capacity_cost_control.shared.generated_data").amethyst
local constants = core:load_global_script("capacity_cost_control.config.constants")
local pricing = core:load_global_script("capacity_cost_control.shared.pricing")
local config = core:load_global_script("capacity_cost_control.config.settings")
local trace = core:load_global_script("capacity_cost_control.utils.logger")
local diagnostics = core:load_global_script("capacity_cost_control.utils.diagnostics")
local purchases = core:load_global_script("capacity_cost_control.store.purchases")
local adapter = {id = "amethyst", faction_key = definition.faction_key, ritual_lookup = {}}
local save_key = "tww3_mod_capacity_cost_control_amethyst_purchases_" .. definition.faction_key

for _, record in ipairs(definition.rituals) do adapter.ritual_lookup[record.key] = record end

local function history(faction)
    return purchases.get_or_import(save_key, definition.rituals, function(record)
        local uses = math.max(0, faction:rituals():get_tracked_cost_uses(record.key) or 0)
        trace.write("[wh3_ccc] amethyst: imported " .. record.key .. " uses=" .. uses)
        return uses
    end)
end

function adapter:handles_ritual(key)
    return self.ritual_lookup[key] ~= nil
end

function adapter:refresh(setting)
    local faction = cm:get_faction(self.faction_key)
    if not faction or faction:is_null_interface() then return end
    local counts = history(faction)
    local rate
    local mct = type(get_mct) == "function" and get_mct()
    if faction:is_human() and mct and mct:get_mod_by_key(config.mod_key) then
        rate = config.resolve_rate(setting or config.read_faction_setting(self.id))
    end
    if faction:has_effect_bundle(definition.bundle_key) then
        cm:remove_effect_bundle(definition.bundle_key, self.faction_key)
    end
    local bundle = cm:create_new_custom_effect_bundle(definition.bundle_key)
    pricing.apply(bundle, definition.rituals, counts, rate)
    bundle:set_duration(0)
    cm:apply_custom_effect_bundle_to_faction(bundle, faction)
end

-- 独立监听成功购买，确保 AI 和未安装 MCT 时也保留原版费用增长。
core:add_listener("tww3_mod_capacity_cost_control_amethyst_purchase", "RitualCompletedEvent",
    function(context)
        if not context:succeeded() then return false end
        local faction = context:performing_faction()
        return faction and not faction:is_null_interface() and faction:name() == definition.faction_key
            and adapter:handles_ritual(context:ritual():ritual_key())
    end,
    function(context)
        history(context:performing_faction())
        local key = context:ritual():ritual_key()
        purchases.record_purchase(save_key, key)
        cm:callback(function() adapter:refresh() end, 0.1)
    end, true)

cm:add_first_tick_callback(function()
    cm:callback(function() adapter:refresh() end, 0.1)
end)

core:add_listener("tww3_mod_capacity_cost_control_amethyst_panel", "PanelOpenedCampaign",
    function(context) return context.string == constants.amethyst.panel_key end,
    function() diagnostics.log_amethyst(adapter, definition) end, true)
core:add_listener("tww3_mod_capacity_cost_control_amethyst_click", "ComponentLClickUp",
    function() return cm:get_local_faction_name() == definition.faction_key end,
    function() diagnostics.log_amethyst(adapter, definition) end, true)

trace.write("[wh3_ccc] amethyst: scripted costs loaded")
return adapter
