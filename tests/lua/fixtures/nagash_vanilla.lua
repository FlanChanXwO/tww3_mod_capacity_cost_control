-- 从 2026-10-20 本机原版 wh3_dlc29_nag_black_pyramid.lua 提取，保留单次门槛结算。
return function(self)
	core:add_listener(
		"BlackPyramid_RitualCompletedEvent_UnitCapSigils",
		"RitualAboutToStartEvent",
		function(context)
			if string.find(context:ritual():ritual_key(), self.necromancy_sigils.unit_cap_ritual_prefix) then
				return true
			end

			return false
		end,
		function(context)
			local ritual = context:ritual()
			local faction = context:performing_faction()
			
			local ritual_target_expended_resources = ritual:ritual_target():get_target_expended_resources()
			if ritual_target_expended_resources:is_null_interface() == false then
				local ritual_cost = ritual_target_expended_resources:absolute_resource_change("wh3_dlc29_nag_necromantic_energy")
				local current_value = cm:model():shared_states_manager():get_state_as_float_value(faction, self.necromancy_sigils.state_keys.value) or self.necromancy_sigils.current_value
				local current_total = cm:model():shared_states_manager():get_state_as_float_value(faction, self.necromancy_sigils.state_keys.total) or self.necromancy_sigils.current_target
				local current_sigils = cm:model():shared_states_manager():get_state_as_float_value(faction, self.necromancy_sigils.state_keys.sigil) or self.necromancy_sigils.sigils_gained

				current_value = current_value - ritual_cost	-- The ritual cost is negative, so we subtract it to add to the current value.

				if current_value >= current_total then
					current_sigils = current_sigils + 1
					current_value = current_value - current_total
					current_total = current_total + self.necromancy_sigils.target_growth

					cm:set_script_state(faction, self.necromancy_sigils.state_keys.sigil, current_sigils)
					cm:set_script_state(faction, self.necromancy_sigils.state_keys.value, current_value)
					cm:set_script_state(faction, self.necromancy_sigils.state_keys.total, current_total)

					local bundle = cm:create_new_custom_effect_bundle(self.necromancy_sigils.effects.bundle)

					if bundle and not bundle:is_null_interface() then
						bundle:add_effect(self.necromancy_sigils.effects.sigil_effect, self.necromancy_sigils.effects.scope, current_sigils)
						bundle:set_duration(0)

						cm:apply_custom_effect_bundle_to_faction(bundle, faction)
					end
				else
					cm:set_script_state(faction, self.necromancy_sigils.state_keys.value, current_value)
				end
			else
				out.design("FAILED TO FIND RESOURCE COST FOR: "..ritual:ritual_key())
			end
		end,
		true
	)
end
