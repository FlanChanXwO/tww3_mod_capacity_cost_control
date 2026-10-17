-- 由原生控件执行外链命令，Lua 只绑定目标与诊断监听。
local links = {}
local log = get_vlog("[capacity_cost_control.links]")
local template_root = "ui/tww3_mod_capacity_cost_control/"

local function bind(button, url, key)
    if not url or url == "" then return end
    local target = url
    if url:match("^https://github%.com/") then
        -- shortcut: 引擎限制直达外站；待有受支持的注册接口后移除 Steam 确认页。
        target = "https://steamcommunity.com/linkfilter/?u=" .. url:gsub("([^%w%-%._~])", function(char)
            return string.format("%%%02X", string.byte(char))
        end)
    end
    common.set_context_value(key, target)
    button:SetContextObject(cco("CcoScriptObject", key))
    log("native link bound: " .. key .. " -> " .. target)
end

function links.configure_option(option, url, key)
    if not url or url == "" then return end
    option.get_uic_template = function() return template_root .. "action_link" end
    local create_option = option.ui_create_option
    option.ui_create_option = function(self, parent)
        local button = create_option(self, parent)
        bind(button, url, "tww3_mod_capacity_cost_control_" .. key)
        return button
    end
    option:set_callback(function()
        log("native action clicked: " .. key .. " -> " .. url .. "; browser opening is not confirmed")
    end)
end

function links.apply(mct_mod, repository_tooltip)
    local page = mct_mod:get_main_page()
    if page._tww3_external_links then return end
    page._tww3_external_links = true
    local populate_sidebar = page.populate_sidebar
    page.populate_sidebar = function(self)
        populate_sidebar(self)
        local holder = find_uicomponent(self._sidebar, "buttons_holder")
        for _, key in ipairs({"github", "workshop"}) do
            local button = find_uicomponent(holder, "button_" .. key)
            if button then
                core:remove_listener(key .. "_button_clicked")
                button:Destroy()
                local id = "tww3_mod_capacity_cost_control_" .. key .. "_link"
                button = core:get_or_create_component(id, template_root .. "icon_link", holder)
                button:SetImagePath("ui/mct/icons/" .. key .. ".png")
                button:SetTooltipText(key == "github" and repository_tooltip or mct_mod["get_" .. key .. "_link"](mct_mod), true)
                button:Resize(32, 32)
                bind(button, mct_mod["get_" .. key .. "_link"](mct_mod), id)
                core:remove_listener(id)
                core:add_listener(id, "ComponentLClickUp",
                    function(context) return context.string == id end,
                    function() log("native icon clicked: " .. key .. "; browser opening is not confirmed") end, true)
            end
        end
        holder:Layout()
    end
end

return links
