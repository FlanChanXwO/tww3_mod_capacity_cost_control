-- 购买记录存储模块，按既有存档键管理各派系的仪式购买次数。
-- 仅为缺失记录调用适配器的历史恢复函数，并保存成功购买的增量。
-- 不判断购买是否成功或修改容量；调用方负责事件过滤与恢复依据。
local migration = core:load_global_script("capacity_cost_control.store.migration")
local purchases = {}

function purchases.get_or_import(save_key, records, recover_count)
    local counts = migration.read_purchases(save_key)
    for _, record in ipairs(records) do
        if counts[record.key] == nil then
            counts[record.key] = recover_count(record)
        end
    end
    cm:set_saved_value(save_key, counts)
    return counts
end

function purchases.record_purchase(save_key, ritual_key)
    local counts = migration.read_purchases(save_key)
    counts[ritual_key] = (counts[ritual_key] or 0) + 1
    cm:set_saved_value(save_key, counts)
end

return purchases
