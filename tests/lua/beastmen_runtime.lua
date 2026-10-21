-- 野兽人运行时回归，在模拟引擎对象中执行真实入口和适配器源码。
-- 使用本机原版 Ruination 函数重放复利涨价，验证旧档、连续购买和费用恢复。
-- 只模拟引擎边界；断言购买计数与玩家隔离，不替代游戏内实际扣款验证。
local function load_in_env(path, env)
    return assert(loadfile(path, "t", env))()
end

local function list(items)
    return {num_items = function() return #items end,
        item_at = function(_, i) return items[i + 1] end}
end

local function bundle(key, values)
    local effects = {}
    local result = {key = function() return key end, set_duration = function() end}
    function result:add_effect(key, scope, value)
        assert(key ~= "mixu_increase_hero_capacity_bst_gorehoof_cost_mod",
            "Mixu has no native cost effect to add or cancel")
        local effect = {_value = value, key = function() return key end}
        function effect:value() return self._value end
        effects[#effects + 1] = effect
    end
    function result:effects() return list(effects) end
    function result:set_effect_value(effect, value) effect._value = value end
    for key, value in pairs(values or {}) do result:add_effect(key, "", value) end
    return result
end

local data = dofile("build/generated/generated_data.lua")
local definition = assert(data.beastmen, "Beastmen metadata must be generated")
local by_key = {}
for _, ritual in ipairs(definition.rituals) do by_key[ritual.key] = ritual end
local unit = assert(by_key.wh2_dlc17_bst_ritual_unit_cap_bestigor_herd)
local other = assert(by_key.wh2_dlc17_bst_ritual_unit_cap_centigors_all)
local hero_keys = {"bray_shaman", "gorebull", "wargor"}
local unit_bundle = "wh2_dlc17_bundle_bst_unit_cap_ritual_cost_mods"
local hero_bundle = "wh2_dlc17_bundle_bst_hero_cap_ritual_cost_mods"
local saved, factions, callbacks, listeners, loaded = {}, {}, {}, {}, {}
saved.tww3_mod_capacity_cost_control_debug_logging = false
local options = {beastmen_enabled = true, beastmen_mode = "no_scaling", beastmen_custom = "1"}
local function add_faction(key, human)
    local f = {_bundles = {}, _capacity = {}, _human = human}
    function f:name() return key end
    function f:culture() return "wh_dlc03_bst_beastmen" end
    function f:is_human() return self._human end
    function f:is_null_interface() return false end
    function f:effect_bundles()
        local items = {}
        for _, item in pairs(self._bundles) do items[#items + 1] = item end
        return list(items)
    end
    function f:has_effect_bundle(key) return self._bundles[key] ~= nil end
    factions[key] = f
    return f
end
local player = add_faction("wh_dlc03_bst_beastmen", true)
local second = add_faction("wh2_dlc17_bst_taurox", true)
local ai = add_faction("wh_dlc05_bst_morghur_herd", false)
local cm = {
    get_local_faction_name = function() return player:name() end,
    get_faction = function(_, key) return factions[key] end,
    get_saved_value = function(_, key) return saved[key] end,
    set_saved_value = function(_, key, value) saved[key] = value end,
    add_loading_game_callback = function() end,
    get_human_factions_of_culture = function(_, culture)
        local result = {}
        for key, f in pairs(factions) do
            if f:is_human() and f:culture() == culture then result[#result + 1] = key end
        end
        return result
    end,
    create_new_custom_effect_bundle = function(_, key)
        local values = {}
        for _, ritual in ipairs(definition.rituals) do
            local is_hero = string.find(ritual.key, "ritual_hero_capacity_", 1)
            if ritual.vanilla_rate > 0 and key == (is_hero and hero_bundle or unit_bundle) then
                values[ritual.key .. "_cost_mod"] = 0
            end
        end
        return bundle(key, values)
    end,
    apply_custom_effect_bundle_to_faction = function(_, b, f) f._bundles[b:key()] = b end,
    remove_effect_bundle = function(_, key, faction_key) factions[faction_key]._bundles[key] = nil end,
    callback = function(_, fn, interval)
        -- 原版 campaign timer：非正延迟同步执行，只有正延迟才排队。
        if interval <= 0 then fn() else callbacks[#callbacks + 1] = fn end
    end,
    add_first_tick_callback = function(_, fn) callbacks[#callbacks + 1] = fn end,
}
local mct_mod = {get_key = function() return "tww3_mod_capacity_cost_control" end}
function mct_mod:get_option_by_key(key)
    if options[key] == nil then return nil end
    return {get_finalized_setting = function() return options[key] end}
end
local core = {}
local env = setmetatable({cm = cm, core = core}, {__index = _G})
function core:get_ui_root() return nil end
env.find_uicomponent=function() return nil end
env.get_mct = function() return {get_mod_by_key = function() return mct_mod end} end
function core:get_env() return env end
function core:load_global_script(name)
    if not loaded[name] then
        local path = "src/script/campaign/" .. string.gsub(name, "%.", "/") .. ".lua"
        if name == "capacity_cost_control.shared.generated_data" or name == "capacity_cost_control.config.metadata" then
            path = "build/generated/" .. string.match(name, "[^.]+$") .. ".lua"
        end
        loaded[name] = load_in_env(path, env)
    end
    return loaded[name]
end
function core:add_listener(name, event, condition, callback)
    listeners[#listeners + 1] = {event = event, condition = condition, callback = callback}
end
local function fire(event, context)
    for _, listener in ipairs(listeners) do
        if listener.event == event and (listener.condition == true or listener.condition(context)) then
            listener.callback(context)
        end
    end
end
local function flush()
    while #callbacks > 0 do
        local pending = callbacks; callbacks = {}
        for _, fn in ipairs(pending) do fn() end
    end
end
local function boot()
    loaded, listeners, callbacks = {}, {}, {}
    load_in_env("src/script/campaign/mod/tww3_mod_capacity_cost_control_main.lua", env)
    if env.get_mct then fire("MctInitialized", {}) end
    flush()
end
local function value(f, key, effect_key)
    local b = f._bundles[key]
    if b then
        local effects = b:effects()
        for i = 0, effects:num_items() - 1 do
            local effect = effects:item_at(i)
            if effect:key() == effect_key then return effect:value() end
        end
    end
    return 0
end
local function native_bundle_key(ritual)
    return string.find(ritual.key, "ritual_hero_capacity_", 1) and hero_bundle or unit_bundle
end
local function seed(f, ritual, modifier)
    local key = native_bundle_key(ritual)
    f._bundles[key] = cm:create_new_custom_effect_bundle(key)
    local effects = f._bundles[key]:effects()
    for i = 0, effects:num_items() - 1 do
        local effect = effects:item_at(i)
        if effect:key() == ritual.key .. "_cost_mod" then effect._value = modifier end
    end
end
local function f32(value) return string.unpack("f", string.pack("f", value)) end
local function cost(f, ritual)
    local native = f32(value(f, native_bundle_key(ritual), ritual.key .. "_cost_mod")
        + value(f, definition.bundle_key, ritual.key .. "_cost_mod"))
    local vanilla = math.floor(f32(ritual.base_cost * f32(1 + f32(native / 100))))
    return math.floor(f32(vanilla * f32(1 + f32(value(f, definition.bundle_key, ritual.effect_key) / 100))))
end
local function change(mode, enabled, custom)
    options.beastmen_mode = mode
    options.beastmen_enabled = enabled ~= false
    options.beastmen_custom = custom or "1"
    fire("MctOptionSettingFinalized", {mod = function() return mct_mod end}); flush()
end
local function equal(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. expected .. ", got " .. actual)
end

-- 以下两函数从 2026-10-16 本机原版脚本提取，保留计算和模板行为。
env.Ruination = {cost_mod_effect_suffix = "_cost_mod"}
load_in_env("tests/lua/fixtures/beastmen_vanilla.lua", env)
local function purchase(f, ritual, success)
    local context = {succeeded = function() return success ~= false end,
        performing_faction = function() return f end,
        ritual = function() return {ritual_key = function() return ritual.key end} end}
    local event_first = (f._capacity[ritual.key] or 0) % 2 == 0
    if event_first then fire("RitualCompletedEvent", context) end
    if success ~= false then
        local increment = native_bundle_key(ritual) == hero_bundle and 10 or 15
        -- 此场景以阵营已有原版费用模板为初始状态。
        local key = native_bundle_key(ritual)
        if not f._bundles[key] then f._bundles[key] = cm:create_new_custom_effect_bundle(key) end
        if ritual.vanilla_rate > 0 then
            env.Ruination:modify_ritual_cap_cost(ritual.key, f, native_bundle_key(ritual), increment)
        end
        f._capacity[ritual.key] = (f._capacity[ritual.key] or 0) + 1
    end
    if not event_first then fire("RitualCompletedEvent", context) end
    flush()
end

local scenarios = {}
function scenarios.mixu_gorehoof()
    local ritual = assert(by_key.mixu_increase_hero_capacity_bst_gorehoof,
        "Mixu Gorehoof capacity ritual must be covered")
    equal(ritual.base_cost, 500, "Mixu reuses the Wargor expenditure of 500")
    equal(ritual.vanilla_rate, 0, "Mixu has no native escalating effect")
    boot()
    for _, percent in ipairs({0, 100, 1000, 12.5}) do
        options.beastmen_base_cost_percent = tostring(percent)
        change("no_scaling")
        equal(cost(player, ritual), math.floor(500 * percent / 100), "Gorehoof initial cost")
        purchase(player, ritual)
        equal(cost(player, ritual), math.floor(500 * percent / 100), "Gorehoof next cost")
    end
    equal(player._capacity[ritual.key], 4, "Gorehoof purchases add capacity")
    options.beastmen_base_cost_percent = "100"
    change("medium")
    equal(cost(player, ritual), 700, "Gorehoof uses its own four recorded purchases")
    purchase(player, ritual)
    equal(cost(player, ritual), 750, "Gorehoof custom growth follows purchase count")
    boot()
    equal(cost(player, ritual), 750, "Gorehoof history survives reload")
    options.beastmen_base_cost_percent = "0"
    change("custom", true, "1000")
    purchase(player, ritual)
    equal(cost(player, ritual), 0, "Gorehoof stays free under high growth")
    purchase(player, ritual, false)
    equal(player._capacity[ritual.key], 6, "failed purchase does not add capacity")
    change("medium", false)
    equal(cost(player, ritual), 500, "disabled restores Mixu fixed cost")
    purchase(ai, ritual)
    equal(cost(ai, ritual), 500, "Gorehoof AI cost is unchanged")
    env.get_mct = nil
    player._bundles[definition.bundle_key] = nil
    boot()
    equal(cost(player, ritual), 500, "without MCT Mixu is unchanged")
end
function scenarios.ungor_purchase_timing()
    local ungor = assert(by_key.wh2_dlc17_bst_ritual_unit_cap_ungor_herd_spearmen_herd)
    boot()
    equal(cost(player, ungor), 100, "ungor initial cost")
    for i = 1, 8 do
        purchase(player, ungor)
        equal(cost(player, ungor), 100, "ungor price after purchase " .. i)
        equal(value(player, unit_bundle, ungor.key .. "_cost_mod")
            + value(player, definition.bundle_key, ungor.key .. "_cost_mod"),
            0, "cancellation must use the latest native value")
    end
end
function scenarios.existing_campaign()
    seed(player, unit, 49.65) -- 原版三次购买：15、31.5、49.65。
    player._capacity[unit.key] = 3
    boot()
    equal(cost(player, unit), 500, "old campaign must return to base cost")
    equal(value(player, unit_bundle, unit.key .. "_cost_mod"), 49.65, "native history must survive")
    purchase(player, unit)
    equal(cost(player, unit), 500, "old escalation must not leak through 0%")
    equal(player._capacity[unit.key], 4, "purchased capacity must survive")
    change("light")
    equal(cost(player, unit), 600, "5% must include the three imported purchases")
    purchase(player, other)
    equal(cost(player, other), 367, "different units must have independent histories")
    equal(cost(player, unit), 600, "other purchases must not change this unit")
    change("custom", true, "7.5")
    equal(cost(player, unit), 650, "custom rate must reprice existing purchases")
    boot()
    equal(cost(player, unit), 650, "saved counters must survive campaign reload")
    change("medium", false)
    equal(cost(player, unit), 848, "disabled override must reveal native four-purchase cost")
    purchase(player, unit)
    equal(cost(player, unit), 957, "disabled purchases must still follow native compound scaling")
    change("medium")
    equal(cost(player, unit), 750, "disabled purchases must remain in history")
end
function scenarios.heroes_and_players()
    boot()
    for _, suffix in ipairs(hero_keys) do
        local ritual = assert(by_key["wh2_dlc17_bst_ritual_hero_capacity_" .. suffix])
        purchase(player, ritual); purchase(player, ritual)
        equal(cost(player, ritual), 500, "each hero must retain the base capacity cost")
    end
    purchase(second, unit)
    purchase(ai, unit)
    equal(cost(second, unit), 500, "second human player must be covered")
    equal(cost(ai, unit), 575, "AI must retain native scaling")
    assert(ai._bundles[definition.bundle_key] == nil, "AI must not receive our bundle")
    change("medium")
    equal(cost(second, unit), 550, "human factions need separate histories")
    equal(cost(player, unit), 500, "another faction's purchases must not count")
    for _, suffix in ipairs(hero_keys) do
        equal(cost(player, by_key["wh2_dlc17_bst_ritual_hero_capacity_" .. suffix]), 600, "hero counters must be separate")
    end
end
function scenarios.failed_and_excluded()
    boot()
    purchase(player, unit, false)
    change("medium")
    equal(cost(player, unit), 500, "failed rituals must not count")
    for _, key in ipairs({"wh2_dlc17_bst_ritual_army_cap_upgrade", "wh2_dlc17_ritual_crafting_bst_army_capacity_1"}) do
        fire("RitualCompletedEvent", {succeeded = function() return true end,
            performing_faction = function() return player end,
            ritual = function() return {ritual_key = function() return key end} end})
    end
    flush()
    equal(cost(player, unit), 500, "army upgrades must not enter unit history")
end
function scenarios.legacy_and_without_mct()
    seed(player, unit, 20) -- 不符合原版曲线，接入时计数从零开始。
    boot()
    change("medium")
    equal(cost(player, unit), 500, "unknown legacy history must use an explicit zero baseline")
    purchase(player, unit)
    equal(cost(player, unit), 550, "new purchases after legacy migration must count")
    change("medium", false)
    equal(cost(player, unit), 685, "legacy native cost must remain untouched")
    env.get_mct = nil
    player._bundles[definition.bundle_key] = nil
    boot()
    purchase(player, unit)
    equal(cost(player, unit), 778, "without MCT the mod must remain inert")
end
function scenarios.deep_history()
    local native = 0
    for _ = 1, 200 do native = f32(native + f32(f32(native / 10) + 15)) end
    seed(player, unit, native)
    boot()
    equal(cost(player, unit), 500, "large compound history must still return exactly to base cost")
    equal(value(player, unit_bundle, unit.key .. "_cost_mod"), native, "large native history must be preserved")
    change("light")
    equal(cost(player, unit), 5500, "large native history must import its actual purchase count")
end
function scenarios.initial_disabled()
    seed(player, unit, 49.65)
    options.beastmen_enabled = false
    boot()
    assert(player._bundles[definition.bundle_key] == nil, "starting disabled must leave the native bundle alone")
    equal(cost(player, unit), 748, "starting disabled must retain the old native price")
    purchase(player, unit)
    equal(cost(player, unit), 848, "disabled purchases must follow native scaling")
    change("light")
    equal(cost(player, unit), 600, "first enable must include imported and disabled purchases")
end

function scenarios.free_cost_labels()
    local function node(id, children, ritual_key)
        local n={text="99",children=children or {}}
        for _,child in ipairs(n.children) do child.parent=n end
        function n:Id() return id end
        function n:Visible() return true end
        function n:ChildCount() return #self.children end
        function n:Find(i) return self.children[i+1] end
        function n:SetStateText(value) self.text=value end
        function n:GetContextObject(kind)
            if kind=="CcoCampaignRitual" and ritual_key then
                return {Call=function(_,expression)
                    equal(expression,"RitualContext.Key","native ritual key")
                    return ritual_key
                end}
            end
        end
        return n
    end
    local labels,rows={},{}
    for _,ritual in ipairs(definition.rituals) do
        local price=node("dy_dread")
        labels[#labels+1]=price
        rows[#rows+1]=node("template",{price},ritual.key)
    end
    local item=node("dy_dread")
    rows[#rows+1]=node("item",{item},"wh2_dlc17_bst_ritual_item_other")
    local panel=node("beastmen_panel",rows)
    function core:get_ui_root() return panel end
    env.UIComponent=function(n) return n end
    env.find_uicomponent=function(root,id) return root and root:Id()==id and root end
    env.uicomponent_descended_from=function(n,id)
        while n do if n:Id()==id then return true end;n=n.parent end
        return false
    end
    local function reset() for _,price in ipairs(labels) do price.text="99" end end
    local function check()
        for _,price in ipairs(labels) do equal(price.text,"0","free unit and hero prices display zero") end
        equal(item.text,"99","item price is unaffected")
    end
    options.beastmen_base_cost_percent="0"
    boot();check()
    for opening=1,2 do
        reset();fire("PanelOpenedCampaign",{string="beastmen_panel"});flush();check()
    end
    reset();fire("ComponentLClickUp",{component=rows[1]});flush();check()
    reset();purchase(player,unit);flush();check()
    equal(cost(player,unit),0,"UI fix preserves free purchase")
    for _,percent in ipairs({"100","1000"}) do
        options.beastmen_base_cost_percent=percent
        reset();change("no_scaling");equal(labels[1].text,"99","paid prices use native display")
    end
    options.beastmen_base_cost_percent="0"
    reset();change("no_scaling",false);equal(labels[1].text,"99","disabled display is unchanged")
    change("no_scaling");check()
    player._human=false
    reset();fire("PanelOpenedCampaign",{string="beastmen_panel"});flush()
    equal(labels[1].text,"99","AI is unchanged")
    player._human=true
    env.get_mct=nil
    reset();boot();fire("PanelOpenedCampaign",{string="beastmen_panel"});flush()
    equal(labels[1].text,"99","without MCT display is unchanged")
end

function scenarios.base_cost_percent()
    seed(player,unit,49.65)
    player._capacity[unit.key]=3
    boot()
    for _,percent in ipairs({0,100,1000,12.5}) do
        options.beastmen_base_cost_percent=tostring(percent)
        change("no_scaling")
        equal(cost(player,unit),math.floor(unit.base_cost*percent/100),"Beastmen base cost")
        purchase(player,unit)
        equal(cost(player,unit),math.floor(unit.base_cost*percent/100),"Beastmen next purchase")
    end
    options.beastmen_base_cost_percent="0"
    change("custom",true,"1000"); purchase(player,unit)
    equal(cost(player,unit),0,"free Beastmen ignores growth")
    equal(player._capacity[unit.key],8,"free purchases add capacity")
    purchase(ai,unit)
    assert(cost(ai,unit)>0,"AI is unaffected by zero base")
    change("no_scaling",false)
    assert(cost(player,unit)>0,"disabled restores compound price")
end

assert(scenarios[arg[1]], "Unknown scenario")()
print("PASS " .. arg[1])
