-- 野兽人适配器，保留原版复利 bundle 并单独修正玩家容量购买费用。
-- 从可核实的原版涨价恢复历史，随后按派系和仪式保存成功购买次数。
-- 仅处理元数据中的兵种与英雄容量，关闭覆盖时移除本模组的费用修正。
local definition = core:load_global_script("capacity_cost_control.shared.generated_data").beastmen
local constants = core:load_global_script("capacity_cost_control.config.constants")
local native = constants.beastmen
local scaling = core:load_global_script("capacity_cost_control.utils.cost_math")
local config = core:load_global_script("capacity_cost_control.config.settings")
local purchases = core:load_global_script("capacity_cost_control.store.purchases")
local beastmen = {id = "beastmen"}
local current_setting = nil
local rituals = {}
for _, ritual in ipairs(definition.rituals) do rituals[ritual.key] = ritual end

local function save_key(faction)
    return "tww3_mod_capacity_cost_control_beastmen_purchases_" .. faction:name()
end

local function native_modifiers(faction)
    local values = {}
    local bundles = faction:effect_bundles()
    for i = 0, bundles:num_items() - 1 do
        local bundle = bundles:item_at(i)
        if bundle:key() == native.unit_bundle or bundle:key() == native.hero_bundle then
            local effects = bundle:effects()
            for j = 0, effects:num_items() - 1 do
                local effect = effects:item_at(j)
                values[effect:key()] = effect:value()
            end
        end
    end
    return values
end

local function import_count(value, increment)
    if value <= 0 then return 0 end
    -- 仅接受能匹配原版复利曲线的历史。
    local count = math.floor(math.log(1 + value / (native.compound_base_factor * increment))
        / math.log(native.compound_multiplier) + 0.5)
    local expected = native.compound_base_factor * increment * (native.compound_multiplier ^ count - 1)
    -- 容许逐次 float32 运算的累计舍入，仍远小于相邻两次购买的差距。
    if math.abs(expected - value) <= math.max(1, math.abs(value)) * math.max(1, count) / constants.precision_divisor then
        return count
    end
    -- shortcut: 其它 mod 改写的历史从零计数；有可靠购买记录来源时再补迁移。
    return 0
end

local function history(faction, modifiers)
    return purchases.get_or_import(save_key(faction), definition.rituals, function(ritual)
        return import_count(modifiers[ritual.key .. constants.cost_effect_suffix] or 0, ritual.vanilla_rate * 100)
    end)
end

function beastmen:handles_ritual(ritual_key)
    return rituals[ritual_key] ~= nil
end

local function refresh_free_labels()
    cm:callback(function()
        if not current_setting or config.resolve_rate(current_setting) == nil
            or config.resolve_base_multiplier(current_setting) ~= 0 then return end
        local faction = cm:get_faction(cm:get_local_faction_name())
        if not faction or faction:is_null_interface() or not faction:is_human()
            or faction:culture() ~= definition.culture_key then return end
        local panel = find_uicomponent(core:get_ui_root(), "beastmen_panel")
        if not panel or not panel:Visible() then return end
        local function visit(component, ritual_key)
            local ritual = component:GetContextObject("CcoCampaignRitual")
            ritual_key = ritual and ritual:Call("RitualContext.Key") or ritual_key
            -- 零支出没有金额可供原版表达式读取，价格会残留模板的 99。
            if component:Id() == "dy_dread" and beastmen:handles_ritual(ritual_key) then
                component:SetStateText("0")
            end
            for i = 0, component:ChildCount() - 1 do
                visit(UIComponent(component:Find(i)), ritual_key)
            end
        end
        visit(panel)
    end, 0.1)
end

core:add_listener("tww3_mod_capacity_cost_control_beastmen_prices", "PanelOpenedCampaign",
    function(context) return context.string == "beastmen_panel" end, refresh_free_labels, true)
core:add_listener("tww3_mod_capacity_cost_control_beastmen_price_tabs", "ComponentLClickUp",
    function(context)
        return current_setting and config.resolve_rate(current_setting) ~= nil
            and config.resolve_base_multiplier(current_setting) == 0
            and uicomponent_descended_from(UIComponent(context.component), "beastmen_panel")
    end, refresh_free_labels, true)

function beastmen:on_ritual_completed(ritual_key, faction)
    purchases.record_purchase(save_key(faction), ritual_key)
end

function beastmen:refresh(setting)
    current_setting = setting
    refresh_free_labels()
    local rate = config.resolve_rate(setting)
    for _, faction_key in ipairs(cm:get_human_factions_of_culture(definition.culture_key)) do
        local faction = cm:get_faction(faction_key)
        if faction and not faction:is_null_interface() and faction:is_human() then
            local modifiers = native_modifiers(faction)
            local counts = history(faction, modifiers)
            if faction:has_effect_bundle(definition.bundle_key) then
                cm:remove_effect_bundle(definition.bundle_key, faction_key)
            end
            if rate ~= nil then
                local bundle = cm:create_new_custom_effect_bundle(definition.bundle_key)
                for _, ritual in ipairs(definition.rituals) do
                    local native_effect = ritual.key .. constants.cost_effect_suffix
                    -- 同一原版效果用相反值抵消，避免巨大复利费用乘接近零的比例丢失精度。
                    -- Mixu 血蹄没有原版涨价效果，只添加实际存在的抵消项。
                    if modifiers[native_effect] ~= nil then
                        bundle:add_effect(native_effect, constants.effect_scope, -modifiers[native_effect])
                    end
                    local base_multiplier = config.resolve_base_multiplier(setting)
                    local desired = 0
                    if base_multiplier ~= 0 then
                        desired = ritual.base_cost * (1 + rate * counts[ritual.key])
                        if base_multiplier ~= 1 then desired = desired * base_multiplier end
                    end
                    bundle:add_effect(ritual.effect_key, constants.effect_scope,
                        scaling.calculate_cost_modifier(ritual.base_cost, desired))
                end
                bundle:set_duration(0)
                cm:apply_custom_effect_bundle_to_faction(bundle, faction)
            end
        end
    end
end

return beastmen
