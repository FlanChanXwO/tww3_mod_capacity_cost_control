-- 在真实原版累计回调上验证费用代理，避免重写奖励算法的测试桩掩盖重复累计。
local data=dofile("build/generated/generated_data.lua").nagash
local record=data.rituals[1]
local lookup={}
for _,item in ipairs(data.rituals) do lookup[item.key]=item end
local options={nagash_enabled=true,nagash_mode="no_scaling",nagash_base_cost_percent="0",nagash_necromancy_progress_percent="100"}
local states,uses,human,faction_key={},0,true,data.faction_key
local applied,native_calls=0,0
local core={event_listeners={}}
function core:add_listener(name,event,condition,callback)
    self.event_listeners[event]=self.event_listeners[event] or {}
    table.insert(self.event_listeners[event],{name=name,condition=condition,callback=callback})
end
local faction={name=function() return faction_key end,is_human=function() return human end,
    rituals=function() return {get_tracked_cost_uses=function() return uses end} end}
local cm={set_script_state=function(_,_,key,value) states[key]=value end,
    model=function() return {shared_states_manager=function() return {get_state_as_float_value=function(_,_,key) return states[key] end} end} end,
    create_new_custom_effect_bundle=function() return {is_null_interface=function() return false end,
        add_effect=function() end,set_duration=function() end} end,
    apply_custom_effect_bundle_to_faction=function() applied=applied+1 end}
local env=setmetatable({core=core,cm=cm,out={design=function(message) error(message) end}},{__index=_G})
local mod={get_option_by_key=function(_,key)
    if options[key]==nil then return nil end
    return {get_finalized_setting=function() return options[key] end}
end}
env.get_mct=function() return {get_mod_by_key=function() return mod end} end
local loaded={}
function core:load_global_script(name)
    if not loaded[name] then
        local path="src/script/campaign/"..name:gsub("%.","/")..".lua"
        if name=="capacity_cost_control.config.metadata" then path="build/generated/metadata.lua" end
        loaded[name]=assert(loadfile(path,"t",env))()
    end
    return loaded[name]
end
local native={necromancy_sigils={
    unit_cap_ritual_prefix="wh3_dlc29_ritual_nag_unit_capacity_",
    state_keys={value="progress",total="target",sigil="sigils"},
    current_value=0,current_target=100,sigils_gained=0,target_growth=100,
    effects={bundle="sigil_bundle",sigil_effect="sigil_effect",scope="faction_to_faction_own_unseen"}}}
local sigils=core:load_global_script("capacity_cost_control.adapters.nagash_sigils")
sigils.install(lookup,data.faction_key) -- 原版还没注册时不拦截，随后可重试。
assert(loadfile("tests/lua/fixtures/nagash_vanilla.lua","t",env))()(native)
local listener=core.event_listeners.RitualAboutToStartEvent[1]
local native_callback=listener.callback
listener.callback=function(context) native_calls=native_calls+1; return native_callback(context) end
sigils.install(lookup,data.faction_key)
local wrapped=listener.callback
sigils.install(lookup,data.faction_key)
assert(wrapped==listener.callback,"do not wrap twice on settings changes")
local function fire(paid,expected,initial,target,key,null)
    states={progress=initial or 0,target=target or 10000,sigils=2}
    local before=native_calls
    local spent={is_null_interface=function() return null==true end,
        absolute_resource_change=function(_,resource)
            assert(resource=="wh3_dlc29_nag_necromantic_energy"); return -paid
        end}
    local ritual={ritual_key=function() return key or record.key end,
        ritual_target=function() return {get_target_expended_resources=function() return spent end} end}
    local context={ritual=function() return ritual end,performing_faction=function() return faction end}
    assert(listener.condition(context))
    listener.callback(context)
    assert(native_calls==before+1,"exactly one native callback per purchase")
    local total=(initial or 0)+expected
    local threshold=target or 10000
    local reward=total>=threshold and 1 or 0
    assert(states.progress==total-reward*threshold,"progress must use selected contribution once")
    assert(states.sigils==2+reward and states.target==threshold+100*reward,"preserve native sigil thresholds")
    assert(spent:absolute_resource_change("wh3_dlc29_nag_necromantic_energy")==-paid,"do not rewrite actual spending")
end
for _,base in ipairs({0,100,1000}) do
    for _,progress in ipairs({0,50,100,1000,12.5}) do
        for _,count in ipairs({0,3,10}) do
            options.nagash_base_cost_percent=tostring(base)
            options.nagash_mode="custom"; options.nagash_custom="1000"
            options.nagash_necromancy_progress_percent=tostring(progress)
            uses=count
            local vanilla=math.floor(record.base_cost*(1+record.vanilla_rate*count))
            fire(base,vanilla*progress/100,0,100000,nil,base==0)
        end
    end
end
options.nagash_necromancy_progress_percent="100"; uses=0
fire(0,120,50,100,nil,true)
options.nagash_necromancy_progress_percent="1000"
fire(0,1200,0,100,nil,true) -- 原版一次回调最多跨过一个门槛。
options.nagash_necromancy_progress_percent="0"
fire(1000,0)
options.nagash_enabled=false; fire(37,37)
options.nagash_enabled=true; human=false; fire(38,38)
human=true; faction_key="other_faction"; fire(39,39)
faction_key=data.faction_key; fire(40,40,0,10000,native.necromancy_sigils.unit_cap_ritual_prefix.."unknown")
local mct=env.get_mct; env.get_mct=false; fire(41,41); env.get_mct=mct
options.nagash_necromancy_progress_percent="-1"; fire(42,42)
assert(applied==2,"only the two threshold crossings should grant sigil effects")
print("PASS nagash_sigils")
