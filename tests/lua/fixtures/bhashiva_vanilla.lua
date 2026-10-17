-- 从本机原版 wh3_cp1_tiger_mercenaries.lua 提取军队容量监听器，保留其计数依赖。
-- 为上阳诸军回归重放原版军队解锁与容量更新，验证两种监听执行顺序。
-- 监听器主体保留提取内容，仅由测试环境提供所需引擎对象和事件。
return function(self)
	core:add_listener(
		"ArmyCapacityUpgraded",
		"RitualCompletedEvent",
		function(context)
			local faction = context:performing_faction()
			if faction:name() ~= self.config.faction_key then
				return false
			end
			return context:ritual():ritual_key() == self.config.army_capacity_ritual_key
		end,
		function(context)
			local faction = context:performing_faction()
			local ritual = context:ritual():ritual_key()
			local num_uses = faction:rituals():get_tracked_cost_uses(ritual)
			if num_uses < 2 then
				return
			end
			local bundle = self:get_faction_bundle_by_key(faction, self.config.army_capacity_effect_bundle_key)
			local bundle_copy = bundle:clone_and_create_custom_effect_bundle(cm:model())
			local success = bundle_copy:set_effect_value_by_key(self.config.army_capacity_effect_key, num_uses)
			if success then
				cm:apply_custom_effect_bundle_to_faction(bundle_copy, faction)
			end
		end,
		true
	);
end
