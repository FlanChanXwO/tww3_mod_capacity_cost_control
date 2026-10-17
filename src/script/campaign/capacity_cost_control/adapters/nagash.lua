-- 纳迦什适配器，按原版购买次数修正容量仪式费用。
-- 读取原版递增记录，使用费用数学模块计算目标价格与补偿。
-- 保留原版 DB 与历史；仅为启用覆盖的玩家派系应用修正。
local definition = core:load_global_script("capacity_cost_control.shared.generated_data").nagash
local constants = core:load_global_script("capacity_cost_control.config.constants")
local cost_math = core:load_global_script("capacity_cost_control.utils.cost_math")

local adapter = {
    id = definition.id,
    faction_key = definition.faction_key,
    bundle_key = definition.bundle_key,
    rituals = definition.rituals,
    ritual_lookup = {},
}

for _, ritual in ipairs(adapter.rituals) do
    adapter.ritual_lookup[ritual.key] = ritual
end

function adapter:handles_ritual(ritual_key)
    return self.ritual_lookup[ritual_key] ~= nil
end

function adapter:refresh(setting)
    local trace_module = core:load_global_script("capacity_cost_control.utils.logger")
    local function trace(message)
        trace_module.write("[wh3_ccc] " .. self.id .. ": " .. message)
    end

    trace("refresh enter")
    local faction = cm:get_faction(self.faction_key)
    if not faction or faction:is_null_interface() then
        trace("refresh: faction missing/null")
        return
    end

    trace("refresh: has_effect_bundle?")
    if faction:has_effect_bundle(self.bundle_key) then
        trace("refresh: removing existing bundle")
        cm:remove_effect_bundle(self.bundle_key, self.faction_key)
    end

    if not faction:is_human() or not setting.enabled then
        trace("refresh: disabled, stop")
        return
    end

    local config = core:load_global_script("capacity_cost_control.config.settings")
    local desired_rate = config.resolve_rate(setting)
    if desired_rate == nil then
        trace("refresh: rate nil, stop")
        return
    end

    trace("refresh: create_new_custom_effect_bundle " .. tostring(self.bundle_key))
    local bundle = cm:create_new_custom_effect_bundle(self.bundle_key)
    trace("refresh: bundle created")
    local rituals = faction:rituals()
    trace("refresh: rituals() ok, count=" .. #self.rituals)

    for index, ritual in ipairs(self.rituals) do
        trace("refresh: ritual " .. index .. " " .. ritual.key)
        local uses = rituals:get_tracked_cost_uses(ritual.key)
        local modifier = cost_math.calculate_post_modifier(
            ritual.vanilla_rate,
            ritual.max_increases,
            uses,
            desired_rate,
            ritual.base_cost
        )

        trace("refresh: modifier=" .. tostring(modifier) .. " uses=" .. tostring(uses) .. " rate=" .. tostring(desired_rate))
        bundle:add_effect(
            ritual.effect_key,
            constants.effect_scope,
            modifier
        )
    end

    trace("refresh: add_effect loop done")
    bundle:set_duration(0)
    trace("refresh: applying bundle")
    cm:apply_custom_effect_bundle_to_faction(bundle, faction)
    trace("refresh: applied")
end

return adapter
