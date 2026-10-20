-- 费用数学模块，计算整数目标价格及原版递增抵消比例。
-- 保留 float32 舍入补偿与原版费用上限，供各计价模块复用。
-- 仅计算数值，不访问派系、存档、事件或费用 bundle。
local constants = core:load_global_script("capacity_cost_control.config.constants")
local cost_math = {}

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

-- 两类原版增长都用整数费用计算修正，避免最终取整少收 1 点。
function cost_math.calculate_cost_modifier(vanilla_cost, desired_cost)
    if desired_cost <= 0 then return -100 end
    if vanilla_cost == desired_cost then return 0 end
    local modifier = ((desired_cost / vanilla_cost) - 1) * 100
    -- 补偿百分数转换及应用造成的 float32 边界误差。
    return modifier + (math.abs(modifier) + 100) / constants.precision_divisor
end

-- 用整数费用抵消原版递增，避免先取整的 97 再按 85/97.75 折算成 84。
function cost_math.calculate_post_modifier(vanilla_rate, max_increases, tracked_uses, desired_rate, base_cost, base_multiplier)
    if base_multiplier == 0 then return -100 end
    local uses = math.max(0, tracked_uses or 0)
    local vanilla_uses = math.min(uses, max_increases)
    local vanilla_multiplier = 1 + vanilla_rate * vanilla_uses
    local vanilla_cap = 1 + vanilla_rate * max_increases
    local desired_multiplier = clamp(1 + desired_rate * uses, 0, vanilla_cap)
    local vanilla_cost = math.floor(base_cost * vanilla_multiplier)
    local desired_cost = base_cost * desired_multiplier
    if base_multiplier ~= nil and base_multiplier ~= 1 then desired_cost = desired_cost * base_multiplier end
    return cost_math.calculate_cost_modifier(vanilla_cost, desired_cost)
end

return cost_math
