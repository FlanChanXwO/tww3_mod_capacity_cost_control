-- 旧档迁移模块，将旧模组的设置与购买次数导入当前身份。
-- 读取 MCT 存档注册表和三类旧计数，只补充新版缺失的记录。
-- 保留旧数据与新版零值，不修改容量、库存或全局 MCT 配置文件。
local constants = core:load_global_script("capacity_cost_control.config.constants")
local metadata = core:load_global_script("capacity_cost_control.config.metadata")
local logger = core:load_global_script("capacity_cost_control.utils.logger")
local migration = {}
local pending_settings = {}
local initialized = false

function migration.initialize()
    if initialized then return end
    initialized = true
    cm:add_loading_game_callback(function(context)
        local registry = cm:load_named_value("mct_registry", {}, context)
        local mods = registry.saved_mods or {}
        local old = mods[constants.legacy.mod_key]
        local current = mods[metadata.mod_key]
        local current_options = current and current.options or {}
        pending_settings = {}
        for key, data in pairs(old and old.options or {}) do
            if current_options[key] == nil and data.setting ~= nil then
                pending_settings[key] = data.setting
            end
        end
    end)
end

function migration.apply_settings()
    local mct = type(get_mct) == "function" and get_mct()
    local mod = mct and mct:get_mod_by_key(metadata.mod_key)
    if not mod then return end
    -- 等待 MCT 完成自己的加载，再使用它的存档恢复接口；不触发逐项刷新。
    for key, value in pairs(pending_settings) do
        local option = mod:get_option_by_key(key)
        if option then
            option:set_finalized_setting(value, true)
            logger.write("migration", "MCT setting imported: " .. key)
        end
    end
    pending_settings = {}
end

function migration.read_purchases(save_key)
    local counts = cm:get_saved_value(save_key) or {}
    for current, old in pairs(constants.legacy.purchase_factions) do
        local prefix = metadata.mod_key .. "_" .. current .. "_purchases_"
        if string.sub(save_key, 1, #prefix) == prefix then
            local old_key = constants.legacy.purchase_prefix .. old .. "_purchases_" .. string.sub(save_key, #prefix + 1)
            local old_counts = cm:get_saved_value(old_key)
            if type(old_counts) == "table" then
                for key, value in pairs(old_counts) do
                    if counts[key] == nil and type(value) == "number" and value >= 0
                        and value - value == 0 and value == math.floor(value) then
                        counts[key] = value
                        logger.write("migration", "purchase count imported: " .. key .. "=" .. value)
                    end
                end
            end
            break
        end
    end
    return counts
end

return migration
