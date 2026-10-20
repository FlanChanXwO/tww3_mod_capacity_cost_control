-- 战役运行时回归，执行真实配置、入口、派系适配器和 MCT 设置源码。
-- 模拟引擎对象与事件顺序，验证费用、购买历史、设置切换和军队容量。
-- 宿主 Lua 的模拟用于捕获逻辑回归，游戏内价格与扣款仍需独立验收。
local function load_in_env(path, env)
    if setfenv then
        return setfenv(assert(loadfile(path)), env)()
    end
    return assert(loadfile(path, "t", env))()
end

package.path = "src/script/campaign/?.lua;" .. package.path

local prefix = "wh3_dlc23_chd_ritual_unit_cap_"
local cost_key = "wh3_dlc23_bundle_chd_unit_cap_rituals_cost_mods"
local cap_key = "wh3_dlc23_bundle_chd_unit_cap_rituals"
local culture = "wh3_dlc23_chd_chaos_dwarfs"
local faction_key = "wh3_dlc23_chd_astragoth"
local ritual_keys = {prefix .. "chaos_dwarf_warriors", prefix .. "infernal_guard", prefix .. "warmachines"}
local options = {chaos_dwarfs_enabled = true, chaos_dwarfs_mode = "no_scaling", chaos_dwarfs_custom = "1"}
local bundles, listeners, first_ticks, callbacks = {}, {}, {}, {}
local loading_callbacks, named_values = {}, {}
local extra_factions = {}
local original_calls = 0
local local_faction_key = faction_key
local ui_root = nil
local saved = {tww3_mod_capacity_cost_control_debug_logging = false}

local function list(items)
    return {
        num_items = function() return #items end,
        item_at = function(_, i) return items[i + 1] end,
    }
end

local function new_bundle(key, values)
    local effects = {}
    for _, ritual_key in ipairs((key == cost_key or key == cap_key) and ritual_keys or {}) do
        local effect_key = key == cost_key and ritual_key .. "_cost_mod" or ritual_key
        local effect = {_key = effect_key, _value = values and values[effect_key] or 0}
        function effect:key() return self._key end
        function effect:value() return self._value end
        effects[#effects + 1] = effect
    end
    if key ~= cost_key and key ~= cap_key then
        for effect_key, value in pairs(values or {}) do
            local effect = {_key = effect_key, _value = value}
            function effect:key() return self._key end
            function effect:value() return self._value end
            effects[#effects + 1] = effect
        end
    end
    local bundle = {
        key = function() return key end,
        effects = function() return list(effects) end,
        set_effect_value = function(_, effect, value) effect._value = value end,
        set_duration = function() end,
        add_effect = function(_, effect_key, _, value)
            effects[#effects + 1] = {
                key = function() return effect_key end,
                value = function() return value end,
            }
        end,
    }
    function bundle:clone_and_create_custom_effect_bundle()
        local copy = {}
        for _, effect in ipairs(effects) do copy[effect:key()] = effect:value() end
        return new_bundle(key, copy)
    end
    function bundle:set_effect_value_by_key(effect_key, value)
        for _, effect in ipairs(effects) do
            if effect:key() == effect_key then effect._value = value; return true end
        end
        return false
    end
    return bundle
end

local faction = {
    name = function() return faction_key end,
    culture = function() return culture end,
    is_human = function() return true end,
    is_null_interface = function() return false end,
    effect_bundles = function()
        local items = {}
        for _, bundle in pairs(bundles) do items[#items + 1] = bundle end
        return list(items)
    end,
}

local cm = {
    model = function() return {} end,
    get_local_faction_name = function() return local_faction_key end,
    get_saved_value = function(_, key) return saved[key] end,
    set_saved_value = function(_, key, value) saved[key] = value end,
    add_loading_game_callback = function(_, callback) loading_callbacks[#loading_callbacks + 1] = callback end,
    load_named_value = function(_, key, fallback) return named_values[key] or fallback end,
    get_faction = function(_, key) return key == faction_key and faction or extra_factions[key] or false end,
    get_human_factions_of_culture = function(_, requested)
        return requested == culture and {faction_key} or {}
    end,
    create_new_custom_effect_bundle = function(_, key) return new_bundle(key) end,
    apply_custom_effect_bundle_to_faction = function(_, bundle) bundles[bundle:key()] = bundle end,
    remove_effect_bundle = function(_, key) bundles[key] = nil end,
    add_first_tick_callback = function(_, callback) first_ticks[#first_ticks + 1] = callback end,
    callback = function(_, callback, interval)
        -- 与原版 campaign timer 一致，0 秒回调立即执行。
        if interval <= 0 then callback() else callbacks[#callbacks + 1] = callback end
    end,
}

local mct_mod = {
        get_key = function() return "tww3_mod_capacity_cost_control" end,
    get_option_by_key = function(_, key)
        return {
            get_finalized_setting = function() return options[key] end,
            set_finalized_setting = function(_, value, first_load)
                assert(first_load == true, "migration must use MCT's load path")
                options[key] = value
            end,
        }
    end,
}
local core = {
    get_ui_root = function() return ui_root end,
    add_listener = function(_, name, event, condition, callback)
        listeners[#listeners + 1] = {event = event, condition = condition, callback = callback}
    end,
}
-- 游戏内 math.huge 不可用；不能让完整标准库掩盖配置校验错误。
local game_math = {}
for key, value in pairs(math) do
    if key ~= "huge" then game_math[key] = value end
end
local env = setmetatable({cm = cm, core = core, math = game_math}, {__index = _G})
env.UIComponent = function(component) return component end
env.find_uicomponent = function(root, id)
    return root and root._panel and root._panel:Id() == id and root._panel or nil
end
env.get_mct = function()
    return {get_mod_by_key = function() return mct_mod end}
end
function core:get_env() return env end
function core:load_global_script(name)
    if not package.loaded[name] then
        local path = "src/script/campaign/" .. string.gsub(name, "%.", "/") .. ".lua"
        if name == "capacity_cost_control.shared.generated_data" or name == "capacity_cost_control.config.metadata" then
            path = "build/generated/" .. string.match(name, "[^.]+$") .. ".lua"
        end
        package.loaded[name] = load_in_env(path, env) or true
    end
    return package.loaded[name]
end

local function get_value(bundle_key, effect_key)
    local bundle = bundles[bundle_key]
    if bundle then
        local effects = bundle:effects()
        for i = 0, effects:num_items() - 1 do
            local effect = effects:item_at(i)
            if effect:key() == effect_key then return effect:value() end
        end
    end
    return 0
end

local hellforge = {
    culture_key = culture,
    unit_cost_modifiers_bundle_string = cost_key,
    unit_cap_modifiers_bundle_string = cap_key,
    cost_mod_effect_suffix = "_cost_mod",
    unit_ritual_cost_mod_increment = 25,
    warmachine_ritual_cost_mod_increment = 10,
    get_faction_bundle_by_key = function(_, _, key) return bundles[key] end,
}
function hellforge:modify_ritual_cap_cost(ritual_key, _, bundle_key)
    original_calls = original_calls + 1
    local values = {}
    for _, key in ipairs(ritual_keys) do
        local effect = key .. "_cost_mod"
        values[effect] = get_value(bundle_key, effect)
    end
    local increment = ritual_key == prefix .. "warmachines"
        and self.warmachine_ritual_cost_mod_increment or self.unit_ritual_cost_mod_increment
    values[ritual_key .. "_cost_mod"] = values[ritual_key .. "_cost_mod"] + increment
    bundles[bundle_key] = new_bundle(bundle_key, values)
end
env.hellforge = hellforge

local function fire(event, context)
    for _, listener in ipairs(listeners) do
        if listener.event == event and (listener.condition == true or listener.condition(context)) then
            listener.callback(context)
        end
    end
end

local function flush_callbacks()
    while #callbacks > 0 do
        local pending = callbacks
        callbacks = {}
        for _, callback in ipairs(pending) do callback() end
    end
end

local function boot()
    load_in_env("src/script/campaign/mod/tww3_mod_capacity_cost_control_main.lua", env)
    for _, callback in ipairs(loading_callbacks) do callback({}) end
    if env.get_mct then fire("MctInitialized", {mct = env.get_mct()}) end
    -- CA 直到 first_tick 才把 cm 暴露到普通 require 使用的 _G。
    _G.cm = cm
    for _, callback in ipairs(first_ticks) do callback() end
    flush_callbacks()
end

local function purchase(ritual_key)
    hellforge:modify_ritual_cap_cost(ritual_key, faction, cost_key)
    local values = {}
    for _, key in ipairs(ritual_keys) do values[key] = get_value(cap_key, key) end
    values[ritual_key] = values[ritual_key] + 1
    bundles[cap_key] = new_bundle(cap_key, values)
end

local function assert_value(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. expected .. ", got " .. actual)
end

local scenarios = {}
local function amethyst_setup(human, without_mct, initial_disabled)
    local definition = core:load_global_script("capacity_cost_control.shared.generated_data").amethyst
    local history, stock, db_rates = {}, {}, {}
    local header
    for line in io.lines("data/amethyst_rituals.tsv") do
        local fields = {}
        for field in (line .. "\t"):gmatch("(.-)\t") do fields[#fields + 1] = field end
        if not header then
            header = {}
            for i, field in ipairs(fields) do header[field] = i end
        elseif fields[1]:sub(1, 1) ~= "#" then
            db_rates[fields[1]] = tonumber(fields[header.percentage_cost_increase_per_use])
        end
    end
    for i, record in ipairs(definition.rituals) do
        history[record.key] = ({9, 2, 3, 0})[i]
        stock[record.key] = 12
        assert(db_rates[record.key] == 0, "only the new zero-growth DB path is under test")
    end
    local f = {
        name = function() return definition.faction_key end,
        is_human = function() return human end,
        is_null_interface = function() return false end,
        has_effect_bundle = function(_, key) return bundles[key] ~= nil end,
        rituals = function() return {get_tracked_cost_uses = function(_, key) return history[key] end} end,
    }
    extra_factions[definition.faction_key] = f
    options.amethyst_enabled, options.amethyst_mode = not initial_disabled, "no_scaling"
    if without_mct then env.get_mct = nil end
    local function f32(value) return string.unpack("f", string.pack("f", value)) end
    local function cost(index)
        local record = definition.rituals[index]
        local modifier = get_value(definition.bundle_key, record.effect_key)
        -- 原版增长已由实际 DB 归零；按观测到的基础费用取整顺序模拟引擎。
        return math.floor(f32(math.floor(f32(record.base_cost * f32(1 + f32(modifier / 100))))
            * f32(1 + db_rates[record.key] * history[record.key])))
    end
    local function buy(index, succeeded, performing)
        local record = definition.rituals[index]
        if succeeded ~= false and not performing then stock[record.key] = stock[record.key] + 1 end
        fire("RitualCompletedEvent", {
            succeeded = function() return succeeded ~= false end,
            performing_faction = function() return performing or f end,
            ritual = function() return {ritual_key = function() return record.key end} end,
        }); flush_callbacks()
    end
    local function change(mode, enabled, custom)
        options.amethyst_enabled, options.amethyst_mode, options.amethyst_custom = enabled, mode, custom
        fire("MctOptionSettingFinalized", {mod = function() return mct_mod end}); flush_callbacks()
    end
    boot()
    return definition, history, stock, cost, buy, change
end

function scenarios.amethyst_history()
    local definition, history, stock, cost, buy, change = amethyst_setup(true, false)
    for i, record in ipairs(definition.rituals) do
        assert_value(cost(i), record.base_cost, "old campaign must return to its base price")
        assert_value(stock[record.key], 12, "migration must preserve existing stock")
        for _ = 1, 4 do
            buy(i)
            assert_value(cost(i), record.base_cost, "continuous purchases must keep the exact base price")
        end
        assert_value(stock[record.key], 16, "successful purchase must still add stock")
    end
    local function prices(expected, message)
        for i, value in ipairs(expected) do assert_value(cost(i), value, message) end
    end
    change("light", true)
    prices({1650, 2600, 1350, 1800}, "5% must use migrated and independently accumulated counts")
    buy(1, false)
    buy(1, true, {name = function() return "other_faction" end, is_human = function() return true end,
        is_null_interface = function() return false end})
    prices({1650, 2600, 1350, 1800}, "failed and other-faction purchases must not count")
    change("medium", true)
    prices({2300, 3200, 1700, 2100}, "10% must preserve history")
    change("custom", true, "7.5")
    prices({1975, 2900, 1525, 1950}, "custom rates must preserve history")
    change("no_scaling", false)
    prices({4250, 5000, 2750, 3000}, "disabled override must restore the full vanilla curve")
    buy(1)
    assert_value(cost(1), 4500, "disabled purchases must still count")
    change("no_scaling", true)
    prices({1000, 2000, 1000, 1500}, "re-enabling must return to exact base prices")
    for key in pairs(history) do history[key] = 0 end
    for key in pairs(package.loaded) do
        if string.find(key, "capacity_cost_control%.", 1) == 1 then package.loaded[key] = nil end
    end
    listeners, first_ticks, callbacks = {}, {}, {}
    boot()
    change("light", true)
    prices({1700, 2600, 1350, 1800}, "reload must prefer saved counts over frozen native counts")
    for _, record in ipairs(definition.rituals) do
        assert_value(history[record.key], 0, "adapter must not rewrite native tracked-use counters")
    end
end

function scenarios.amethyst_without_mct()
    options.amethyst_base_cost_percent="0"
    local _, _, _, cost, buy = amethyst_setup(true, true)
    for i, expected in ipairs({3250, 3000, 1750, 1500}) do
        assert_value(cost(i), expected, "without MCT must keep vanilla prices")
    end
    buy(1)
    assert_value(cost(1), 3500, "without MCT purchases must still follow vanilla")
end

function scenarios.amethyst_ai()
    options.amethyst_base_cost_percent="0"
    local _, _, _, cost, buy = amethyst_setup(false, false)
    for i, expected in ipairs({3250, 3000, 1750, 1500}) do
        assert_value(cost(i), expected, "AI must ignore player settings and keep vanilla prices")
    end
    buy(1)
    assert_value(cost(1), 3500, "AI purchases must preserve vanilla escalation")
end

function scenarios.amethyst_initial_disabled()
    options.amethyst_base_cost_percent="0"
    local _, _, _, cost, buy = amethyst_setup(true, false, true)
    assert_value(cost(1), 3250, "starting disabled must recover the old vanilla price")
    buy(1)
    assert_value(cost(1), 3500, "starting disabled must continue the vanilla curve")
end

function scenarios.amethyst_engine_logging()
    local definition, _, _, cost = amethyst_setup(true, false)
    local_faction_key = definition.faction_key
    saved.tww3_mod_capacity_cost_control_debug_logging = true
    local logs, queries = {}, 0
    core:load_global_script("capacity_cost_control.utils.logger").write = function(message) logs[#logs + 1] = message end
    local rows = {}
    local function node(id, children, context)
        return {Id = function() return id end, Visible = function() return true end,
            ChildCount = function() return #children end,
            Find = function(_, i) return children[i + 1] end,
            GetContextObject = function() return context end}
    end
    for i, record in ipairs(definition.rituals) do
        rows[i] = node("row", {}, {Call = function(_, query)
            if query == "RitualContext.Key" then return record.key end
            assert(query == "ResourceTransactionContext.PooledResourceTransactionList[0].AbsoluteValue")
            queries = queries + 1
            return cost(i)
        end})
    end
    ui_root = {_panel = node("dlc25_don_main", rows)}
    fire("PanelOpenedCampaign", {string = "dlc25_don_main"}); flush_callbacks()
    assert_value(queries, 4, "engine logging must read all four real contexts")
    assert(string.find(table.concat(logs, "\n"), "cost=2000", 1), "engine cost must be logged")
    for i, record in ipairs(definition.rituals) do
        assert_value(cost(i), record.base_cost, "logging must not mutate fees or UI")
    end
end

function scenarios.campaign_environment()
    boot()
    purchase(ritual_keys[1])
    assert_value(get_value(cost_key, ritual_keys[1] .. "_cost_mod"), 0, "0% must suppress the vanilla 25% increase")
    assert_value(get_value(cap_key, ritual_keys[1]), 1, "capacity purchase must still be recorded")
end


function scenarios.mct_custom_input_validation()
    assert(env.math.huge == nil, "validation must run without math.huge")
    local validators, sections, defaults, dropdowns = {}, {}, {}, {}
    local labels, buttons, section_titles, sorters = {}, {}, {}, {}
    local link_options, link_targets = {}, {}
    local layout_groups, registered_version, workshop_id, github_id
    local function noop() end
    local registration = {set_title = function(_, title)
            assert_value(title, "兵种容量费用控制", "MCT title must match the current mod name")
        end,
        set_author = function(_, author) assert_value(author, "FlanChanXwO", "author comes from project metadata") end,
        set_version = function(_, version) registered_version = version end,
        set_workshop_id = function(_, id) workshop_id = id end,
        set_github_id = function(_, id) github_id = id end,
        set_description = noop,
        get_main_page = function() return {populate_sidebar = noop} end,
        add_new_section = function(_, key)
            sections[#sections + 1] = key
            return {
                set_localised_text = function(_, text) section_titles[key] = text end,
                set_option_sort_function = function(_, sorter) sorters[key] = sorter end,
            }
        end,
        add_new_option = function(_, key)
            local option = {ui_create_option = function(self)
                    assert_value(self:get_uic_template(), "ui/tww3_mod_capacity_cost_control/action_link", "use native link template")
                    return {SetContextObject = function(_, context) link_targets[key] = context end}
                end,
                set_assigned_section = noop,
                set_text = function(_, text) labels[key] = text end,
                set_button_text = function(_, text) buttons[key] = text end,
                set_tooltip_text = noop,
                set_default_value = function(_, value) defaults[key] = value end,
                add_dropdown_value = function(_, value)
                    dropdowns[key] = dropdowns[key] or {}
                    dropdowns[key][#dropdowns[key] + 1] = value
                end,
                add_validity_test = function(_, test) validators[key] = test end}
            link_options[key] = option
            return option
        end}
    env.get_mct = function()
        return {register_mod = function(_, key)
            assert(key == "tww3_mod_capacity_cost_control")
            return registration
        end}
    end
    local contexts = {}
    env.common = {get_context_value = function() return true end,
        set_context_value = function(key, url) contexts[key] = url end}
    env.cco = function(kind, key)
        assert_value(kind, "CcoScriptObject", "native callback uses a script context")
        return {key = key, url = contexts[key]}
    end
    -- MCT settings 没有 campaign core；只允许通过 pack 中的 loadfile 路径加载依赖。
    local mct_env = setmetatable({core = false}, {__index = env})
    mct_env.loadfile = function(path)
        if path == "script/mct/capacity_cost_control/layout.lua" then
            return function() return {apply = function(_, left, right) layout_groups = {left, right} end} end
        end
        local generated = path == "script/campaign/capacity_cost_control/config/metadata.lua"
            or path == "script/campaign/capacity_cost_control/shared/i18.lua"
        local file = generated and "build/generated/" .. string.match(path, "[^/]+$") or "src/" .. path
        return loadfile(file, "t", mct_env)
    end
    load_in_env("src/script/mct/settings/tww3_mod_capacity_cost_control_mct.lua", mct_env)
    local metadata = assert(loadfile("build/generated/metadata.lua"))()
    assert_value(registered_version, metadata.version, "MCT must display the packaged version")
    assert_value(workshop_id, "3821170924", "MCT must link the published Workshop item")
    assert_value(github_id, "FlanChanXwO/tww3_mod_capacity_cost_control", "MCT must link the project repository")
    assert(labels.project_issues == nil, "issue tracker button must not be registered")
    for key, url in pairs({project_workshop = "https://steamcommunity.com/sharedfiles/filedetails/?id=" .. metadata.workshop_id,
        project_repository = metadata.github_repository}) do
        link_options[key]:ui_create_option({})
        local target = key == "project_repository"
            and "https://steamcommunity.com/linkfilter/?u=https%3A%2F%2Fgithub.com%2FFlanChanXwO%2Ftww3_mod_capacity_cost_control" or url
        assert_value(link_targets[key].url, target, "GitHub uses Steam confirmation; Workshop stays direct")
    end
    for key, title in pairs({project_workshop = "创意工坊", project_repository = "参与贡献"}) do
        assert(labels[key] == title, key .. ": action label must be localized separately from its button")
        assert_value(buttons[key], title, "action button must use the localized title")
    end
    assert_value(section_titles.links, "其它", "links section title")
    assert_value(table.concat(sorters.links(), ","), "project_workshop,project_repository", "link display order")
    local order = {"nagash", "chaos_dwarfs", "bhashiva", "beastmen", "amethyst"}
    for i, prefix in ipairs(order) do
        assert_value(sections[i + 2], prefix, "faction registration order must remain unchanged")
        assert_value(layout_groups[1][i], prefix, "left layout must match registration order")
        assert(defaults[prefix .. "_enabled"] == true, "override must default to enabled")
        assert_value(defaults[prefix .. "_mode"], "no_scaling", "mode default must remain 0%")
        assert_value(defaults[prefix .. "_custom"], "1", "custom default must remain a text value")
        assert_value(defaults[prefix .. "_base_cost_percent"], "100", "base multiplier default")
        assert_value(table.concat(dropdowns[prefix .. "_mode"], ","), "no_scaling,light,medium,custom",
            "all pricing modes must be registered in the same order")
    end
    assert(defaults.debug_logging == false, "diagnostics must default to disabled")
    assert_value(table.concat(layout_groups[2], ","), "debug,links", "other sections must remain on the right")
    local count = 0
    for key, validate in pairs(validators) do
        count = count + 1
        for _, text in ipairs({"1", "100", "7.5", "0.5"}) do
            assert(validate(text) == true, key .. " must accept " .. text)
        end
        assert(validate("0") == (key:match("_custom$") == nil), key .. " zero validation")
        for _, text in ipairs({"-5", "-0.5", "", "abc", "1e9999", "-1e9999"}) do
            local valid, message = validate(text)
            assert(valid == false and type(message) == "string", key .. " must reject " .. text)
        end
    end
    assert_value(count, 11, "all percentage inputs must use validation")
end

function scenarios.custom_100_without_math_huge()
    boot()
    local config = core:load_global_script("capacity_cost_control.config.settings")
    local defaults = config.default_settings()
    defaults.nagash.enabled = false
    assert(defaults.chaos_dwarfs.enabled == true and config.default_settings().nagash.enabled == true,
        "returned settings must not mutate shared constants or other factions")
    purchase(ritual_keys[1])
    options.chaos_dwarfs_mode, options.chaos_dwarfs_custom = "custom", "100"
    fire("MctOptionSettingFinalized", {mod = function() return mct_mod end}); flush_callbacks()
    assert_value(get_value(cost_key, ritual_keys[1] .. "_cost_mod"), 100,
        "confirmed custom 100 must reprice an existing purchase immediately")
    purchase(ritual_keys[1])
    assert_value(get_value(cost_key, ritual_keys[1] .. "_cost_mod"), 200,
        "custom 100 must apply to subsequent purchases")
    options.chaos_dwarfs_mode = "medium"
    fire("MctOptionSettingFinalized", {mod = function() return mct_mod end}); flush_callbacks()
    assert_value(get_value(cost_key, ritual_keys[1] .. "_cost_mod"), 20,
        "switching away from custom must not be stuck on the previous rate")
    options.chaos_dwarfs_mode, options.chaos_dwarfs_custom = "custom", "7.5"
    fire("MctOptionSettingFinalized", {mod = function() return mct_mod end}); flush_callbacks()
    assert_value(get_value(cost_key, ritual_keys[1] .. "_cost_mod"), 15, "decimal custom rates must remain valid")
    local config = core:load_global_script("capacity_cost_control.config.settings")
    for _, invalid in ipairs({"-5", "0", "", "abc", "1e9999", "-1e9999"}) do
        assert(config.resolve_rate({enabled = true, mode = "custom", custom_percent = invalid}) == nil,
            "invalid runtime rate must be rejected: " .. invalid)
    end
end

function scenarios.mct_change()
    boot()
    options.chaos_dwarfs_mode = "medium"
    fire("MctOptionSettingFinalized", {mod = function() return mct_mod end})
    flush_callbacks()
    purchase(ritual_keys[1])
    assert_value(get_value(cost_key, ritual_keys[1] .. "_cost_mod"), 10, "MCT change must take effect in the current campaign")
end

function scenarios.existing_campaign()
    bundles[cap_key] = new_bundle(cap_key, {[ritual_keys[1]] = 2, [ritual_keys[2]] = 1, [ritual_keys[3]] = 3})
    bundles[cost_key] = new_bundle(cost_key, {
        [ritual_keys[1] .. "_cost_mod"] = 50,
        [ritual_keys[2] .. "_cost_mod"] = 25,
        [ritual_keys[3] .. "_cost_mod"] = 30,
    })
    boot()
    assert_value(get_value(cost_key, ritual_keys[1] .. "_cost_mod"), 0, "loading at 0% must remove existing escalation")
    assert_value(get_value(cap_key, ritual_keys[1]), 2, "existing capacity must be preserved")
    purchase(ritual_keys[1])
    options.chaos_dwarfs_mode = "light"
    fire("MctOptionSettingFinalized", {mod = function() return mct_mod end})
    flush_callbacks()
    assert_value(get_value(cost_key, ritual_keys[1] .. "_cost_mod"), 15, "5% must use all three historical purchases")
    assert_value(get_value(cost_key, ritual_keys[2] .. "_cost_mod"), 5, "unit categories must keep separate histories")
    assert_value(get_value(cost_key, ritual_keys[3] .. "_cost_mod"), 15, "warmachines must use the selected rate")
    options.chaos_dwarfs_enabled = false
    fire("MctOptionSettingFinalized", {mod = function() return mct_mod end})
    flush_callbacks()
    assert_value(get_value(cost_key, ritual_keys[1] .. "_cost_mod"), 75, "disabling must restore vanilla unit escalation")
    assert_value(get_value(cost_key, ritual_keys[3] .. "_cost_mod"), 30, "disabling must restore vanilla warmachine escalation")
    purchase(ritual_keys[3])
    assert_value(get_value(cost_key, ritual_keys[3] .. "_cost_mod"), 40, "disabled purchases must follow vanilla")
    assert_value(original_calls, 1, "only disabled purchases must call vanilla")
end

function scenarios.without_mct()
    options.chaos_dwarfs_base_cost_percent="0"
    env.get_mct = nil
    boot()
    purchase(ritual_keys[1])
    assert_value(get_value(cost_key, ritual_keys[1] .. "_cost_mod"), 25, "without MCT vanilla must remain active")
    assert_value(original_calls, 1, "without MCT purchases must call vanilla")
end

function scenarios.initial_disabled()
    options.chaos_dwarfs_base_cost_percent="0"
    options.chaos_dwarfs_enabled = false
    bundles[cap_key] = new_bundle(cap_key, {[ritual_keys[1]] = 2})
    local original_bundle = new_bundle(cost_key, {[ritual_keys[1] .. "_cost_mod"] = 50})
    bundles[cost_key] = original_bundle
    boot()
    assert(bundles[cost_key] == original_bundle, "starting disabled must not rebuild the vanilla bundle")
    purchase(ritual_keys[1])
    assert_value(get_value(cost_key, ritual_keys[1] .. "_cost_mod"), 75, "starting disabled must follow vanilla")
end

function scenarios.multiple_purchases()
    options.chaos_dwarfs_mode = "custom"
    options.chaos_dwarfs_custom = "7.5"
    boot()
    purchase(ritual_keys[1])
    purchase(ritual_keys[2])
    purchase(ritual_keys[1])
    purchase(ritual_keys[3])
    assert_value(get_value(cost_key, ritual_keys[1] .. "_cost_mod"), 15, "custom rate must accumulate per category")
    assert_value(get_value(cost_key, ritual_keys[2] .. "_cost_mod"), 7.5, "another category must retain its modifier")
    assert_value(get_value(cost_key, ritual_keys[3] .. "_cost_mod"), 7.5, "warmachines must use the custom rate")
end

function scenarios.ritual_adapters()
    local definitions = core:load_global_script("capacity_cost_control.shared.generated_data")
    for _, key in ipairs({"nagash"}) do
        options[key .. "_enabled"] = true
        options[key .. "_mode"] = "no_scaling"
        extra_factions[definitions[key].faction_key] = {
            name = function() return definitions[key].faction_key end,
            is_human = function() return true end,
            is_null_interface = function() return false end,
            has_effect_bundle = function() return false end,
            rituals = function() return {get_tracked_cost_uses = function() return 1 end} end,
        }
    end
    boot()
    local nagash = definitions.nagash
    local modifier = get_value(nagash.bundle_key, nagash.rituals[1].effect_key)
    assert_value(math.floor(138 * (1 + modifier / 100)), 120, "Nagash must read campaign MCT settings")
end

function scenarios.ritual_purchase_history()
    local definitions = core:load_global_script("capacity_cost_control.shared.generated_data")
    local histories = {}
    for _, key in ipairs({"nagash"}) do
        options[key .. "_enabled"] = true
        options[key .. "_mode"] = "no_scaling"
        local definition = definitions[key]
        local history = {}
        histories[key] = history
        extra_factions[definition.faction_key] = {
            name = function() return definition.faction_key end,
            is_human = function() return true end,
            is_null_interface = function() return false end,
            has_effect_bundle = function(_, bundle) return bundles[bundle] ~= nil end,
            rituals = function()
                return {get_tracked_cost_uses = function(_, ritual) return history[ritual] or 0 end}
            end,
        }
    end
    local nagash = definitions.nagash
    local polearm = nagash.rituals[28]
    assert(polearm.key == "wh3_dlc29_ritual_nag_unit_capacity_polearm_inf")
    histories.nagash[polearm.key] = 3
    boot()
    local function cost(definition, ritual, uses)
        local vanilla = math.floor(ritual.base_cost * (1 + ritual.vanilla_rate * math.min(uses, ritual.max_increases)))
        return math.floor(vanilla * (1 + get_value(definition.bundle_key, ritual.effect_key) / 100))
    end
    assert_value(cost(nagash, polearm, 3), 85, "existing Nagash campaign must reprice to 85")
    local items = {{key = "nagash", definition = nagash, ritual = polearm}}
    for _, item in ipairs(items) do
        local history = histories[item.key]
        for _ = 1, 5 do
            history[item.ritual.key] = (history[item.ritual.key] or 0) + 1
            fire("RitualCompletedEvent", {
                ritual = function() return {ritual_key = function() return item.ritual.key end} end,
                performing_faction = function() return extra_factions[item.definition.faction_key] end,
                succeeded = function() return true end,
            })
            flush_callbacks()
            assert_value(cost(item.definition, item.ritual, history[item.ritual.key]),
                item.ritual.base_cost, "repeated purchases must keep the base price")
        end
        local uses = history[item.ritual.key]
        options[item.key .. "_mode"] = "light"
        fire("MctOptionSettingFinalized", {mod = function() return mct_mod end})
        flush_callbacks()
        assert_value(cost(item.definition, item.ritual, uses),
            math.floor(item.ritual.base_cost * (100 + 5 * uses) / 100), "5% must use existing purchase history")
        options[item.key .. "_mode"] = "custom"
        options[item.key .. "_custom"] = "7.5"
        fire("MctOptionSettingFinalized", {mod = function() return mct_mod end})
        flush_callbacks()
        assert_value(cost(item.definition, item.ritual, uses),
            math.floor(item.ritual.base_cost * (100 + 7.5 * uses) / 100), "custom rate must use existing purchase history")
        options[item.key .. "_enabled"] = false
        fire("MctOptionSettingFinalized", {mod = function() return mct_mod end})
        flush_callbacks()
        assert(bundles[item.definition.bundle_key] == nil, "disabling must remove our modifiers")
        assert_value(history[item.ritual.key], uses, "refreshes must preserve vanilla use tracking")
        options[item.key .. "_enabled"] = true
        options[item.key .. "_mode"] = "no_scaling"
        fire("MctOptionSettingFinalized", {mod = function() return mct_mod end})
        flush_callbacks()
    end
end

function scenarios.ai_preserved()
    local definitions = core:load_global_script("capacity_cost_control.shared.generated_data")
    for _, key in ipairs({"nagash"}) do
        options[key .. "_enabled"] = true
        options[key .. "_mode"] = "no_scaling"
        extra_factions[definitions[key].faction_key] = {
            is_human = function() return false end,
            is_null_interface = function() return false end,
            has_effect_bundle = function() return false end,
        }
    end
    boot()
    for _, key in ipairs({"nagash"}) do
        assert(bundles[definitions[key].bundle_key] == nil, key .. " AI must not receive price modifiers")
    end
    hellforge:modify_ritual_cap_cost(ritual_keys[1], {is_human = function() return false end}, cost_key)
    assert_value(original_calls, 1, "Chaos Dwarf AI must call vanilla even while player override is enabled")
    assert_value(get_value(cost_key, ritual_keys[1] .. "_cost_mod"), 25, "Chaos Dwarf AI must retain vanilla escalation")
end


local function bhashiva_setup(human, without_mct, initial_disabled, native_first, fresh)
    local definition = core:load_global_script("capacity_cost_control.shared.generated_data").bhashiva
    local army = definition.rituals[1]
    local army_bundle = "wh3_cp1_ritual_cth_army_capacity_bundle"
    local army_effect = "wh2_dlc09_effect_increase_army_capacity"
    local history, capacity, db_rates = {}, {}, {}
    local header
    for line in io.lines("data/bhashiva_rituals.tsv") do
        local fields = {}
        for field in (line .. "\t"):gmatch("(.-)\t") do fields[#fields + 1] = field end
        if not header then
            header = {}
            for i, field in ipairs(fields) do header[field] = i end
        elseif fields[1]:sub(1, 1) ~= "#" then
            db_rates[fields[1]] = tonumber(fields[header.percentage_cost_increase_per_use])
        end
    end
    for i, record in ipairs(definition.rituals) do
        history[record.key] = not fresh and i == 3 and 1 or 0
        if not fresh and i == 1 and native_first then history[record.key] = 2 end
        capacity[record.key] = 12
        assert(db_rates[record.key] == 0, "Bhashiva DB growth must be disabled")
    end
    -- 模拟旧档已买两次军队容量，但费用计数已被旧参考包清零。
    if not fresh then bundles[army_bundle] = new_bundle(army_bundle, {[army_effect] = 2}) end
    local f = {
        name = function() return definition.faction_key end,
        is_human = function() return human end,
        is_null_interface = function() return false end,
        has_effect_bundle = function(_, key) return bundles[key] ~= nil end,
        effect_bundles = faction.effect_bundles,
        rituals = function() return {get_tracked_cost_uses = function(_, key) return history[key] end} end,
    }
    extra_factions[definition.faction_key] = f
    options.bhashiva_enabled, options.bhashiva_mode = not initial_disabled, "no_scaling"
    if without_mct then env.get_mct = nil end
    local native = {config = {faction_key = definition.faction_key,
        army_capacity_ritual_key = army.key, army_capacity_effect_bundle_key = army_bundle,
        army_capacity_effect_key = army_effect},
        get_faction_bundle_by_key = function(_, _, key) return bundles[key] end}
    local register = load_in_env("tests/lua/fixtures/bhashiva_vanilla.lua", env)
    if native_first then register(native) end
    local function f32(value) return string.unpack("f", string.pack("f", value)) end
    local function cost(index)
        local record = definition.rituals[index]
        local modifier = get_value(definition.bundle_key, record.effect_key)
        -- 先取整基础费用，再应用 DB 使用递增；旧反算模型在这里得到 49。
        return math.floor(f32(math.floor(f32(record.base_cost * f32(1 + f32(modifier / 100))))
            * f32(1 + db_rates[record.key] * history[record.key])))
    end
    local function buy(index, succeeded, performing)
        local record = definition.rituals[index]
        if succeeded ~= false and not performing then
            capacity[record.key] = capacity[record.key] + 1
            if index == 1 then bundles[army_bundle] = new_bundle(army_bundle, {[army_effect] = 1}) end
        end
        fire("RitualCompletedEvent", {
            succeeded = function() return succeeded ~= false end,
            performing_faction = function() return performing or f end,
            ritual = function() return {ritual_key = function() return record.key end} end,
        }); flush_callbacks()
    end
    local function change(mode, enabled, custom)
        options.bhashiva_enabled, options.bhashiva_mode, options.bhashiva_custom = enabled, mode, custom
        fire("MctOptionSettingFinalized", {mod = function() return mct_mod end}); flush_callbacks()
    end
    boot()
    if not native_first then register(native) end
    return definition, history, capacity, cost, buy, change, function() return get_value(army_bundle, army_effect) end
end

local function bhashiva_history(native_first)
    local definition, history, capacity, cost, buy, change, army_capacity = bhashiva_setup(true, false, false, native_first)
    for i, record in ipairs(definition.rituals) do
        assert_value(cost(i), record.base_cost, "old Bhashiva campaign must return to exact base price")
        assert_value(capacity[record.key], 12, "migration must preserve unit capacity")
        for _ = 1, 4 do
            buy(i)
            assert_value(cost(i), record.base_cost, "repeated Bhashiva purchases must keep exact base prices")
        end
        assert_value(capacity[record.key], 16, "unit capacity payload must still apply")
    end
    assert_value(army_capacity(), 6, "four army purchases must advance old capacity 2 to 6")
    buy(1, false)
    assert_value(army_capacity(), 6, "failed army rituals must not let the native listener restore stale capacity")
    local counts = cm:get_saved_value("tww3_mod_capacity_cost_control_shangyang_purchases_" .. definition.faction_key)
    assert_value(counts[definition.rituals[2].key], 4, "categories must count independently")
    assert_value(counts[definition.rituals[3].key], 5, "readable old unit history must be imported")
    local function expected(rate, original)
        for i, record in ipairs(definition.rituals) do
            local multiplier = math.min(1 + (original and record.vanilla_rate or rate) * counts[record.key],
                1 + record.vanilla_rate * record.max_increases)
            assert_value(cost(i), math.floor(record.base_cost * multiplier), "selected rate must use full history")
        end
    end
    buy(3, false)
    buy(3, true, {name = function() return "other_faction" end, is_human = function() return true end,
        is_null_interface = function() return false end})
    assert_value(counts[definition.rituals[3].key], 5, "failed and other-faction rituals must not count")
    change("light", true); expected(0.05)
    change("medium", true); expected(0.10)
    change("custom", true, "7.5"); expected(0.075)
    change("no_scaling", false); expected(nil, true)
    buy(1)
    assert_value(army_capacity(), 7, "disabled overrides must still advance army capacity")
    expected(nil, true)
    change("no_scaling", true); expected(0)
    for key in pairs(history) do history[key] = 0 end
    for key in pairs(package.loaded) do
        if string.find(key, "capacity_cost_control%.", 1) == 1 then package.loaded[key] = nil end
    end
    listeners, first_ticks, callbacks = {}, {}, {}
    boot()
    change("light", true); expected(0.05)
    assert_value(army_capacity(), 7, "reload must retain army capacity")
    for key, value in pairs(history) do assert_value(value, 0, "adapter must not rewrite native use counters") end
end

function scenarios.bhashiva_history_native_first() bhashiva_history(true) end
function scenarios.bhashiva_history_mod_first() bhashiva_history(false) end


function scenarios.bhashiva_new_campaign()
    local _, _, _, cost, buy, _, army_capacity = bhashiva_setup(true, false, false, true, true)
    assert_value(army_capacity(), 0, "fresh campaign must not receive free army capacity")
    for expected = 1, 4 do
        buy(1)
        assert_value(army_capacity(), expected, "each army purchase must add one capacity")
        assert_value(cost(1), 250, "army price must remain exact at 0%")
    end
end

local function bhashiva_vanilla_prices(human, without_mct, disabled)
    local definition, _, _, cost, buy, _, army_capacity = bhashiva_setup(human, without_mct, disabled, true)
    assert_value(cost(1), 750, "AI/disabled/no MCT must retain original army price")
    assert_value(cost(3), 55, "AI/disabled/no MCT must retain original jade infantry price")
    buy(1); buy(3)
    assert_value(cost(1), 1000, "original army curve must continue")
    assert_value(cost(3), 60, "original unit curve must continue")
    assert_value(army_capacity(), 3, "original army capacity must continue")
end

function scenarios.bhashiva_without_mct() options.bhashiva_base_cost_percent="0"; bhashiva_vanilla_prices(true, true, false) end
function scenarios.bhashiva_ai() options.bhashiva_base_cost_percent="0"; bhashiva_vanilla_prices(false, false, false) end
function scenarios.bhashiva_initial_disabled() options.bhashiva_base_cost_percent="0"; bhashiva_vanilla_prices(true, false, true) end

function scenarios.legacy_migration()
    local data = core:load_global_script("capacity_cost_control.shared.generated_data")
    local amethyst_key = "tww3_mod_capacity_cost_control_amethyst_purchases_" .. data.amethyst.faction_key
    local old_amethyst_key = "wh3_ccc_amethyst_purchases_" .. data.amethyst.faction_key
    local first = data.amethyst.rituals[1].key
    local second = data.amethyst.rituals[2].key
    saved[old_amethyst_key] = {[first] = 4, [second] = 7}
    saved[amethyst_key] = {[first] = 0}
    local shangyang_key = "tww3_mod_capacity_cost_control_shangyang_purchases_" .. data.bhashiva.faction_key
    local old_shangyang_key = "wh3_ccc_bhashiva_purchases_" .. data.bhashiva.faction_key
    local army = data.bhashiva.rituals[1].key
    saved[old_shangyang_key] = {[army] = 3}
    local beastmen_key = "tww3_mod_capacity_cost_control_beastmen_purchases_test_faction"
    saved.wh3_ccc_beastmen_purchases_test_faction = {unit = 5, invalid = -1}
    named_values.mct_registry = {saved_mods = {
        wh3_capacity_cost_control = {options = {
            chaos_dwarfs_enabled = {setting = false}, chaos_dwarfs_mode = {setting = "custom"},
            chaos_dwarfs_custom = {setting = "100"}, amethyst_enabled = {setting = false},
        }},
        tww3_mod_capacity_cost_control = {options = {amethyst_enabled = {setting = true}}},
    }}
    options.amethyst_enabled = true
    boot()
    assert(options.chaos_dwarfs_enabled == false, "old false setting must migrate")
    assert_value(options.chaos_dwarfs_mode, "custom", "old pricing mode must migrate")
    assert_value(options.chaos_dwarfs_custom, "100", "old custom percentage must migrate")
    assert(options.amethyst_enabled == true, "new MCT setting must win over old settings")
    local purchases = core:load_global_script("capacity_cost_control.store.purchases")
    local counts = purchases.get_or_import(amethyst_key, data.amethyst.rituals, function() return 0 end)
    assert_value(counts[first], 0, "new zero count must be preserved")
    assert_value(counts[second], 7, "missing count must come from old history")
    counts = purchases.get_or_import(shangyang_key, data.bhashiva.rituals, function() return 0 end)
    assert_value(counts[army], 3, "bhashiva history must migrate to shangyang")
    purchases.record_purchase(beastmen_key, "unit")
    assert_value(saved[beastmen_key].unit, 6, "purchase before initialization must increment old history")
    assert(saved[beastmen_key].invalid == nil, "invalid old counts must not migrate")
    purchases.record_purchase(amethyst_key, second)
    assert_value(saved[old_amethyst_key][second], 7, "migration must not mutate old records")
    package.loaded["capacity_cost_control.store.purchases"] = nil
    purchases = core:load_global_script("capacity_cost_control.store.purchases")
    counts = purchases.get_or_import(amethyst_key, data.amethyst.rituals, function() error("history already exists") end)
    assert_value(counts[second], 8, "reloading must not reapply old purchase counts")
    options.chaos_dwarfs_custom = "5"
    fire("MctInitialized", {})
    assert_value(options.chaos_dwarfs_custom, "5", "migration must not overwrite later MCT changes")
end

function scenarios.purchase_store()
    local name = "capacity_cost_control.store.purchases"
    local purchases = core:load_global_script(name)
    local records = {{key = "first"}, {key = "second"}}
    local key = "test_purchase_store_faction_one"
    saved[key] = {first = 0}
    local imports = 0
    local counts = purchases.get_or_import(key, records, function(record)
        assert_value(record.key, "second", "existing zero must not be imported again")
        imports = imports + 1
        return 7
    end)
    assert_value(imports, 1, "only missing records are recovered")
    assert_value(counts.first, 0, "existing zero is preserved")
    purchases.record_purchase(key, "first")
    purchases.record_purchase(key, "first")
    package.loaded[name] = nil
    purchases = core:load_global_script(name)
    counts = purchases.get_or_import(key, records, function() error("saved history must not be imported again") end)
    assert_value(counts.first, 2, "consecutive purchases survive module reload")
    assert_value(counts.second, 7, "other rituals keep independent counts")

    local other = "test_purchase_store_faction_two"
    purchases.record_purchase(other, "first")
    local other_counts = purchases.get_or_import(other, records, function(record)
        assert_value(record.key, "second", "purchase before initialization must be retained")
        return 0
    end)
    assert_value(other_counts.first, 1, "first purchase does not require prior import")
    assert_value(saved[key].first, 2, "another faction's purchase must remain independent")
end

function scenarios.logger_uses_mod_id()
    local text = ""
    local metadata = assert(loadfile("build/generated/metadata.lua"))()
    local logger_env = {
        core = {load_global_script = function() return metadata end},
        cm = {get_saved_value = function() return true end},
        get_timestamp = function() return "test-time" end,
        io = {open = function(path, mode)
            assert_value(path, metadata.log_file, "keep the existing log destination")
            assert_value(mode, "a", "append to existing logs")
            return {
                write = function(_, value) text = text .. value end,
                flush = function() end,
                close = function() end,
            }
        end},
    }
    setmetatable(logger_env, {__index = env})
    local logger = load_in_env("src/script/campaign/capacity_cost_control/utils/logger.lua", logger_env)
    logger.write("test", "message")
    assert_value(text, "test-time | [tww3_mod_capacity_cost_control] | test: message\n", "mod_id preserves the log prefix")
end

function scenarios.mct_external_links()
    local listeners, contexts = {}, {}
    local buttons, original_populates = {}, 0
    local holder = {Layout = function() end}
    local page = {_sidebar = {}}
    local link_env = {
        common = {set_context_value = function(key, value) contexts[key] = value end},
        cco = function(kind, key)
            assert_value(kind, "CcoScriptObject", "bind script context to native callback")
            return {key = key, url = contexts[key]}
        end,
        core = {
            remove_listener = function(_, name) listeners[name] = nil end,
            get_or_create_component = function(_, id, template, parent)
                assert_value(template, "ui/tww3_mod_capacity_cost_control/icon_link", "use native icon callback")
                assert(parent == holder)
                local button = {id = id, SetImagePath = function() end, SetTooltipText = function() end, Resize = function() end}
                function button:SetContextObject(context) self.context = context end
                buttons[id] = button
                return button
            end,
        },
        find_uicomponent = function(parent, key)
            if parent == page._sidebar then
                assert_value(key, "buttons_holder", "find native sidebar holder")
                return holder
            end
            assert(parent == holder)
            return buttons[key]
        end,
    }
    setmetatable(link_env, {__index = env})
    local mod = {
        get_main_page = function() return page end,
        get_github_link = function() return "https://github.com/FlanChanXwO/tww3_mod_capacity_cost_control" end,
        get_workshop_link = function() return "https://steamcommunity.com/sharedfiles/filedetails/?id=3821170924" end,
    }
    page.populate_sidebar = function()
        original_populates = original_populates + 1
        buttons = {}
        for _, key in ipairs({"github", "workshop"}) do
            local button = {}
            function button:Destroy() self.destroyed = true end
            buttons["button_" .. key] = button
            listeners[key .. "_button_clicked"] = {callback = function() error("old command route") end}
        end
    end
    local links = assert(loadfile("src/script/mct/capacity_cost_control/links.lua", "t", link_env))()
    links.apply(mod, nil, link_env)
    links.apply(mod, nil, link_env)
    for _ = 1, 2 do
        page:populate_sidebar()
        for _, key in ipairs({"github", "workshop"}) do
            local id = "tww3_mod_capacity_cost_control_" .. key .. "_link"
            assert(buttons["button_" .. key].destroyed, "replace the old icon")
            local target = key == "github"
                and "https://steamcommunity.com/linkfilter/?u=https%3A%2F%2Fgithub.com%2FFlanChanXwO%2Ftww3_mod_capacity_cost_control"
                or mod:get_workshop_link()
            assert_value(buttons[id].context.url, target, "icons share the action destination policy")
            assert(not listeners[key .. "_button_clicked"], "remove the old Lua command route")
        end
    end
    assert_value(original_populates, 2, "sidebar must not be wrapped twice")
    local empty = {}
    links.configure_option(empty, "", "empty", link_env)
    assert(next(empty) == nil, "empty destinations retain the inactive action")
    local encoded_context
    local encoded_option = {
        ui_create_option = function() return {SetContextObject = function(_, context) encoded_context = context end} end,
    }
    links.configure_option(encoded_option, 'https://github.com/owner/repo?q="x"&v=100%#readme', "encoded", link_env)
    encoded_option:ui_create_option({})
    assert_value(encoded_context.url,
        "https://steamcommunity.com/linkfilter/?u=https%3A%2F%2Fgithub.com%2Fowner%2Frepo%3Fq%3D%22x%22%26v%3D100%25%23readme",
        "escape reserved URL bytes so the confirmation page receives exactly one complete destination")
    local fail_option = {ui_create_option = function() error("engine UI failure") end}
    links.configure_option(fail_option, "https://example.com", "failure", link_env)
    local ok, err = pcall(fail_option.ui_create_option, fail_option, {})
    assert(not ok and string.find(err, "engine UI failure", 1, true), "preserve native UI errors")
end


function scenarios.chaos_dwarfs_free_cost_labels()
    local function node(id, children, ritual_key)
        local result = {_children = children or {}, text = "99"}
        function result:Id() return id end
        function result:Visible() return true end
        function result:ChildCount() return #self._children end
        function result:Find(i) return self._children[i + 1] end
        function result:SetStateText(value) self.text = value end
        function result:GetContextObject(kind)
            if kind == "CcoCampaignRitual" and ritual_key then
                return {Call = function(_, expression)
                    assert_value(expression, "RitualContext.Key", "read the native ritual context")
                    return ritual_key
                end}
            end
        end
        return result
    end
    -- 原版 hellforge_panel_unit_caps_tab.twui.xml 的价格默认 99；零支出没有 transaction 来改写文字。
    local free, unrelated, progression = node("template_cost"), node("template_cost"), node("progression_cost")
    local row = node("template_unit_entries", {free, progression}, ritual_keys[1])
    local panel = node("hellforge_panel_main", {row, node("other", {unrelated}, "other_ritual")})
    ui_root = {_panel = panel}
    options.chaos_dwarfs_base_cost_percent = "0"
    boot()
    fire("PanelOpenedCampaign", {string = "hellforge_panel_main"}); flush_callbacks()
    assert_value(free.text, "0", "free capacity displays zero instead of the native placeholder")
    assert_value(unrelated.text, "99", "other rituals retain native text")
    assert_value(progression.text, "99", "manufactory progression is not a capacity price")
    for opening = 1, 2 do
        free.text = "99"
        fire("PanelOpenedCampaign", {string = "hellforge_panel_main"}); flush_callbacks()
        assert_value(free.text, "0", "reopening resets the native zero-cost placeholder")
    end
    purchase(ritual_keys[1]); free.text = "99"; flush_callbacks()
    assert_value(free.text, "0", "purchase refresh retains zero label")
    assert_value(get_value(cost_key, ritual_keys[1] .. "_cost_mod"), -100, "actual purchase remains free")
    for _, value in ipairs({"100", "1000"}) do
        options.chaos_dwarfs_base_cost_percent = value
        free.text = "250" -- 非零交易仍由原版 ContextTextLabel 更新。
        fire("MctOptionSettingFinalized", {mod = function() return mct_mod end}); flush_callbacks()
        assert_value(free.text, "250", "paid prices remain under native control")
    end
    options.chaos_dwarfs_base_cost_percent = "0"
    fire("MctOptionSettingFinalized", {mod = function() return mct_mod end}); flush_callbacks()
    assert_value(free.text, "0", "changing to free updates an already open panel")
    options.chaos_dwarfs_enabled = false
    free.text = "100"
    fire("MctOptionSettingFinalized", {mod = function() return mct_mod end}); flush_callbacks()
    fire("PanelOpenedCampaign", {string = "hellforge_panel_main"}); flush_callbacks()
    assert_value(free.text, "100", "disabled overrides retain native display")
    options.chaos_dwarfs_enabled = true
    local_faction_key = "another_faction"
    fire("MctOptionSettingFinalized", {mod = function() return mct_mod end}); flush_callbacks()
    assert_value(free.text, "100", "other local factions retain native display")
end

function scenarios.base_cost_chaos_dwarfs()
    boot()
    local function change(percent, mode, enabled)
        options.chaos_dwarfs_base_cost_percent = percent
        options.chaos_dwarfs_mode, options.chaos_dwarfs_enabled = mode or "medium", enabled ~= false
        fire("MctOptionSettingFinalized", {mod = function() return mct_mod end}); flush_callbacks()
    end
    local effect = ritual_keys[1] .. "_cost_mod"
    for _, percent in ipairs({0, 100, 1000, 12.5}) do
        change(tostring(percent))
        local count = get_value(cap_key, ritual_keys[1])
        assert_value(get_value(cost_key, effect), (100 + count * 10) * percent / 100 - 100, "CHD base scales existing cost")
        purchase(ritual_keys[1])
        assert_value(get_value(cost_key, effect), (100 + (count + 1) * 10) * percent / 100 - 100, "CHD purchases retain base multiplier")
        assert_value(get_value(cap_key, ritual_keys[1]), count + 1, "free purchases retain capacity history")
    end
    change("0", "custom")
    options.chaos_dwarfs_custom = "1000"
    fire("MctOptionSettingFinalized", {mod = function() return mct_mod end}); flush_callbacks()
    purchase(ritual_keys[1])
    assert_value(get_value(cost_key, effect), -100, "growth cannot undo free cost")
    hellforge.unit_ritual_cost_mod_increment = 37
    change("0", "medium", false)
    assert_value(get_value(cost_key, effect), get_value(cap_key, ritual_keys[1]) * 37, "disable restores current vanilla increment")
    purchase(ritual_keys[1])
    assert_value(get_value(cost_key, effect), get_value(cap_key, ritual_keys[1]) * 37, "disabled purchases use current vanilla")
end

function scenarios.base_cost_nagash()
    local definition = core:load_global_script("capacity_cost_control.shared.generated_data").nagash
    local record, uses = definition.rituals[28], 3
    options.nagash_enabled, options.nagash_mode = true, "medium"
    extra_factions[definition.faction_key] = {
        name=function() return definition.faction_key end, is_human=function() return true end,
        is_null_interface=function() return false end,
        has_effect_bundle=function(_, key) return bundles[key] ~= nil end,
        rituals=function() return {get_tracked_cost_uses=function() return uses end} end,
    }
    boot()
    for _, percent in ipairs({0,100,1000,12.5}) do
        options.nagash_base_cost_percent=tostring(percent)
        fire("MctOptionSettingFinalized", {mod=function() return mct_mod end}); flush_callbacks()
        local vanilla=math.floor(record.base_cost*(1+record.vanilla_rate*uses))
        assert_value(math.floor(vanilla*(1+get_value(definition.bundle_key,record.effect_key)/100)),
            math.floor(record.base_cost*(100+10*uses)*percent/10000), "Nagash scaled cost")
        uses=uses+1
    end
    options.nagash_enabled=false
    fire("MctOptionSettingFinalized", {mod=function() return mct_mod end}); flush_callbacks()
    assert(bundles[definition.bundle_key]==nil,"disabled Nagash removes multiplier")
end

function scenarios.base_cost_amethyst()
    local definition, _, stock, cost, buy, change = amethyst_setup(true, false)
    for _, percent in ipairs({0,100,1000,12.5}) do
        options.amethyst_base_cost_percent=tostring(percent)
        change("no_scaling",true)
        for i,record in ipairs(definition.rituals) do
            assert_value(cost(i), math.floor(record.base_cost*percent/100), "Amethyst base multiplier")
            buy(i)
            assert_value(cost(i), math.floor(record.base_cost*percent/100), "Amethyst next purchase")
        end
    end
    options.amethyst_base_cost_percent="0"
    change("custom",true,"1000"); buy(1)
    assert_value(cost(1),0,"free Amethyst ignores growth")
    assert_value(stock[definition.rituals[1].key],17,"all purchases add stock")
    change("no_scaling",false)
    assert(cost(1)>0,"disable restores Amethyst cost")
end

function scenarios.base_cost_bhashiva()
    local definition, _, capacity, cost, buy, change = bhashiva_setup(true,false,false,true,false)
    for _, percent in ipairs({0,100,1000,12.5}) do
        options.bhashiva_base_cost_percent=tostring(percent)
        change("no_scaling",true)
        for i,record in ipairs(definition.rituals) do
            assert_value(cost(i),math.floor(record.base_cost*percent/100),"Shang-Yang scaled cost")
            buy(i)
            assert_value(cost(i),math.floor(record.base_cost*percent/100),"Shang-Yang next purchase")
        end
    end
    options.bhashiva_base_cost_percent="0"
    change("custom",true,"1000"); buy(1)
    assert_value(cost(1),0,"free army capacity ignores growth")
    assert_value(capacity[definition.rituals[1].key],17,"army purchases add capacity")
    change("no_scaling",false)
    assert(cost(1)>0,"disable restores Shang-Yang cost")
end

function scenarios.percent_settings()
    local config=core:load_global_script("capacity_cost_control.config.settings")
    assert_value(config.resolve_base_multiplier({enabled=true}),1,"missing setting uses 100%")
    for _,bad in ipairs({-1,math.huge,-math.huge,0/0,"bad"}) do
        assert(config.resolve_rate({enabled=true,mode="medium",base_cost_percent=bad})==nil,"invalid base percentage disables override")
    end
    assert_value(config.resolve_base_multiplier({base_cost_percent="0"}),0,"zero multiplier")
    assert_value(config.resolve_base_multiplier({base_cost_percent="12.5"}),0.125,"fractional multiplier")
    assert_value(config.default_settings().nagash.necromancy_progress_percent,100,"default progress")
end

assert(scenarios[arg[1]], "Unknown scenario")()
print("PASS " .. arg[1])
