-- 原版 wh2_dlc17_bst_ruination_progression.lua，2026-10-16 本机核对。
-- 为野兽人回归提供原版容量费用增长函数，作为独立的复利行为参照。
-- 函数主体保留原版实现，由测试环境提供 Ruination、cm 和 bundle 对象。
function Ruination:modify_ritual_cap_cost(ritual_key, faction_interface, bundle_key, multiplier)
	local current_bundle = Ruination:get_faction_bundle_by_key(faction_interface, bundle_key)
	local effect_to_modify_key = ritual_key..self.cost_mod_effect_suffix
	local effects_to_new_values = {}

	if current_bundle then
		local active_effects = current_bundle:effects()
		for i = 0, active_effects:num_items() - 1 do
			local active_effect = active_effects:item_at(i)
			local old_value = active_effect:value()
			local active_effect_key = active_effect:key()
			if active_effect_key == effect_to_modify_key then
				if old_value == 0 then
					effects_to_new_values[active_effect_key] = old_value + multiplier
				else
					effects_to_new_values[active_effect_key] = old_value + (old_value/10 + multiplier)
				end
			else
				effects_to_new_values[active_effect_key] = old_value
			end
		end
	end

	local bundle_to_apply = cm:create_new_custom_effect_bundle(bundle_key)
	local new_effects = bundle_to_apply:effects()

	for i = 0, new_effects:num_items() - 1 do
		local new_effect = new_effects:item_at(i)
		local new_effect_key = new_effect:key()

		if effects_to_new_values[new_effect_key] then
			bundle_to_apply:set_effect_value(new_effect, effects_to_new_values[new_effect_key])
		end
	end

	bundle_to_apply:set_duration(0)

	cm:apply_custom_effect_bundle_to_faction(bundle_to_apply,faction_interface)

end

function Ruination:get_faction_bundle_by_key(faction_interface, bundle_key)
	local effect_bundle_list = faction_interface:effect_bundles()

	for i = 0, effect_bundle_list:num_items() - 1 do
		local effect_bundle = effect_bundle_list:item_at(i)

		if effect_bundle:key() == bundle_key then
			return effect_bundle
		end
	end
end

