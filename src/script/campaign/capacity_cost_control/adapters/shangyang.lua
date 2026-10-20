-- 上阳诸军适配器，使用共享计价模块控制兵种与军队容量仪式费用。
-- 导入可核实的购买次数并独立存档，军队历史同时参考已有容量效果。
-- 同步原版军队容量并处理失败仪式写回，确保后续军队和领主仍可解锁。
local definition = core:load_global_script("capacity_cost_control.shared.generated_data").bhashiva
local army = core:load_global_script("capacity_cost_control.config.constants").shangyang
local pricing = core:load_global_script("capacity_cost_control.shared.pricing")
local config = core:load_global_script("capacity_cost_control.config.settings")
local trace = core:load_global_script("capacity_cost_control.utils.logger")
local purchases = core:load_global_script("capacity_cost_control.store.purchases")
local adapter = {id = "bhashiva", faction_key = definition.faction_key, ritual_lookup = {}}
local save_key = "tww3_mod_capacity_cost_control_shangyang_purchases_" .. definition.faction_key

for _, record in ipairs(definition.rituals) do adapter.ritual_lookup[record.key] = record end

local function get_army_bundle(faction)
    if not faction:has_effect_bundle(army.army_bundle) then return end
    local bundles = faction:effect_bundles()
    for i = 0, bundles:num_items() - 1 do
        local bundle = bundles:item_at(i)
        if bundle:key() == army.army_bundle then return bundle end
    end
end

local function get_army_capacity(bundle)
    if not bundle then return 0 end
    local effects = bundle:effects()
    for i = 0, effects:num_items() - 1 do
        local effect = effects:item_at(i)
        if effect:key() == army.army_effect then return effect:value() end
    end
    return 0
end

local function history(faction)
    return purchases.get_or_import(save_key, definition.rituals, function(record)
        local uses = math.max(0, faction:rituals():get_tracked_cost_uses(record.key) or 0)
        -- 军队容量 bundle 可补回旧参考包清零的费用计数，不从兵种容量猜测购买次数。
        if record.key == army.army_ritual then uses = math.max(uses, get_army_capacity(get_army_bundle(faction))) end
        trace.write("[wh3_ccc] bhashiva: imported " .. record.key .. " uses=" .. uses)
        return uses
    end)
end

local function sync_army_capacity(faction, counts)
    local uses = counts[army.army_ritual]
    if uses < 1 then return end
    local bundle = get_army_bundle(faction)
    if not bundle then
        trace.write("[wh3_ccc] bhashiva ERR: purchased army capacity bundle missing")
        return
    end
    if get_army_capacity(bundle) == uses then return end
    -- 原版后续军队上限依赖费用计数；改为独立计数后，按原版方式克隆并更新同一容量效果。
    local copy = bundle:clone_and_create_custom_effect_bundle(cm:model())
    if not copy:set_effect_value_by_key(army.army_effect, uses) then
        trace.write("[wh3_ccc] bhashiva ERR: army capacity effect missing")
        return
    end
    cm:apply_custom_effect_bundle_to_faction(copy, faction)
    trace.write("[wh3_ccc] bhashiva: army capacity=" .. uses)
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
    local base_multiplier = rate ~= nil and config.resolve_base_multiplier(setting or config.read_faction_setting(self.id)) or nil
    pricing.apply(bundle, definition.rituals, counts, rate, base_multiplier)
    bundle:set_duration(0)
    cm:apply_custom_effect_bundle_to_faction(bundle, faction)
    sync_army_capacity(faction, counts)
end

-- AI、无 MCT 和关闭覆盖期间也计数，以便维持原版价格及军队容量。
core:add_listener("tww3_mod_capacity_cost_control_shangyang_purchase", "RitualCompletedEvent",
    function(context)
        -- 原版军队监听器未过滤失败事件，仍须延迟还原其可能写回的旧容量。
        if not context:succeeded() and context:ritual():ritual_key() ~= army.army_ritual then return false end
        local faction = context:performing_faction()
        return faction and not faction:is_null_interface() and faction:name() == definition.faction_key
            and adapter:handles_ritual(context:ritual():ritual_key())
    end,
    function(context)
        history(context:performing_faction())
        local key = context:ritual():ritual_key()
        if context:succeeded() then
            purchases.record_purchase(save_key, key)
        end
        cm:callback(function() adapter:refresh() end, 0.1)
    end, true)

cm:add_first_tick_callback(function()
    cm:callback(function() adapter:refresh() end, 0.1)
end)

trace.write("[wh3_ccc] bhashiva: scripted costs loaded")
return adapter
