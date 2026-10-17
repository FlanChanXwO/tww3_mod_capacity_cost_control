-- 紫晶军械库诊断模块，读取面板中的仪式标识与引擎计算费用。
-- 仅在诊断开启且属于本地紫晶派系时，延迟遍历可见面板并记录日志。
-- 只读取界面上下文，费用修正与购买计数由适配器负责。
local diagnostics = {}
local constants = core:load_global_script("capacity_cost_control.config.constants")
local metadata = core:load_global_script("capacity_cost_control.config.metadata")
local logger = core:load_global_script("capacity_cost_control.utils.logger")

function diagnostics.log_amethyst(adapter, definition)
    if not cm or cm:get_saved_value("tww3_mod_capacity_cost_control_debug_logging") ~= true
        or cm:get_local_faction_name() ~= definition.faction_key then return end
    cm:callback(function()
        local ok, err = pcall(function()
            local panel = find_uicomponent(core:get_ui_root(), constants.amethyst.panel_key)
            if not panel or not panel:Visible() then return end
            local seen = {}
            local function visit(component, ritual)
                ritual = component:GetContextObject("CcoCampaignRitual") or ritual
                local key = ritual and ritual:Call("RitualContext.Key")
                if adapter:handles_ritual(key) and not seen[key] then
                    seen[key] = true
                    logger.write("amethyst: " .. key .. " engine_cost=" .. tostring(ritual:Call("ResourceTransactionContext.PooledResourceTransactionList[0].AbsoluteValue")))
                end
                for i = 0, component:ChildCount() - 1 do visit(UIComponent(component:Find(i)), ritual) end
            end
            visit(panel)
        end)
        if not ok then logger.write("amethyst: diagnostic_error=" .. tostring(err)) end
    end, 0.1)
end

return diagnostics
