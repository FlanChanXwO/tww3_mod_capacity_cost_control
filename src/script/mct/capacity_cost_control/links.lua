-- 由原生控件执行外链命令，Lua 只绑定目标。
local links = {}
local template_root = "ui/tww3_mod_capacity_cost_control/"

local function bind(button, url, key, runtime)
    local common, cco = runtime.common, runtime.cco
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
end

function links.configure_option(option, url, key, runtime)
    if not url or url == "" then return end
    option.get_uic_template = function() return template_root .. "action_link" end
    local create_option = option.ui_create_option
    option.ui_create_option = function(self, parent)
        local button = create_option(self, parent)
        bind(button, url, "tww3_mod_capacity_cost_control_" .. key, runtime)
        return button
    end
end

function links.apply(mct_mod, repository_tooltip, runtime)
    local core, find_uicomponent = runtime.core, runtime.find_uicomponent
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
                bind(button, mct_mod["get_" .. key .. "_link"](mct_mod), id, runtime)
            end
        end
        holder:Layout()
    end
end

return links
