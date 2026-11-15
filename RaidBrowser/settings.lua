-- Per-character settings, raid filters, new-raid notifications and the /rb command.
RaidBrowser.settings = {}

local S = RaidBrowser.settings

local defaults = {
	-- Seconds after a host's last LFM message before their raid is removed.
	expiry_time = 120,
	-- Print a chat line (and play a sound) for new raids that pass the filters.
	notify = false,
	filters = {
		-- A raid is shown if it needs at least one of the enabled roles.
		roles = { tank = true, healer = true, dps = true },
		hide_saved = false,
		hide_gs_too_high = false,
		-- [instance key] = true for instances that should be hidden.
		hidden_instances = {},
	},
	-- [player name] = true for raid hosts hidden via right-click.
	hidden_hosts = {},
}

local MIN_EXPIRY, MAX_EXPIRY = 30, 600

-- WotLK raids get their own filter entry; everything else is grouped as "other".
S.filter_instances = {
	{ key = 'Icecrown Citadel', label = 'Icecrown Citadel' },
	{ key = 'Trial of the Crusader', label = 'Trial of the Crusader' },
	{ key = 'The Ruby Sanctum', label = 'Ruby Sanctum' },
	{ key = 'Ulduar', label = 'Ulduar' },
	{ key = 'Naxxramas', label = 'Naxxramas' },
	{ key = 'Vault of Archavon', label = 'Vault of Archavon' },
	{ key = 'The Obsidian Sanctum', label = 'Obsidian Sanctum' },
	{ key = 'The Eye of Eternity', label = 'Eye of Eternity' },
	{ key = "Onyxia's Lair", label = "Onyxia's Lair" },
	{ key = 'other', label = 'Other raids (TBC/Classic)' },
}

local known_instances = {}
for _, entry in ipairs(S.filter_instances) do
	known_instances[entry.key] = true
end

---Copies missing keys from source into target (recursively for tables).
local function apply_defaults(target, source)
	for key, value in pairs(source) do
		if type(value) == 'table' then
			if type(target[key]) ~= 'table' then
				target[key] = {}
			end
			apply_defaults(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end
end

function S.initialize()
	if type(RaidBrowserCharacterSettings) ~= 'table' then
		RaidBrowserCharacterSettings = {}
	end
	apply_defaults(RaidBrowserCharacterSettings, defaults)
end

---@return table
function S.get()
	if type(RaidBrowserCharacterSettings) ~= 'table' or not RaidBrowserCharacterSettings.filters then
		S.initialize()
	end
	return RaidBrowserCharacterSettings
end

---@param raid_info table
---@return string
function S.instance_key(raid_info)
	local name = raid_info.instance_name
	if name and known_instances[name] then
		return name
	end
	return 'other'
end

---Whether the player's gearscore meets the raid's requirement.
---@param lfm_info table
---@param player_gs number?
---@return boolean? nil if there is no requirement or the player's GS is unknown
function S.meets_gs(lfm_info, player_gs)
	local required = tonumber(lfm_info.gs)
	if not required or not player_gs then
		return nil
	end
	-- Requirements are stored as e.g. "5.6" (thousands).
	return player_gs >= required * 1000
end

---@param lfm_info table
---@param player_gs number?
---@return boolean
function S.matches_filters(lfm_info, player_gs)
	local settings = S.get()
	if settings.hidden_hosts[lfm_info.sender] then
		return false
	end

	local filters = settings.filters
	if filters.hidden_instances[S.instance_key(lfm_info.raid_info)] then
		return false
	end

	local role_match = false
	for _, role in ipairs(lfm_info.roles) do
		if filters.roles[role] then
			role_match = true
			break
		end
	end
	if not role_match then
		return false
	end

	if filters.hide_saved and RaidBrowser.stats.raid_lock_info(lfm_info.raid_info) then
		return false
	end

	if filters.hide_gs_too_high and S.meets_gs(lfm_info, player_gs) == false then
		return false
	end

	return true
end

---Number of filter groups that currently hide something (for the button label).
---@return integer
function S.active_filter_count()
	local filters = S.get().filters
	local count = 0

	for _, enabled in pairs(filters.roles) do
		if not enabled then
			count = count + 1
			break
		end
	end
	if filters.hide_saved then count = count + 1 end
	if filters.hide_gs_too_high then count = count + 1 end
	if next(filters.hidden_instances) then count = count + 1 end

	return count
end

--[[ Hidden raid hosts ]]--

function S.hide_host(name)
	S.get().hidden_hosts[name] = true
end

---@return integer
function S.hidden_host_count()
	local count = 0
	for _ in pairs(S.get().hidden_hosts) do
		count = count + 1
	end
	return count
end

---@return integer number of players that were unhidden
function S.unhide_all_hosts()
	local count = S.hidden_host_count()
	S.get().hidden_hosts = {}
	return count
end

--[[ Notifications ]]--

local SOUND_COOLDOWN = 10
local last_sound_time = 0

---Called by the chat parser when a host starts advertising a raid.
---@param lfm_info table
function S.notify_new_raid(lfm_info)
	local settings = S.get()
	if not settings.notify then return end

	-- No need to notify while the player is looking at the list.
	if LFRBrowseFrame:IsVisible() then return end

	local player_gs = settings.filters.hide_gs_too_high and RaidBrowser.stats.player_gs() or nil
	if not S.matches_filters(lfm_info, player_gs) then return end

	local gs_text = ''
	if tonumber(lfm_info.gs) then
		gs_text = ' (' .. lfm_info.gs .. ' GS)'
	end

	---@diagnostic disable-next-line: undefined-field
	RaidBrowser:Print(string.format('New raid: |cff00ffff%s|r%s from |Hplayer:%s|h[%s]|h. Type /rb to open.',
		RaidBrowser.get_display_raid_name(lfm_info.raid_info.name), gs_text, lfm_info.sender, lfm_info.sender))

	local now = time()
	if now - last_sound_time >= SOUND_COOLDOWN then
		PlaySound('RaidWarning')
		last_sound_time = now
	end
end

--[[ Slash command ]]--

local function print_help()
	---@diagnostic disable-next-line: undefined-field
	local print = function(text) RaidBrowser:Print(text) end
	print('Commands:')
	print('  /rb - open or close the raid browser')
	print('  /rb notify - turn new-raid notifications on or off')
	print('  /rb expiry <seconds> - how long raids stay listed after their last message (now ' ..
		S.get().expiry_time .. 's)')
	print('  /rb unhide - show all players you hid via right-click again')
end

local function on_slash_command(input)
	local command, argument = (input or ''):lower():match('^%s*(%S*)%s*(.-)%s*$')
	local settings = S.get()

	---@diagnostic disable-next-line: undefined-field
	local print = function(text) RaidBrowser:Print(text) end

	if command == '' then
		RaidBrowser.gui.toggle()

	elseif command == 'notify' then
		if argument == 'on' then
			settings.notify = true
		elseif argument == 'off' then
			settings.notify = false
		else
			settings.notify = not settings.notify
		end
		print('New-raid notifications ' .. (settings.notify and 'enabled' or 'disabled') .. '.')

	elseif command == 'expiry' then
		local seconds = tonumber(argument)
		if not seconds then
			print('Raids expire ' .. settings.expiry_time .. ' seconds after their last message. Usage: /rb expiry <seconds>')
			return
		end
		seconds = math.floor(math.max(MIN_EXPIRY, math.min(MAX_EXPIRY, seconds)))
		settings.expiry_time = seconds
		print('Raids now expire ' .. seconds .. ' seconds after their last message.')

	elseif command == 'unhide' then
		local count = S.unhide_all_hosts()
		print('Unhid ' .. count .. ' player' .. (count == 1 and '' or 's') .. '.')
		RaidBrowser.gui.update_list_if_visible()

	else
		print_help()
	end
end

---@diagnostic disable-next-line: undefined-field
RaidBrowser:RegisterChatCommand('rb', on_slash_command)
