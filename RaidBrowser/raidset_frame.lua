RaidBrowser.gui.raidset = {};

local frame = CreateFrame("Frame", "RaidBrowserRaidSetMenu", LFRBrowseFrame, "UIDropDownMenuTemplate")
UIDropDownMenu_SetWidth(RaidBrowserRaidSetMenu, 150)
frame:SetWidth(90);

---@type 'Active'|'Primary'|'Secondary'|'Both'|nil
local current_selection = nil;

-- Created further below; declared here so initialize() can reference it.
local short_spec_check

-- Formats a raidset as "<gs> <spec>". GearScore is optional, so gs may be nil.
---@param spec string?
---@param gs number|string|nil
---@return string?
local function format_raidset(spec, gs)
	if not spec then return nil end
	if gs then return gs .. ' ' .. spec end
	return spec
end

---@param selection any
---@return 'Active'|'Primary'|'Secondary'|'Both'
local function normalize_selection(selection)
	if selection == 'Active' or selection == 'Primary' or selection == 'Secondary' or selection == 'Both' then
		return selection
	end
	return 'Active'
end

---@return boolean
local function is_active_selected(_)
	return 'Active' == current_selection;
end

---@return boolean
local function is_primary_selected(_)
	return 'Primary' == current_selection;
end

---@return boolean
local function is_secondary_selected(_)
	return 'Secondary' == current_selection;
end

local function is_both_selected(option)
	return ('Both' == current_selection);
end

---@param selection 'Active'|'Primary'|'Secondary'|'Both'
local function set_selection(selection)
	local text = '';

	if selection == 'Both' then
		local spec1, gs1 = RaidBrowser.stats.get_raidset('Primary')
		local spec2, gs2 = RaidBrowser.stats.get_raidset('Secondary')
		

		if gs1 then gs1 = math.floor(gs1 / 100) / 10 end
		if gs2 then gs2 = math.floor(gs2 / 100) / 10 end
		text = (format_raidset(spec1, gs1) or '-') .. ' / ' .. (format_raidset(spec2, gs2) or '-')
		if not (spec1 or spec2) then
			text = 'Set any spec first';
		end
		
	else
		---@diagnostic disable-next-line: param-type-mismatch
		text = format_raidset(RaidBrowser.stats.get_raidset(selection)) or 'Free slot'
	end

	UIDropDownMenu_SetText(RaidBrowserRaidSetMenu, text)
	current_selection = selection;
end

local function on_active()
	set_selection('Active');
	RaidBrowser.stats.select_current_raidset('Active');
	RaidBrowser.check_button()
end

local function on_primary()
	set_selection('Primary');
	RaidBrowser.stats.select_current_raidset('Primary');
	RaidBrowser.check_button()
end

local function on_secondary()
	set_selection('Secondary');
	RaidBrowser.stats.select_current_raidset('Secondary');
	RaidBrowser.check_button()
end

local function on_both()
	set_selection('Both');
	RaidBrowser.stats.select_current_raidset('Both');
	RaidBrowser.check_button()
end

local menu = {
	{
		text = 'Active',
		func = on_active,
		checked = is_active_selected,
	},

	{
		text = "Primary",
		func = on_primary,
		checked = is_primary_selected,
	},

	{
		text = "Secondary",
		func = on_secondary,
		checked = is_secondary_selected,
	},
	
	{ 
		text = "Both", 
		func = on_both, 
		checked = is_both_selected,
	}
}

-- Get the menu option text
local function get_option_text(option)
	local text = format_raidset(RaidBrowser.stats.get_raidset(option));
	return option .. ': ' .. (text or 'Free slot');
end

-- Get the menu option text for the combined Primary/Secondary entry
local function get_option_texts(option)
	local text1 = format_raidset(RaidBrowser.stats.get_raidset('Primary'));
	local text2 = format_raidset(RaidBrowser.stats.get_raidset('Secondary'));
	if not (text1 or text2) then
		return option .. ': Set any spec first';
	end

	return option .. ': ' .. (text1 or '-') .. ' / ' .. (text2 or '-');
end

-- Setup dropdown menu for the raidset selection
frame:SetPoint("CENTER", LFRBrowseFrame, "CENTER", 30, 165)
UIDropDownMenu_Initialize(frame, EasyMenu_Initialize, nil, nil, menu);

local function show_menu()
	menu[1].text = get_option_text('Active');
	menu[2].text = get_option_text('Primary');
	menu[3].text = get_option_text('Secondary');
	menu[4].text = get_option_texts('Both');
	ToggleDropDownMenu(1, nil, frame, frame, 25, 10, menu);	 
end

RaidBrowserRaidSetMenuButton:SetScript('OnClick', show_menu)

local function on_raidset_save()
	if current_selection == 'Primary' then
		RaidBrowser.stats.save_primary_raidset();

	elseif current_selection == 'Secondary' then
		RaidBrowser.stats.save_secondary_raidset();
	end

	local spec, gs = RaidBrowser.stats.current_raidset();

	---@diagnostic disable-next-line: undefined-field
	RaidBrowser:Print('Raidset saved: ' .. tostring(spec) .. (gs and (' ' .. gs .. 'gs') or ''));
	if current_selection then
		set_selection(current_selection)
	else
		set_selection('Active')
	end
end

function RaidBrowser.gui.raidset.initialize()
	local selection = normalize_selection(RaidBrowserCharacterCurrentRaidset)
	set_selection(selection)
	if short_spec_check then
		local use_short_names = RaidBrowser.stats.use_short_spec_names and RaidBrowser.stats.use_short_spec_names() or false
		short_spec_check:SetChecked(use_short_names)
	end
	-- Sync the save button with the restored selection (it is hidden for Active/Both).
	RaidBrowser.check_button()
end

function RaidBrowser.check_button()
    if is_active_selected() or is_both_selected() then
        RaidBrowserRaidSetSaveButton:Disable()
        RaidBrowserRaidSetSaveButton:SetText("Select spec first")
        RaidBrowserRaidSetSaveButton:Hide()
    else
        RaidBrowserRaidSetSaveButton:Enable()
        RaidBrowserRaidSetSaveButton:SetText("Save gear+spec")
        RaidBrowserRaidSetSaveButton:Show()
    end
end

local refresh_events = {
	PLAYER_EQUIPMENT_CHANGED = true,
	ACTIVE_TALENT_GROUP_CHANGED = true, -- dual spec switch
	PLAYER_TALENT_UPDATE = true, -- talent points spent/reset
}

local function onEvent(this, event, arg1)
	if refresh_events[event] then
		RaidBrowser.gui.raidset.initialize()
	end
end

local function onShow(this)
	-- update displayed Spec + GS in selection onShow
	RaidBrowser.gui.raidset.initialize()
end

for event in pairs(refresh_events) do
	frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", onEvent)
frame:SetScript("onShow", onShow)


-- Create raidset save button
local button = CreateFrame("BUTTON", "RaidBrowserRaidSetSaveButton", LFRBrowseFrame, "OptionsButtonTemplate")
button:SetPoint("CENTER", LFRBrowseFrame, "CENTER", -53, 168)
button:EnableMouse(true)
button:RegisterForClicks("AnyUp")

button:SetText("Save Raid Gear");
button:SetWidth(110);
button:SetScript("OnClick", on_raidset_save);
button:Show();

-- Create short spec names checkbox
short_spec_check = CreateFrame("CheckButton", "RaidBrowserRaidSetShortSpecCheckButton", LFRBrowseFrame, "UICheckButtonTemplate")
short_spec_check:SetPoint("CENTER", LFRBrowseFrame, "CENTER", -137, -169)
short_spec_check:SetScript("OnClick", function(self)
	local enabled = self:GetChecked() ~= nil;
	if RaidBrowser.stats.set_use_short_spec_names then
		RaidBrowser.stats.set_use_short_spec_names(enabled)
	end
	if RaidBrowser.stats.refresh_saved_raidset_spec_names then
		RaidBrowser.stats.refresh_saved_raidset_spec_names()
	end

	if current_selection then
		set_selection(current_selection);
	end

	---@diagnostic disable-next-line: undefined-field
	RaidBrowser:Print('Short spec names: ' .. (enabled and 'enabled' or 'disabled'));
end)

local short_spec_label = _G[short_spec_check:GetName() .. "Text"]
if short_spec_label then
	short_spec_label:SetText("Use short spec names")
end
