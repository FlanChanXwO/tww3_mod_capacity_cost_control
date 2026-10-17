-- MCT 设置入口，注册五个派系的费用选项、诊断开关和其它设置。
-- 读取常量、项目元数据与双语文本，并将分组交给布局模块展示。
-- MCT 未加载时直接退出；设置文件通过 loadfile 加载数据，不依赖战役入口。
if not get_mct then return end
local mct = get_mct()
-- MCT 不保证 campaign 模块加载环境，固定数据与元数据均通过 loadfile 读取。
local constants = assert(loadfile("script/campaign/capacity_cost_control/config/constants.lua"))()
local metadata = assert(loadfile("script/campaign/capacity_cost_control/config/metadata.lua"))()
local defaults = constants.defaults
local mct_mod = mct:register_mod(metadata.mod_key)
local layout = loadfile("script/mct/capacity_cost_control/layout.lua")
layout = layout and layout() or {}
local project_links = assert(loadfile("script/mct/capacity_cost_control/links.lua"))()

-- MCT 用 loadfile 加载 settings 文件，package.path 可能不含 script/campaign/
-- 所以同样用 loadfile 而非 require 加载 i18 数据。
local i18
local ok, err = pcall(function()
    local fn = loadfile("script/campaign/capacity_cost_control/shared/i18.lua")
    if fn then i18 = fn() end
end)
if not i18 then i18 = { en = {}, zh = {} } end

-- 检测游戏语言：IsLocChinese 是引擎注册的 context command，
-- 简中和繁中环境下返回 true。pcall 防止 MCT 加载时序问题。
local function is_chinese()
    local ok2, result = pcall(common.get_context_value, "IsLocChinese()")
    return ok2 and result == true
end

local L = is_chinese() and i18.zh or i18.en

-- fallback 文案：i18 加载失败时用硬编码英文，确保 MCT 不会因 "no title" 禁用。
local title = L.title or "Unit Capacity Cost Control"
local description = L.description or "Configurable capacity cost scaling for Nagash, Chaos Dwarfs, Bhashiva, Beastmen, and Amethyst units."

mct_mod:set_title(title)
mct_mod:set_author(metadata.author)
mct_mod:set_description(description)
mct_mod:set_version(metadata.version)
mct_mod:set_workshop_id(metadata.workshop_id)
mct_mod:set_github_id(metadata.github_repository:match("github%.com/(.+)$"))

local sections = L.sections or {}
local options = L.options or {}
local dropdown_values = L.dropdown_values or {}
local validation = L.validation or {}

-- 诊断日志开关：玩家在 MCT 面板切换，无需重新构建。
local debug_section = mct_mod:add_new_section("debug")
debug_section:set_localised_text(L.debug and L.debug.section or "Diagnostics")
local debug_opt = mct_mod:add_new_option("debug_logging", "checkbox")
debug_opt:set_assigned_section("debug")
debug_opt:set_text(L.debug and L.debug.text or "Enable diagnostics")
debug_opt:set_tooltip_text(L.debug and L.debug.tooltip or "Writes runtime diagnostics to tww3_mod_capacity_cost_control_log.txt in the game directory.")
debug_opt:set_default_value(defaults.debug_logging)
local links_section = mct_mod:add_new_section("links")
links_section:set_localised_text((L.links and L.links.section) or "Other")
links_section:set_option_sort_function(function()
    return {"project_workshop", "project_repository"}
end)

local function add_faction_section(section_key, prefix)
    local section = mct_mod:add_new_section(section_key)
    section:set_localised_text(sections[section_key] or section_key)

    local enabled = mct_mod:add_new_option(prefix .. "_enabled", "checkbox")
    enabled:set_assigned_section(section_key)
    enabled:set_text(options.enabled and options.enabled.text or "Enable override")
    enabled:set_tooltip_text(options.enabled and options.enabled.tooltip or "")
    enabled:set_default_value(defaults.enabled)

    local mode = mct_mod:add_new_option(prefix .. "_mode", "dropdown")
    mode:set_assigned_section(section_key)
    mode:set_text(options.mode and options.mode.text or "Scaling per purchase")
    for _, key in ipairs(constants.mode_order) do
        local text = dropdown_values[key] or {}
        local rate = constants.preset_rates[key]
        local fallback = rate and (tostring(rate * 100) .. "%") or "Custom"
        mode:add_dropdown_value(key, text.text or fallback, text.tooltip or "", key == defaults.mode)
    end
    mode:set_default_value(defaults.mode)

    local custom = mct_mod:add_new_option(prefix .. "_custom", "text_input")
    custom:set_assigned_section(section_key)
    custom:set_text(options.custom and options.custom.text or "Custom scaling (%)")
    custom:set_tooltip_text(options.custom and options.custom.tooltip or "")
    custom:set_default_value(tostring(defaults.custom_percent))
    local invalid_msg = validation.custom_invalid or "Enter a finite number greater than 0."
    custom:add_validity_test(function(text)
        local value = tonumber(text)
        -- 避开 WH3 缺失的 math.huge，同时拒绝无穷和 NaN。
        if not value or value <= 0 or value - value ~= 0 then
            return false, invalid_msg
        end
        return true
    end)
end

local function add_link_option(key, url, text, tooltip)
    local option = mct_mod:add_new_option(key, "action")
    option:set_assigned_section("links")
    option:set_text(text or key)
    if option.set_button_text then option:set_button_text(text or key) end
    if option.set_tooltip_text then option:set_tooltip_text(tooltip or "") end
    if url and url ~= "" then
        project_links.configure_option(option, url, key)
    end
end

for _, prefix in ipairs(constants.faction_order) do
    add_faction_section(prefix, prefix)
end

local links = L.links or {}
local repository = metadata.github_repository or ""
local workshop_id = metadata.workshop_id or ""
add_link_option("project_workshop", workshop_id ~= "" and ("https://steamcommunity.com/sharedfiles/filedetails/?id=" .. workshop_id) or "", links.workshop or "Steam Workshop", links.workshop_tooltip)
add_link_option("project_repository", repository, links.repository or "Contribute", links.repository_tooltip)
project_links.apply(mct_mod, links.repository_tooltip)

if layout.apply then
    layout.apply(mct_mod, constants.faction_order, constants.other_sections)
end
