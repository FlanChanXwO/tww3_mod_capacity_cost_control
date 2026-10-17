-- 紫晶与上阳诸军共用的脚本计价模块，向费用 bundle 添加修正效果。
-- 根据基础费用、购买次数和费率计算目标价，并限制到原版费用上限。
-- 购买记录由 store 管理，整数费用和 float32 补偿交给 cost_math 模块。
local pricing = {}
local constants = core:load_global_script("capacity_cost_control.config.constants")
local scaling = core:load_global_script("capacity_cost_control.utils.cost_math")

function pricing.apply(bundle, records, counts, rate)
    for _, record in ipairs(records) do
        local uses = counts[record.key] or 0
        local applied_rate = rate or record.vanilla_rate
        local multiplier = math.min(1 + applied_rate * uses, 1 + record.vanilla_rate * record.max_increases)
        local desired = record.base_cost * multiplier
        bundle:add_effect(record.effect_key, constants.effect_scope,
            scaling.calculate_cost_modifier(record.base_cost, desired))
    end
end

return pricing
