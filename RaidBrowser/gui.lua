---@diagnostic disable: undefined-field
RaidBrowser.gui = {}

-- Players whispered via Join this session: [name] = time of the whisper.
RaidBrowser.whispered = {}

local search_button = LFRQueueFrameFindGroupButton
local join_button = LFRBrowseFrameInviteButton

local name_column = LFRBrowseFrameColumnHeader1
local gs_list_column = LFRBrowseFrameColumnHeader2
local raid_list_column = LFRBrowseFrameColumnHeader3

-- Re-whispering the same host within this many seconds is blocked.
local WHISPER_COOLDOWN = 60

local sort_column
local sort_ascending = false

-- Player gearscore for the list update in progress (used for GS coloring).
local list_player_gs

---Order by ascending or descending based on module variable sort_ascending.
---@param a any
---@param b any
---@return boolean
---@nodiscard
local function compare(a, b)
	if sort_ascending then
		return a > b
	else
		return a < b
	end
end

---@param a table
---@param b table
---@return boolean
---@nodiscard
local sort_function = function(a, b)
	local key_a, key_b
	if sort_column == "name" then
		key_a, key_b = a.sender, b.sender
	elseif sort_column == "gs" then
		key_a, key_b = a.gs, b.gs
	elseif sort_column == "raid" then
		key_a = RaidBrowser.get_display_raid_name(a.raid_info.name)
		key_b = RaidBrowser.get_display_raid_name(b.raid_info.name)
	else
		-- Default: most recently advertised raids first.
		if a.time ~= b.time then
			return a.time > b.time
		end
		return a.sender < b.sender
	end

	if key_a ~= key_b then
		return compare(key_a, key_b)
	end
	-- Stable order for equal keys so rows don't jump around between updates.
	return a.sender < b.sender
end

---@param column string
local function set_sort(column)
	if sort_column == column then
		sort_ascending = not sort_ascending
	else
		sort_column = column
	end

	if RaidBrowser.gui then
		RaidBrowser.gui.update_list()
	end
end

function RaidBrowser.set_sort(column)
    set_sort(column)
end

---Raids that pass the current filters, sorted for display.
---@param player_gs number?
local function get_sorted_messages(player_gs)
	local keys = {}
	for _, info in pairs(RaidBrowser.lfm_messages) do
		if RaidBrowser.settings.matches_filters(info, player_gs) then
			table.insert(keys, info)
		end
	end

	table.sort(keys, sort_function)
	return keys
end

name_column:SetScript('OnClick', function() set_sort('name') end)
gs_list_column:SetText('GS')
gs_list_column:SetScript('OnClick', function() set_sort('gs') end)
raid_list_column:SetText('Raid')
raid_list_column:SetScript('OnClick', function() set_sort('raid') end)

---Whisper a join request to the given raid host (at most once per WHISPER_COOLDOWN).
---@param host_name string?
local function send_join(host_name)
	local raid_message = host_name and RaidBrowser.lfm_messages[host_name]
	if not raid_message then return end

	local last_whisper = RaidBrowser.whispered[host_name]
	if last_whisper and time() - last_whisper < WHISPER_COOLDOWN then
		RaidBrowser:Print(string.format('You already whispered %s %d seconds ago.', host_name, time() - last_whisper))
		return
	end

	local message = RaidBrowser.stats.build_join_message(raid_message.raid_info.name);
	SendChatMessage(message, 'WHISPER', nil, host_name);
	RaidBrowser.whispered[host_name] = time();
	RaidBrowser.gui.update_list_if_visible();
end

local function on_join()
	send_join(LFRBrowseFrame.selectedName)
end

join_button:SetText('Join')
join_button:SetScript('OnClick', on_join)

---@param value integer
---@return string
---@nodiscard
local function format_count(value)
	if value == 1 then
		return ' ';
	end

	return 's ';
end

---@param seconds string
---@return string
---@nodiscard
local function format_seconds(seconds)
	local num_seconds = tonumber(seconds)

	if num_seconds <= 0 then
		return "00 seconds";
	end

	local days_text = '';
	local hours_text = '';
	local minutes_text = '';

	if num_seconds >= 86400 then
		local days = math.floor(num_seconds / 86400);
		days_text = days .. ' day' .. format_count(days);
		num_seconds = num_seconds % 86400;
	end

	if num_seconds >= 3600 then
		local hours = math.floor(num_seconds / 3600);
		hours_text = hours .. ' hr' .. format_count(hours);
		num_seconds = num_seconds % 3600;
	end

	if num_seconds >= 60 then
		local minutes = math.floor(num_seconds / 60);
		minutes_text = minutes .. ' min' .. format_count(minutes);
	end

	return days_text .. hours_text .. minutes_text;
end

-- Hide unused dropdown menu
LFRBrowseFrameRaidDropDown:Hide()

search_button:SetText('Find Raid')
search_button:SetScript('OnClick', function() end)

-- Shared frame for the right-click and filter dropdown menus.
local menu_frame = CreateFrame('Frame', 'RaidBrowserMenuFrame', UIParent, 'UIDropDownMenuTemplate')

-- Tooltip handlers are shared by all list buttons instead of being recreated
-- for every button on every list update.
local function on_button_enter(lfr_button)
	GameTooltip:SetOwner(lfr_button, 'ANCHOR_RIGHT');

	local raid_name = RaidBrowser.get_display_raid_name(lfr_button.raid_info.name);
	local seconds = time() - lfr_button.lfm_info.time;
	local last_sent = string.format('Last sent: %d seconds ago', seconds);
	GameTooltip:AddLine(lfr_button.lfm_info.message, 1, 1, 1, true);
	GameTooltip:AddLine(last_sent);

	if lfr_button.raid_locked then
		GameTooltip:AddLine('\nYou are |cffff0000saved|cffffd100 for ' .. raid_name);
		GameTooltip:AddLine('Lockout expires in ' .. format_seconds(lfr_button.raid_reset_time));
	else
		GameTooltip:AddLine('\nYou are |cff00ffffnot saved|cffffd100 for ' .. raid_name);
	end

	local last_whisper = RaidBrowser.whispered[lfr_button.unitName];
	if last_whisper then
		GameTooltip:AddLine(string.format('You whispered %s %d seconds ago.', lfr_button.unitName, time() - last_whisper),
			0.6, 0.6, 0.6);
	end

	GameTooltip:AddLine('Right-click for more options', 0.5, 0.5, 0.5);
	GameTooltip:Show();
end

local function on_button_leave(_)
	GameTooltip:Hide();
end

---Right-click menu for a raid host: join or hide all their raids.
---@param host_name string
local function show_host_menu(host_name)
	local menu = {
		{ text = host_name, isTitle = true, notCheckable = true },
		{ text = 'Whisper join request', notCheckable = true, func = function() send_join(host_name) end },
		{ text = 'Hide raids from ' .. host_name, notCheckable = true, func = function()
			RaidBrowser.settings.hide_host(host_name)
			RaidBrowser:Print('Hid raids from ' .. host_name .. '. Type /rb unhide to show them again.')
			RaidBrowser.gui.update_list()
		end },
		{ text = 'Cancel', notCheckable = true },
	}
	EasyMenu(menu, menu_frame, 'cursor', 0, 0, 'MENU')
end

local function on_button_click(button, mouse_button)
	if mouse_button == 'RightButton' and button.unitName then
		show_host_menu(button.unitName)
	end
end

-- Assignment operator for LFR buttons
---@param button Button
---@param host_name string
---@param lfm_info any
---@param index integer
local function assign_lfr_button(button, host_name, lfm_info, index)
	button.index = index;

	button.lfm_info = lfm_info;
	button.raid_info = lfm_info.raid_info;

	-- Update selected LFR raid host name
	button.unitName = host_name;

	-- Update button text with raid host name , GS, Raid, and role information
	button.name:SetText(host_name);
	button.level:SetText(button.lfm_info.gs); -- Previously level, now GS

	-- Raid name
	button.class:SetText(RaidBrowser.get_display_raid_name(button.raid_info.name));

	button.raid_locked, button.raid_reset_time = RaidBrowser.stats.raid_lock_info(button.raid_info);
	button.type = "party";

	-- The party/leader icon carried no information, so it stays hidden.
	button.partyIcon:Hide();

	button.tankIcon:Hide();
	button.healerIcon:Hide();
	button.damageIcon:Hide();

	-- Get all the roles from the lfm info table
	for _, role in pairs(button.lfm_info.roles) do
		if role == 'tank' then
			button.tankIcon:Show()
		end

		if role == 'healer' then
			button.healerIcon:Show();
		end

		if role == 'melee_dps' or role == 'ranged_dps' or role == 'dps' then
			button.damageIcon:Show();
		end
	end

	button:Enable();

	-- Grey out hosts that were already whispered this session.
	if RaidBrowser.whispered[host_name] then
		button.name:SetTextColor(0.6, 0.6, 0.6);
	else
		button.name:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b);
	end

	-- Green if the player's GS meets the requirement, red if not, white if unknown.
	local meets_gs = RaidBrowser.settings.meets_gs(lfm_info, list_player_gs);
	if meets_gs == true then
		button.level:SetTextColor(0.1, 1, 0.1);
	elseif meets_gs == false then
		button.level:SetTextColor(1, 0.25, 0.25);
	else
		button.level:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b);
	end

	-- If the raid is saved, then color the raid text in the list as red
	if button.raid_locked then
		button.class:SetTextColor(1, 0, 0);
	else
		button.class:SetTextColor(0, 1, 1);
	end

	-- Set up the corresponding textures for the roles columns
	button.tankIcon:SetTexture("Interface\\LFGFrame\\LFGRole");
	button.healerIcon:SetTexture("Interface\\LFGFrame\\LFGRole");
	button.damageIcon:SetTexture("Interface\\LFGFrame\\LFGRole");

	button:SetScript("OnDoubleClick", on_join)
	button:SetScript('OnEnter', on_button_enter)
	button:SetScript('OnLeave', on_button_leave)

	-- Right-click menu; hooked once so Blizzard's own OnClick (selection) keeps working.
	if not button.raid_browser_hooked then
		button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
		button:HookScript('OnClick', on_button_click)
		button.raid_browser_hooked = true
	end
end

---@param button Button
---@param index integer
local function insert_lfm_button(button, index)
	list_player_gs = RaidBrowser.stats.player_gs();
	local lfm_info = get_sorted_messages(list_player_gs)[index];
	if lfm_info then
		assign_lfr_button(button, lfm_info.sender, lfm_info, index);
	end
end

local function update_buttons()
	LFRBrowseFrameSendMessageButton:Enable();
	LFRBrowseFrameInviteButton:Enable();
end

-- The "Use short spec names" checkbox (raidset_frame.lua) covers the bottom of
-- Blizzard's list, so only the rows above it are used. Scrolling kicks in once
-- there are more raids than these rows.
local NUM_VISIBLE_ROWS = math.min(NUM_LFR_LIST_BUTTONS, 17)

function RaidBrowser.gui.update_list()
	LFRBrowseFrameRefreshButton.timeUntilNextRefresh = LFR_BROWSE_AUTO_REFRESH_TIME;

	-- Look up the player's GS and sort once per update instead of once per row.
	list_player_gs = RaidBrowser.stats.player_gs()
	local sorted = get_sorted_messages(list_player_gs)
	local numResults = #sorted
	FauxScrollFrame_Update(LFRBrowseFrameListScrollFrame, numResults, NUM_VISIBLE_ROWS, 16);

	local offset = FauxScrollFrame_GetOffset(LFRBrowseFrameListScrollFrame);

	for i = 1, NUM_LFR_LIST_BUTTONS do
		local button = _G["LFRBrowseFrameListButton" .. i];
		local index = i + offset;
		local lfm_info = i <= NUM_VISIBLE_ROWS and sorted[index] or nil;

		if lfm_info then
			assign_lfr_button(button, lfm_info.sender, lfm_info, index);
			button:Show();

			if LFRBrowseFrame.selectedName == lfm_info.sender then
				button:LockHighlight();
			else
				button:UnlockHighlight();
			end
		else
			button:Hide();
			button:UnlockHighlight();
		end
	end

	update_buttons();
end

-- Chat parsing can trigger many updates per second; only redraw while the
-- browser is actually on screen. The OnShow hook below catches up on open.
function RaidBrowser.gui.update_list_if_visible()
	if LFRBrowseFrame:IsVisible() then
		RaidBrowser.gui.update_list();
	end
end

LFRBrowseFrame:HookScript('OnShow', function() RaidBrowser.gui.update_list() end)

---Opens or closes the raid browser (used by /rb).
function RaidBrowser.gui.toggle()
	if LFRParentFrame:IsShown() then
		HideUIPanel(LFRParentFrame);
	else
		LFRFrame_SetActiveTab(2);
		ShowUIPanel(LFRParentFrame);
	end
end

--[[ Filter button and menu ]]--

local filter_button = CreateFrame('Button', 'RaidBrowserFilterButton', LFRBrowseFrame, 'OptionsButtonTemplate')
filter_button:SetPoint('CENTER', LFRBrowseFrame, 'CENTER', 120, -169)
filter_button:SetWidth(90)

function RaidBrowser.gui.update_filter_button()
	local count = RaidBrowser.settings.active_filter_count()
	if count > 0 then
		filter_button:SetText('Filter (' .. count .. ')')
	else
		filter_button:SetText('Filter')
	end
end

local function on_filter_changed()
	RaidBrowser.gui.update_filter_button()
	RaidBrowser.gui.update_list()
end

---Checkbox entry that flips table[key]; the menu stays open while toggling.
local function toggle_entry(text, tbl, key, inverted)
	return {
		text = text,
		checked = (tbl[key] and true or false) ~= (inverted and true or false),
		keepShownOnClick = true,
		func = function()
			if inverted then
				tbl[key] = not tbl[key] or nil
			else
				tbl[key] = not tbl[key]
			end
			on_filter_changed()
		end,
	}
end

local function build_filter_menu()
	local settings = RaidBrowser.settings.get()
	local filters = settings.filters

	local menu = {
		{ text = 'Show raids that need', isTitle = true, notCheckable = true },
		toggle_entry('Tank', filters.roles, 'tank'),
		toggle_entry('Healer', filters.roles, 'healer'),
		toggle_entry('DPS', filters.roles, 'dps'),

		{ text = 'Hide', isTitle = true, notCheckable = true },
		toggle_entry('Raids I am saved for', filters, 'hide_saved'),
		toggle_entry('Raids above my GS', filters, 'hide_gs_too_high'),

		{ text = 'Raids', isTitle = true, notCheckable = true },
	}

	-- Instances are checked when shown; hidden_instances stores the unchecked ones.
	for _, instance in ipairs(RaidBrowser.settings.filter_instances) do
		table.insert(menu, toggle_entry(instance.label, filters.hidden_instances, instance.key, true))
	end

	table.insert(menu, { text = 'Other', isTitle = true, notCheckable = true })
	table.insert(menu, toggle_entry('Notify me about new matching raids', settings, 'notify'))

	local hidden_count = RaidBrowser.settings.hidden_host_count()
	table.insert(menu, {
		text = 'Unhide ' .. hidden_count .. ' hidden player' .. (hidden_count == 1 and '' or 's'),
		notCheckable = true,
		disabled = hidden_count == 0,
		func = function()
			RaidBrowser.settings.unhide_all_hosts()
			on_filter_changed()
		end,
	})

	return menu
end

filter_button:SetScript('OnClick', function()
	EasyMenu(build_filter_menu(), menu_frame, 'cursor', 0, 0, 'MENU')
end)

-- Saved variables are not loaded yet at this point; OnEnable updates the label.
filter_button:SetText('Filter')

-- Setup LFR browser hooks
LFRBrowse_UpdateButtonStates = update_buttons
LFRBrowseFrameList_Update = RaidBrowser.gui.update_list
LFRBrowseFrameListButton_SetData = insert_lfm_button

-- Set the "Browse" tab to be active.
LFRFrame_SetActiveTab(2)

LFRParentFrameTab1:Hide();
LFRParentFrameTab2:Hide();
