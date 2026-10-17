-- 费用精度回归，在每次运算后量化为 float32，重放游戏日志中的数值精度。
-- 执行真实 cost_math 公式并模拟基价计价，检查递增与折扣后的整数结果。
-- 使用宿主 Lua 的 string.pack/unpack 模拟精度，不依赖游戏引擎对象。
local function unwrap(value) return type(value) == "table" and value.value or value end
local number = {}
local function f32(value)
    return setmetatable({value = string.unpack("f", string.pack("f", unwrap(value)))}, number)
end
for name, operation in pairs({
    __add = function(a, b) return a + b end,
    __sub = function(a, b) return a - b end,
    __mul = function(a, b) return a * b end,
    __div = function(a, b) return a / b end,
}) do
    number[name] = function(a, b) return f32(operation(unwrap(a), unwrap(b))) end
end
number.__lt = function(a, b) return unwrap(a) < unwrap(b) end
number.__le = function(a, b) return unwrap(a) <= unwrap(b) end
number.__eq = function(a, b) return unwrap(a) == unwrap(b) end
local env = setmetatable({math = {
    max = function(a, b) return f32(math.max(unwrap(a), unwrap(b))) end,
    min = function(a, b) return f32(math.min(unwrap(a), unwrap(b))) end,
    floor = function(a) return f32(math.floor(unwrap(a))) end,
    abs = function(a) return f32(math.abs(unwrap(a))) end,
}}, {__index = _G})
env.core = {load_global_script = function(_, name)
    return assert(loadfile("src/script/campaign/" .. string.gsub(name, "%.", "/") .. ".lua", "t", env))()
end}
local scaling = assert(loadfile("src/script/campaign/capacity_cost_control/utils/cost_math.lua", "t", env))()
local observed = ((1 / (1 + f32(0.15) * 3)) - 1) * 100
assert(math.abs(unwrap(observed) - (-31.03448677063)) < 1e-10, "float32 model must match the game trace")
local function price(base, rate, cap, uses, desired, discount)
    local modifier = scaling.calculate_post_modifier(f32(rate), f32(cap), f32(uses), f32(desired), f32(base))
    local vanilla = math.floor(unwrap(f32(base) * (1 + f32(rate) * f32(math.min(uses, cap)))))
    return math.floor(unwrap(f32(vanilla) * (1 + modifier / 100) * f32(discount or 1)))
end

local function beastmen_price(base, uses, desired, native, discount, cap)
    -- 原版效果与独立 bundle 中的同键相反值先相加，消除大数除法。
    local combined = f32(native) + f32(-native)
    assert(unwrap(combined) == 0, "native compound modifier must cancel exactly")
    local multiplier = 1 + f32(desired) * f32(uses)
    if cap and multiplier > cap then multiplier = f32(cap) end
    local modifier = scaling.calculate_cost_modifier(f32(base), f32(base) * multiplier)
    return math.floor(unwrap(f32(base) * (1 + combined / 100) * (1 + modifier / 100) * f32(discount)))
end

for uses = 0, 3 do
    local actual = price(85, 0.15, 2147483647, uses, 0)
    assert(actual == 85, "polearm price after " .. uses .. " purchases: expected 85, got " .. actual)
end
local data = dofile("build/generated/generated_data.lua")
for faction, definition in pairs(data) do
    for _, ritual in ipairs(definition.rituals) do
        for _, percent in ipairs({0, 5, 10, 7.5, 100}) do
            for uses = 0, 200 do
                for _, discount in ipairs({1, 0.9, 0.75}) do
                    local desired = 100 + percent * uses
                    if definition.cost_model ~= "beastmen" then
                        desired = math.min(desired, 100 + ritual.vanilla_rate * 100 * ritual.max_increases)
                    end
                    local expected = math.floor(ritual.base_cost * desired / 100 * discount)
                    local actual
                    if definition.cost_model == "beastmen" then
                        local native = ritual.vanilla_rate * 1000 * (1.1 ^ uses - 1)
                        actual = beastmen_price(ritual.base_cost, uses, percent / 100, native, discount)
                    elseif definition.cost_model == "amethyst" or definition.cost_model == "bhashiva" then
                        -- 紫晶和虎人 DB 不再增长，直接从基础费用应用所选线性费率。
                        actual = beastmen_price(ritual.base_cost, uses, percent / 100, 0, discount,
                            1 + ritual.vanilla_rate * ritual.max_increases)
                    else
                        actual = price(ritual.base_cost, ritual.vanilla_rate,
                            ritual.max_increases, uses, percent / 100, discount)
                    end
                    assert(actual == expected, faction .. " " .. ritual.key .. " uses=" .. uses
                        .. " rate=" .. percent .. " discount=" .. discount
                        .. ": expected " .. expected .. ", got " .. actual)
                end
            end
        end
    end
end
print("PASS ritual_prices")
