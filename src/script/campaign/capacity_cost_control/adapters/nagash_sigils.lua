-- 只替换原版容量购买监听器读取的本次支出，门槛、奖励和状态写入仍由原版处理。
local config = core:load_global_script("capacity_cost_control.config.settings")
local defaults = core:load_global_script("capacity_cost_control.config.constants").defaults
local sigils = {}
local listener_name = "BlackPyramid_RitualCompletedEvent_UnitCapSigils"
local resource_key = "wh3_dlc29_nag_necromantic_energy"
local installed = false

function sigils.install(rituals, faction_key)
    if installed then return end
    -- 已核对原版 lib_core 的监听器记录结构；首次刷新发生在原版初始化之后。
    for _, listener in ipairs(core.event_listeners and core.event_listeners.RitualAboutToStartEvent or {}) do
        if listener.name == listener_name and not listener.to_remove then
            local original = listener.callback
            listener.callback = function(context)
                local faction = context:performing_faction()
                local ritual = context:ritual()
                local record = rituals[ritual:ritual_key()]
                local mct = type(get_mct) == "function" and get_mct()
                local setting = config.read_faction_setting("nagash")
                local multiplier = config.resolve_percent(setting.necromancy_progress_percent,
                    defaults.necromancy_progress_percent)
                if not record or faction:name() ~= faction_key or not faction:is_human()
                    or not mct or not mct:get_mod_by_key(config.mod_key)
                    or config.resolve_rate(setting) == nil or multiplier == nil then
                    return original(context)
                end

                local uses = math.max(0, faction:rituals():get_tracked_cost_uses(record.key) or 0)
                local vanilla_cost = math.floor(record.base_cost * (1 + record.vanilla_rate
                    * math.min(uses, record.max_increases)))
                local contribution = vanilla_cost * multiplier
                local target = ritual:ritual_target()
                local spent = target:get_target_expended_resources()
                if not spent:is_null_interface() and spent:absolute_resource_change(resource_key) == -contribution then
                    return original(context)
                end

                -- 免费购买可能没有支出接口；为原版提供本次等价支出，不更改真实扣款。
                local progress_resources = {
                    is_null_interface = function() return false end,
                    absolute_resource_change = function(_, key)
                        if key == resource_key then return -contribution end
                        return spent:absolute_resource_change(key)
                    end,
                }
                original({
                    performing_faction = function() return faction end,
                    ritual = function() return {
                        ritual_key = function() return record.key end,
                        ritual_target = function() return {
                            get_target_expended_resources = function() return progress_resources end,
                        } end,
                    } end,
                })
            end
            installed = true
            return
        end
    end
end

return sigils
