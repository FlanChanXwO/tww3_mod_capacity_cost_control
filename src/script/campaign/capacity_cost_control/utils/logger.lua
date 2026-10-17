-- 运行时日志模块，按诊断开关向元数据指定的文件追加记录。
-- 统一添加引擎时间、模组标识和事件来源，供费用与历史问题排查。
-- 默认关闭；文件打开失败时返回，不阻断调用方的费用处理。
local metadata = core:load_global_script("capacity_cost_control.config.metadata")
local logger = {}

local function timestamp()
    if type(get_timestamp) == "function" then
        local ok, value = pcall(get_timestamp)
        if ok and value then return tostring(value) end
    end
    return "unknown-time"
end

function logger.write(source, message)
    if not cm or cm:get_saved_value("tww3_mod_capacity_cost_control_debug_logging") ~= true then return end
    if message == nil then
        message = source
        source = "runtime"
    end
    local ok, file = pcall(io.open, metadata.log_file, "a")
    if not ok or not file then return end
    file:write(timestamp() .. " | [" .. metadata.technical_name .. "] | " .. tostring(source) .. ": " .. tostring(message) .. "\n")
    file:flush()
    file:close()
end

return logger
