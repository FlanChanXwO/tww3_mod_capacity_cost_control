-- 辅助模块使用独立 loadfile 环境；真实绘制及链接回调必须使用设置入口传入的接口。
local Node={}; Node.__index=Node
function Node:new(key) return setmetatable({key=key,children={},w=1000,h=700},self) end
function Node:Width() return self.w end
function Node:Height() return self.h end
function Node:Resize(w,h) self.w=w; self.h=h end
function Node:Layout() end
function Node:Destroy() self.destroyed=true end
function Node:SetContextObject(value) self.context=value end
for _,name in ipairs({"SetCanResizeHeight","SetCanResizeWidth","SetDockingPoint","SetImagePath","SetTooltipText",
    "SetCurrentStateImageTiled","SetCurrentStateImageMargins"}) do Node[name]=function() end end
local function component(parent,...)
    for _,key in ipairs({...}) do
        if not parent then return nil end
        parent=parent.children[key]
    end
    return parent
end
for _,mode in ipairs({"frontend","campaign"}) do
    local registered,sections,selected,listeners,contexts={},{},{},{},{}
    local painted=0
    local core={}
    function core:get_or_create_component(key,template,parent)
        local node=parent.children[key]
        if not node or node.destroyed then
            node=Node:new(key); parent.children[key]=node
            if template=="ui/groovy/layouts/listview" then
                local clip=Node:new("list_clip"); node.children.list_clip=clip
                clip.children.list_box=Node:new("list_box")
            end
        end
        return node
    end
    function core:add_listener(name,event,condition,callback) listeners[name]={condition=condition,callback=callback} end
    function core:remove_listener(name) listeners[name]=nil end
    local settings_page,main_page={},{}
    main_page.populate_sidebar=function(self)
        self._sidebar=Node:new("sidebar")
        local holder=Node:new("buttons_holder"); self._sidebar.children.buttons_holder=holder
        for _,key in ipairs({"github","workshop"}) do holder.children["button_"..key]=Node:new(key) end
    end
    local mod={set_title=function() end,set_author=function() end,set_description=function() end,
        set_version=function() end,set_workshop_id=function() end,set_github_id=function() end,
        get_first_settings_page=function() return settings_page end,
        get_main_page=function() return main_page end,
        get_section_by_key=function(_,key) return sections[key] end,
        set_positions_for_options=function() end,
        get_github_link=function() return "https://github.com/FlanChanXwO/tww3_mod_capacity_cost_control" end,
        get_workshop_link=function() return "https://steamcommunity.com/sharedfiles/filedetails/?id=3821170924" end}
    settings_page._mod_obj=mod
    function mod:add_new_section(key)
        local section={_options={},set_localised_text=function() end,set_option_sort_function=function() end}
        function section:populate(box)
            painted=painted+1
            for _,option in pairs(self._options) do
                if option.kind=="action" then
                    local button=option:ui_create_option(box)
                    assert(button.context,"link should receive its context in "..mode)
                end
            end
        end
        sections[key]=section; return section
    end
    function mod:add_new_option(key,kind)
        local option={kind=kind,set_text=function() end,set_tooltip_text=function() end,
            set_button_text=function() end,add_dropdown_value=function() end}
        function option:set_assigned_section(section) sections[section]._options[key]=self end
        function option:set_default_value(value) if selected[key]==nil then selected[key]=value end end
        function option:add_validity_test(test) self.validate=test end
        function option:set_callback(callback) self.callback=callback end
        function option:ui_create_option(box) return core:get_or_create_component(key,self:get_uic_template(),box) end
        registered[key]=option; return option
    end
    local runtime={core=core,find_uicomponent=component,
        common={get_context_value=function() return true end,set_context_value=function(key,value) contexts[key]=value end},
        cco=function(_,key) return {url=contexts[key]} end,get_vlog=function() return function() end end,
        get_mct=function() return {register_mod=function() return mod end} end}
    local env=setmetatable(runtime,{__index=_G})
    -- MCT GLib 将入口绑定到 core:get_env()，入口自行 loadfile 的辅助脚本不会继承它。
    local auxiliary=setmetatable(mode=="frontend" and runtime or
        {core=false,find_uicomponent=false,common=false,cco=false,get_vlog=false},{__index=_G})
    env.loadfile=function(path)
        local generated=path:match("/metadata.lua$") or path:match("/i18.lua$")
        local source=generated and ("build/generated/"..path:match("[^/]+$")) or ("src/"..path)
        return loadfile(source,"t",auxiliary)
    end
    assert(loadfile("src/script/mct/settings/tww3_mod_capacity_cost_control_mct.lua","t",env))()
    for _,key in ipairs({"nagash_base_cost_percent","nagash_necromancy_progress_percent","amethyst_base_cost_percent"}) do
        assert(selected[key]=="100",key.." defaults to 100%")
        assert(registered[key].validate("0") and registered[key].validate("12.5"))
        assert(not registered[key].validate("-1") and not registered[key].validate("1e9999"))
    end
    selected.nagash_base_cost_percent="0"
    for opening=1,3 do
        painted=0
        settings_page:populate(Node:new("panel"))
        assert(painted==7,mode.." must render all seven sections on every opening")
        main_page:populate_sidebar()
        local holder=component(main_page._sidebar,"buttons_holder")
        for _,key in ipairs({"github","workshop"}) do
            local id="tww3_mod_capacity_cost_control_"..key.."_link"
            assert(component(holder,id).context.url,"icon context after reopen")
            assert(listeners[id].condition({string=id}))
            listeners[id].callback()
        end
        registered.project_repository.callback()
        assert(selected.nagash_base_cost_percent=="0","reopening must retain settings")
    end
end
print("PASS mct_ui")
