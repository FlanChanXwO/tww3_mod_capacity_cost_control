-- MCT 页面布局模块，将派系设置与其它设置固定分配到左右两列。
-- 替换本模组设置页的 populate，复用原生分组、控件和滚动容器。
-- 仅调整当前设置页的展示，不负责选项注册、保存或费用计算。
local layout = {}

function layout.apply(mct_mod, left_sections, right_sections, runtime)
    local core, find_uicomponent = runtime.core, runtime.find_uicomponent
    local page = mct_mod:get_first_settings_page()
    if not page then return end
    if page._tww3_fixed_layout then return end
    page._tww3_fixed_layout = true
    page.num_columns = 2

    -- SettingsPage 没有列分配接口；复用原生 populate 流程，只固定本页两组 section。
    page.populate = function(self, panel)
        local groups = {left_sections, right_sections}
        local mod = self._mod_obj
        mod:set_positions_for_options()

        for column_num = 1, 2 do
            local column = core:get_or_create_component("settings_column_" .. column_num,
                "ui/groovy/layouts/listview", panel)
            column:SetCanResizeHeight(true)
            column:SetCanResizeWidth(true)
            column:Resize(panel:Width() / 2, panel:Height(), false)
            column:SetCanResizeWidth(false)
            column:SetDockingPoint(column_num == 1 and 1 or 3)
        end

        local divider = 0
        for column_num, keys in ipairs(groups) do
            local column = find_uicomponent(panel, "settings_column_" .. column_num)
            local box = find_uicomponent(column, "list_clip", "list_box")
            local sections = {}
            for _, key in ipairs(keys) do
                sections[#sections + 1] = mod:get_section_by_key(key)
            end
            for index, section in ipairs(sections) do
                if section and section._options and next(section._options) then
                    section:populate(box, column:Width() * 0.95, column:Height() * 0.12)
                    if index < #sections then
                        divider = divider + 1
                        local holder = core:get_or_create_component("divider_holder_" .. divider,
                            "ui/campaign ui/script_dummy", box)
                        holder:Resize(box:Width(), 13)
                        local line = core:get_or_create_component("divider", "ui/groovy/image", holder)
                        line:SetDockingPoint(5)
                        line:Resize(holder:Width() - 10, 13)
                        line:SetImagePath("ui/skins/default/parchment_divider_length.png", 0)
                        line:SetCurrentStateImageTiled(0, true)
                        line:SetCurrentStateImageMargins(0, 2, 0, 2, 0)
                    end
                end
            end
            local clip = find_uicomponent(column, "list_clip")
            box:Layout()
            clip:Resize(column:Width(), column:Height())
            box:Resize(column:Width(), column:Height())
        end
        if self.OnPopulate then self:OnPopulate(panel) end
    end
end

return layout
