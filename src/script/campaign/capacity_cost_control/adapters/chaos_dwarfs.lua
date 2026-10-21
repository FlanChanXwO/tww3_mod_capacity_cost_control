-- 混沌矮人适配器，通过 hellforge hook 替换玩家容量购买的递增率。
-- 设置变更时读取原版容量 bundle，按已购次数重算费用效果。
-- 保留原版容量记录，AI 和关闭覆盖的购买继续调用原版逻辑。
local chaos_dwarfs = { id = "chaos_dwarfs" }
local constants = core:load_global_script("capacity_cost_control.config.constants")
local native = constants.chaos_dwarfs
local config = core:load_global_script("capacity_cost_control.config.settings")

local original_modify = nil
local current_setting = nil

local function trace(msg)
    core:load_global_script("capacity_cost_control.utils.logger").write("[wh3_ccc] chaos_dwarfs: " .. msg)
end

local function rate_percent(setting)
    local config = core:load_global_script("capacity_cost_control.config.settings")
    local rate = config.resolve_rate(setting)
    if rate == nil then return nil end
    return rate * 100
end

local function refresh_free_labels()
    -- 原版零支出不生成 transaction，ContextTextLabel 会留下模板中的 99；等原版重绘后补零。
    cm:callback(function()
        if not current_setting or rate_percent(current_setting) == nil
            or config.resolve_base_multiplier(current_setting) ~= 0 then return end
        local faction = cm:get_faction(cm:get_local_faction_name())
        if not faction or faction:is_null_interface() or not faction:is_human()
            or faction:culture() ~= hellforge.culture_key then return end
        local panel = find_uicomponent(core:get_ui_root(), "hellforge_panel_main")
        if not panel or not panel:Visible() then return end
        local function visit(component, ritual_key)
            local ritual = component:GetContextObject("CcoCampaignRitual")
            ritual_key = ritual and ritual:Call("RitualContext.Key") or ritual_key
            if component:Id() == "template_cost" and ritual_key
                and chaos_dwarfs:handles_ritual(ritual_key) then
                component:SetStateText("0")
            end
            for i = 0, component:ChildCount() - 1 do
                visit(UIComponent(component:Find(i)), ritual_key)
            end
        end
        visit(panel)
    end, 0.1)
end

function chaos_dwarfs:handles_ritual(ritual_key)
    return string.match(ritual_key, native.ritual_pattern) ~= nil
end

function chaos_dwarfs:install_hook()
    if not hellforge then
        trace("install_hook: hellforge nil")
        return
    end
    if original_modify then return end
    original_modify = hellforge.modify_ritual_cap_cost
    core:add_listener("tww3_mod_capacity_cost_control_hellforge_prices", "PanelOpenedCampaign",
        function(context) return context.string == "hellforge_panel_main" end,
        refresh_free_labels, true)

    hellforge.modify_ritual_cap_cost = function(self_inner, ritual_key, faction_interface, bundle_key)
        local desired = current_setting and rate_percent(current_setting) or nil
        if desired == nil or not faction_interface:is_human() then
            -- disabled 或无设定：走 vanilla
            original_modify(self_inner, ritual_key, faction_interface, bundle_key)
            return
        end

        local effect_key = ritual_key .. constants.cost_effect_suffix
        local base_multiplier = config.resolve_base_multiplier(current_setting)
        trace("modify: " .. ritual_key .. " desired=" .. tostring(desired))

        -- 读当前 bundle（与 vanilla get_faction_bundle_by_key 相同方式）
        local current_bundle = nil
        local bundle_list = faction_interface:effect_bundles()
        for i = 0, bundle_list:num_items() - 1 do
            local b = bundle_list:item_at(i)
            if b:key() == bundle_key then
                current_bundle = b
                break
            end
        end

        -- 构建 new values（与 vanilla 逻辑完全平行，只是 increment 换成 desired）
        local effects_to_new_values = {}
        if current_bundle then
            local active_effects = current_bundle:effects()
            for i = 0, active_effects:num_items() - 1 do
                local eff = active_effects:item_at(i)
                local old_val = eff:value()
                local eff_key = eff:key()
                if eff_key == effect_key then
                    effects_to_new_values[eff_key] = base_multiplier == 0 and -100 or old_val + desired * base_multiplier
                else
                    effects_to_new_values[eff_key] = old_val
                end
            end
        end

        -- 创建新 bundle 并设置（与 vanilla 完全平行）
        local bundle = cm:create_new_custom_effect_bundle(bundle_key)
        local new_effects = bundle:effects()
        for i = 0, new_effects:num_items() - 1 do
            local ne = new_effects:item_at(i)
            local ne_key = ne:key()
            if effects_to_new_values[ne_key] then
                bundle:set_effect_value(ne, effects_to_new_values[ne_key])
            elseif effect_key == ne_key then
                local modifier = desired
                if base_multiplier == 0 then modifier = -100
                elseif base_multiplier ~= 1 then modifier = (100 + desired) * base_multiplier - 100 end
                bundle:set_effect_value(ne, modifier)
            else
                bundle:set_effect_value(ne, (base_multiplier - 1) * 100)
            end
        end

        bundle:set_duration(0)
        cm:apply_custom_effect_bundle_to_faction(bundle, faction_interface)
        refresh_free_labels()
        trace("modify: done " .. ritual_key)
    end
    trace("install_hook: patched")
end

function chaos_dwarfs:refresh(setting)
    local previous_rate = current_setting and rate_percent(current_setting)
    current_setting = setting
    self:install_hook()
    if not hellforge then return end
    refresh_free_labels()

    local desired = rate_percent(setting)
    local base_multiplier = desired ~= nil and config.resolve_base_multiplier(setting) or 1
    if desired == nil and previous_rate == nil then return end

    for _, faction_key in ipairs(cm:get_human_factions_of_culture(hellforge.culture_key)) do
        local faction = cm:get_faction(faction_key)
        if faction and not faction:is_null_interface() and faction:is_human() then
            -- 原版容量 bundle 每次购买加 1；价格为 0% 时也保留完整购买记录。
            local cap_bundle = hellforge:get_faction_bundle_by_key(faction, hellforge.unit_cap_modifiers_bundle_string)
            local counts = {}
            if cap_bundle then
                local effects = cap_bundle:effects()
                for i = 0, effects:num_items() - 1 do
                    local effect = effects:item_at(i)
                    counts[effect:key()] = effect:value()
                end
            end

            local bundle = cm:create_new_custom_effect_bundle(hellforge.unit_cost_modifiers_bundle_string)
            local effects = bundle:effects()
            for i = 0, effects:num_items() - 1 do
                local effect = effects:item_at(i)
                local ritual_key = string.gsub(effect:key(), constants.cost_effect_suffix .. "$", "")
                local increment = desired
                if increment == nil then
                    increment = effect:key() == native.warmachine_effect
                        and hellforge.warmachine_ritual_cost_mod_increment or hellforge.unit_ritual_cost_mod_increment
                end
                local modifier = (counts[ritual_key] or 0) * increment
                if base_multiplier == 0 then modifier = -100
                elseif base_multiplier ~= 1 then modifier = (100 + modifier) * base_multiplier - 100 end
                bundle:set_effect_value(effect, modifier)
            end
            bundle:set_duration(0)
            cm:apply_custom_effect_bundle_to_faction(bundle, faction)
        end
    end
end

return chaos_dwarfs
