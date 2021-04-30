local ADDON = 'Farseer'
if select(2, UnitClass('player')) ~= 'SHAMAN' then
	DisableAddOn(ADDON)
	return
end
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

-- copy heavily accessed global functions into local scope for performance
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellCharges = _G.GetSpellCharges
local GetTime = _G.GetTime
local UnitCastingInfo = _G.UnitCastingInfo
local UnitAura = _G.UnitAura
-- end copy global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
   return string.lower(str:sub(1, start:len())) == start:lower()
end
-- end useful functions

Farseer = {}
local Opt -- use this as a local table reference to Farseer

SLASH_Farseer1, SLASH_Farseer2 = '/fs', '/farseer'
BINDING_HEADER_FARSEER = ADDON

local function InitOpts()
	local function SetDefaults(t, ref)
		local k, v
		for k, v in next, ref do
			if t[k] == nil then
				local pchar
				if type(v) == 'boolean' then
					pchar = v and 'true' or 'false'
				elseif type(v) == 'table' then
					pchar = 'table'
				else
					pchar = v
				end
				t[k] = v
			elseif type(t[k]) == 'table' then
				SetDefaults(t[k], v)
			end
		end
	end
	SetDefaults(Farseer, { -- defaults
		locked = false,
		snap = false,
		scale = {
			main = 1,
			previous = 0.7,
			cooldown = 0.7,
			interrupt = 0.4,
			extra = 0.4,
			glow = 1,
		},
		glow = {
			main = true,
			cooldown = true,
			interrupt = false,
			extra = true,
			blizzard = false,
			color = { r = 1, g = 1, b = 1 },
		},
		hide = {
			elemental = false,
			enhancement = false,
			restoration = false,
		},
		alpha = 1,
		frequency = 0.2,
		previous = true,
		always_on = false,
		cooldown = true,
		spell_swipe = true,
		dimmer = true,
		miss_effect = true,
		boss_only = false,
		interrupt = true,
		aoe = false,
		auto_aoe = false,
		auto_aoe_ttl = 10,
		cd_ttd = 8,
		pot = false,
		trinket = true,
		shield = true,
		earth = true,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	glows = {},
}

-- automatically registered events container
local events = {}

local timer = {
	combat = 0,
	display = 0,
	health = 0
}

-- specialization constants
local SPEC = {
	NONE = 0,
	ELEMENTAL = 1,
	ENHANCEMENT = 2,
	RESTORATION = 3,
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	spec = 0,
	target_mode = 0,
	execute_remains = 0,
	haste_factor = 1,
	gcd = 1.5,
	gcd_remains = 0,
	health = 0,
	health_max = 0,
	mana = 0,
	mana_base = 0,
	mana_max = 0,
	mana_regen = 0,
	maelstrom = 0,
	maelstrom_max = 0,
	maelstrom_weapon = 0,
	elemental_remains = 0,
	moving = false,
	movement_speed = 100,
	last_swing_taken = 0,
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
	},
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	health_array = {},
	hostile = false,
	estimated_range = 30,
}

-- base mana by player level
local BaseMana = {
	52,   54,   57,   60,   62,   66,   69,   72,   76,   80,
	86,   93,   101,  110,  119,  129,  140,  152,  165,  178,
	193,  210,  227,  246,  267,  289,  314,  340,  369,  400,
	433,  469,  509,  551,  598,  648,  702,  761,  825,  894,
	969,  1050, 1138, 1234, 1337, 1449, 1571, 1702, 1845, 2000,
	2349, 2759, 3241, 3807, 4472, 5253, 6170, 7247, 8513, 10000
}

local farseerPanel = CreateFrame('Frame', 'farseerPanel', UIParent)
farseerPanel:SetPoint('CENTER', 0, -169)
farseerPanel:SetFrameStrata('BACKGROUND')
farseerPanel:SetSize(64, 64)
farseerPanel:SetMovable(true)
farseerPanel:Hide()
farseerPanel.icon = farseerPanel:CreateTexture(nil, 'BACKGROUND')
farseerPanel.icon:SetAllPoints(farseerPanel)
farseerPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
farseerPanel.border = farseerPanel:CreateTexture(nil, 'ARTWORK')
farseerPanel.border:SetAllPoints(farseerPanel)
farseerPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
farseerPanel.border:Hide()
farseerPanel.dimmer = farseerPanel:CreateTexture(nil, 'BORDER')
farseerPanel.dimmer:SetAllPoints(farseerPanel)
farseerPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
farseerPanel.dimmer:Hide()
farseerPanel.swipe = CreateFrame('Cooldown', nil, farseerPanel, 'CooldownFrameTemplate')
farseerPanel.swipe:SetAllPoints(farseerPanel)
farseerPanel.text = CreateFrame('Frame', nil, farseerPanel)
farseerPanel.text:SetAllPoints(farseerPanel)
farseerPanel.text.tl = farseerPanel.text:CreateFontString(nil, 'OVERLAY')
farseerPanel.text.tl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
farseerPanel.text.tl:SetPoint('TOPLEFT', farseerPanel, 'TOPLEFT', 2.5, -3)
farseerPanel.text.tl:SetJustifyH('LEFT')
farseerPanel.text.tr = farseerPanel.text:CreateFontString(nil, 'OVERLAY')
farseerPanel.text.tr:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
farseerPanel.text.tr:SetPoint('TOPRIGHT', farseerPanel, 'TOPRIGHT', -2.5, -3)
farseerPanel.text.tr:SetJustifyH('RIGHT')
farseerPanel.text.bl = farseerPanel.text:CreateFontString(nil, 'OVERLAY')
farseerPanel.text.bl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
farseerPanel.text.bl:SetPoint('BOTTOMLEFT', farseerPanel, 'BOTTOMLEFT', 2.5, 3)
farseerPanel.text.bl:SetJustifyH('LEFT')
farseerPanel.text.br = farseerPanel.text:CreateFontString(nil, 'OVERLAY')
farseerPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
farseerPanel.text.br:SetPoint('BOTTOMRIGHT', farseerPanel, 'BOTTOMRIGHT', -2.5, 3)
farseerPanel.text.br:SetJustifyH('RIGHT')
farseerPanel.text.center = farseerPanel.text:CreateFontString(nil, 'OVERLAY')
farseerPanel.text.center:SetFont('Fonts\\FRIZQT__.TTF', 11, 'OUTLINE')
farseerPanel.text.center:SetAllPoints(farseerPanel.text)
farseerPanel.text.center:SetJustifyH('CENTER')
farseerPanel.text.center:SetJustifyV('CENTER')
farseerPanel.button = CreateFrame('Button', nil, farseerPanel)
farseerPanel.button:SetAllPoints(farseerPanel)
farseerPanel.button:RegisterForClicks('LeftButtonDown', 'RightButtonDown', 'MiddleButtonDown')
local farseerPreviousPanel = CreateFrame('Frame', 'farseerPreviousPanel', UIParent)
farseerPreviousPanel:SetFrameStrata('BACKGROUND')
farseerPreviousPanel:SetSize(64, 64)
farseerPreviousPanel:Hide()
farseerPreviousPanel:RegisterForDrag('LeftButton')
farseerPreviousPanel:SetScript('OnDragStart', farseerPreviousPanel.StartMoving)
farseerPreviousPanel:SetScript('OnDragStop', farseerPreviousPanel.StopMovingOrSizing)
farseerPreviousPanel:SetMovable(true)
farseerPreviousPanel.icon = farseerPreviousPanel:CreateTexture(nil, 'BACKGROUND')
farseerPreviousPanel.icon:SetAllPoints(farseerPreviousPanel)
farseerPreviousPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
farseerPreviousPanel.border = farseerPreviousPanel:CreateTexture(nil, 'ARTWORK')
farseerPreviousPanel.border:SetAllPoints(farseerPreviousPanel)
farseerPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
local farseerCooldownPanel = CreateFrame('Frame', 'farseerCooldownPanel', UIParent)
farseerCooldownPanel:SetSize(64, 64)
farseerCooldownPanel:SetFrameStrata('BACKGROUND')
farseerCooldownPanel:Hide()
farseerCooldownPanel:RegisterForDrag('LeftButton')
farseerCooldownPanel:SetScript('OnDragStart', farseerCooldownPanel.StartMoving)
farseerCooldownPanel:SetScript('OnDragStop', farseerCooldownPanel.StopMovingOrSizing)
farseerCooldownPanel:SetMovable(true)
farseerCooldownPanel.icon = farseerCooldownPanel:CreateTexture(nil, 'BACKGROUND')
farseerCooldownPanel.icon:SetAllPoints(farseerCooldownPanel)
farseerCooldownPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
farseerCooldownPanel.border = farseerCooldownPanel:CreateTexture(nil, 'ARTWORK')
farseerCooldownPanel.border:SetAllPoints(farseerCooldownPanel)
farseerCooldownPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
farseerCooldownPanel.cd = CreateFrame('Cooldown', nil, farseerCooldownPanel, 'CooldownFrameTemplate')
farseerCooldownPanel.cd:SetAllPoints(farseerCooldownPanel)
local farseerInterruptPanel = CreateFrame('Frame', 'farseerInterruptPanel', UIParent)
farseerInterruptPanel:SetFrameStrata('BACKGROUND')
farseerInterruptPanel:SetSize(64, 64)
farseerInterruptPanel:Hide()
farseerInterruptPanel:RegisterForDrag('LeftButton')
farseerInterruptPanel:SetScript('OnDragStart', farseerInterruptPanel.StartMoving)
farseerInterruptPanel:SetScript('OnDragStop', farseerInterruptPanel.StopMovingOrSizing)
farseerInterruptPanel:SetMovable(true)
farseerInterruptPanel.icon = farseerInterruptPanel:CreateTexture(nil, 'BACKGROUND')
farseerInterruptPanel.icon:SetAllPoints(farseerInterruptPanel)
farseerInterruptPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
farseerInterruptPanel.border = farseerInterruptPanel:CreateTexture(nil, 'ARTWORK')
farseerInterruptPanel.border:SetAllPoints(farseerInterruptPanel)
farseerInterruptPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
farseerInterruptPanel.cast = CreateFrame('Cooldown', nil, farseerInterruptPanel, 'CooldownFrameTemplate')
farseerInterruptPanel.cast:SetAllPoints(farseerInterruptPanel)
local farseerExtraPanel = CreateFrame('Frame', 'farseerExtraPanel', UIParent)
farseerExtraPanel:SetFrameStrata('BACKGROUND')
farseerExtraPanel:SetSize(64, 64)
farseerExtraPanel:Hide()
farseerExtraPanel:RegisterForDrag('LeftButton')
farseerExtraPanel:SetScript('OnDragStart', farseerExtraPanel.StartMoving)
farseerExtraPanel:SetScript('OnDragStop', farseerExtraPanel.StopMovingOrSizing)
farseerExtraPanel:SetMovable(true)
farseerExtraPanel.icon = farseerExtraPanel:CreateTexture(nil, 'BACKGROUND')
farseerExtraPanel.icon:SetAllPoints(farseerExtraPanel)
farseerExtraPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
farseerExtraPanel.border = farseerExtraPanel:CreateTexture(nil, 'ARTWORK')
farseerExtraPanel.border:SetAllPoints(farseerExtraPanel)
farseerExtraPanel.border:SetTexture(ADDON_PATH .. 'border.blp')

-- Start AoE

Player.target_modes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.ELEMENTAL] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
	},
	[SPEC.ENHANCEMENT] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
	},
	[SPEC.RESTORATION] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
	},
}

function Player:SetTargetMode(mode)
	if mode == self.target_mode then
		return
	end
	self.target_mode = min(mode, #self.target_modes[self.spec])
	self.enemies = self.target_modes[self.spec][self.target_mode][1]
	farseerPanel.text.br:SetText(self.target_modes[self.spec][self.target_mode][2])
end

function Player:ToggleTargetMode()
	local mode = self.target_mode + 1
	self:SetTargetMode(mode > #self.target_modes[self.spec] and 1 or mode)
end

function Player:ToggleTargetModeReverse()
	local mode = self.target_mode - 1
	self:SetTargetMode(mode < 1 and #self.target_modes[self.spec] or mode)
end

-- Target Mode Keybinding Wrappers
function Farseer_SetTargetMode(mode)
	Player:SetTargetMode(mode)
end

function Farseer_ToggleTargetMode()
	Player:ToggleTargetMode()
end

function Farseer_ToggleTargetModeReverse()
	Player:ToggleTargetModeReverse()
end

-- End AoE

-- Start Auto AoE

local autoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {
		[120651] = true, -- Explosives (Mythic+ affix)
	},
}

function autoAoe:Add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local unitId = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	if unitId and self.ignored_units[tonumber(unitId)] then
		self.blacklist[guid] = Player.time + 10
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = Player.time
	if update and new then
		self:Update()
	end
end

function autoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function autoAoe:Clear()
	local guid
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:Update()
	local count, i = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		Player:SetTargetMode(1)
		return
	end
	Player.enemies = count
	for i = #Player.target_modes[Player.spec], 1, -1 do
		if count >= Player.target_modes[Player.spec][i][1] then
			Player:SetTargetMode(i)
			Player.enemies = count
			return
		end
	end
end

function autoAoe:Purge()
	local update, guid, t
	for guid, t in next, self.targets do
		if Player.time - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	-- remove expired blacklisted enemies
	for guid, t in next, self.blacklist do
		if Player.time > t then
			self.blacklist[guid] = nil
		end
	end
	if update then
		self:Update()
	end
end

-- End Auto AoE

-- Start Abilities

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {}
}

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		rank = 0,
		mana_cost = 0,
		maelstrom_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 40,
		velocity = 0,
		last_used = 0,
		auraTarget = buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, self)
	abilities.all[#abilities.all + 1] = ability
	return ability
end

function Ability:Match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function Ability:Usable(seconds)
	if not self.known then
		return false
	end
	if self:Cost() > Player.mana then
		return false
	end
	if Player.spec == SPEC.ELEMENTAL and self:MaelstromCost() > Player.maelstrom then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Remains()
	if self:Casting() or self:Traveling() > 0 then
		return self:Duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		elseif self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - Player.ctime - Player.execute_remains, 0)
		end
	end
	return 0
end

function Ability:Refreshable()
	if self.buff_duration > 0 then
		return self:Remains() < self:Duration() * 0.3
	end
	return self:Down()
end

function Ability:Up(condition)
	return self:Remains(condition) > 0
end

function Ability:Down(condition)
	return self:Remains(condition) <= 0
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.traveling = {}
	else
		self.traveling = nil
		self.velocity = 0
	end
end

function Ability:Traveling(all)
	if not self.traveling then
		return 0
	end
	local count, cast, _ = 0
	for _, cast in next, self.traveling do
		if all or cast.dstGUID == Target.guid then
			if Player.time - cast.start < self.max_range / self.velocity then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity
end

function Ability:Ticking()
	if self.aura_targets then
		local count, guid, aura = 0
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:Up() and 1 or 0
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - Player.execute_remains)
end

function Ability:Stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		elseif self:Match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:Cost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * Player.mana_base) or 0
end

function Ability:MaelstromCost()
	return self.maelstrom_cost
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return recharge_time
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.ability_casting == self
end

function Ability:Channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:CastTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and Player.gcd or 0
	end
	return castTime / 1000
end

function Ability:CastRegen()
	return Player.mana_regen * self:CastTime() - self:Cost()
end

function Ability:Previous(n)
	local i = n or 1
	if Player.ability_casting then
		if i == 1 then
			return Player.ability_casting == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {},
		target_count = 0,
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	else
		self.auto_aoe.trigger = 'SPELL_DAMAGE'
	end
end

function Ability:RecordTargetHit(guid)
	self.auto_aoe.targets[guid] = Player.time
	if not self.auto_aoe.start_time then
		self.auto_aoe.start_time = self.auto_aoe.targets[guid]
	end
end

function Ability:UpdateTargetsHit()
	if self.auto_aoe.start_time and Player.time - self.auto_aoe.start_time >= 0.3 then
		self.auto_aoe.start_time = nil
		if self.auto_aoe.remove then
			autoAoe:Clear()
		end
		self.auto_aoe.target_count = 0
		local guid
		for guid in next, self.auto_aoe.targets do
			autoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		autoAoe:Update()
	end
end

function Ability:Targets()
	if self.auto_aoe and self:Up() then
		return self.auto_aoe.target_count
	end
	return 0
end

function Ability:CastSuccess(dstGUID, timeStamp)
	self.last_used = timeStamp
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.traveling and self.next_castGUID then
		self.traveling[self.next_castGUID] = {
			guid = self.next_castGUID,
			start = self.last_used,
			dstGUID = dstGUID,
		}
		self.next_castGUID = nil
	end
end

function Ability:CastLanded(dstGUID, timeStamp, eventType)
	if not self.traveling then
		return
	end
	local guid, cast, oldest
	for guid, cast in next, self.traveling do
		if Player.time - cast.start >= self.max_range / self.velocity + 0.2 then
			self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
		elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
			oldest = cast
		end
	end
	if oldest then
		Target.estimated_range = min(self.max_range, floor(self.velocity * max(0, timeStamp - oldest.start)))
		self.traveling[oldest.guid] = nil
	end
end

-- start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	local _, ability, guid, expires
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	local _, ability
	for _, ability in next, abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = {
		expires = Player.time + self:Duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:RefreshAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		self:ApplyAura(guid)
		return
	end
	local duration = self:Duration()
	aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

-- Shaman Abilities
---- Multiple Specializations
local ChainHeal = Ability:Add(1064, true, true)
ChainHeal.mana_cost = 30
ChainHeal.consume_mw = true
local ChainLightning = Ability:Add(188443, false, true)
ChainLightning.mana_cost = 1
ChainLightning.maelstrom_cost = -4
ChainLightning.consume_mw = true
ChainLightning:AutoAoe(false)
local EarthElemental = Ability:Add(198103, true, true)
EarthElemental.buff_duration = 60
EarthElemental.cooldown_duration = 300
local FlameShock = Ability:Add(188389, false, true)
FlameShock.buff_duration = 18
FlameShock.cooldown_duration = 6
FlameShock.mana_cost = 1.5
FlameShock.tick_interval = 2
FlameShock.hasted_ticks = true
FlameShock:TrackAuras()
local FlametongueWeapon = Ability:Add(318038, true, true)
FlametongueWeapon.enchant_id = 5400
local FrostShock = Ability:Add(196840, false, true)
FrostShock.buff_duration = 6
FrostShock.mana_cost = 1
local GhostWolf = Ability:Add(2645, true, true)
local HealingSurge = Ability:Add(8004, true, true)
HealingSurge.mana_cost = 24
HealingSurge.consume_mw = true
local Heroism = Ability:Add(32182, true, false)
Heroism.buff_duration = 40
Heroism.cooldown_duration = 300
Heroism.mana_cost = 21.5
local LightningBolt = Ability:Add(188196, false, true)
LightningBolt.mana_cost = 2
LightningBolt.maelstrom_cost = -8
LightningBolt.consume_mw = true
local LightningShield = Ability:Add(192106, true, true)
LightningShield.buff_duration = 3600
LightningShield.mana_cost = 1.5
local SpiritwalkersGrace = Ability:Add(79206, true, true)
SpiritwalkersGrace.buff_duration = 15
SpiritwalkersGrace.mana_cost = 14.1
local WindShear = Ability:Add(57994, false, true)
WindShear.buff_duration = 3
WindShear.cooldown_duration = 12
------ Talents
local ElementalBlast = Ability:Add(117014, false, true)
ElementalBlast.cooldown_duration = 12
ElementalBlast.mana_cost = 2.75
ElementalBlast.maelstrom_cost = -30
local Stormkeeper = Ability:Add({191634, 320137}, true, true)
Stormkeeper.buff_duration = 15
Stormkeeper.cooldown_duration = 60
------ Procs
local LavaSurge = Ability:Add(77756, true, true, 77762)
LavaSurge.buff_duration = 10
---- Elemental
local EarthShock = Ability:Add(8042, false, true)
EarthShock.mana_cost = 0.6
EarthShock.maelstrom_cost = 60
local Earthquake = Ability:Add(61882, false, true, 77478)
Earthquake.mana_cost = 0.6
Earthquake.maelstrom_cost = 60
Earthquake:AutoAoe(false)
local FireElemental = Ability:Add(198067, true, true)
FireElemental.buff_duration = 30
FireElemental.cooldown_duration = 150
FireElemental.mana_cost = 5
local LavaBurst = Ability:Add(51505, false, true, 285452)
LavaBurst.cooldown_duration = 8
LavaBurst.mana_cost = 2.5
LavaBurst.maelstrom_cost = -10
LavaBurst.requires_charge = true
LavaBurst:SetVelocity(60)
local Thunderstorm = Ability:Add(51490, false, true)
Thunderstorm.cooldown_duration = 45
Thunderstorm.buff_duration = 5
Thunderstorm:AutoAoe(false)
------ Talents
local AscendanceFlame = Ability:Add(114050, true, true)
AscendanceFlame.buff_duration = 15
AscendanceFlame.cooldown_duration = 180
local EchoingShock = Ability:Add(320125, true, true)
EchoingShock.buff_duration = 8
EchoingShock.cooldown_duration = 30
EchoingShock.mana_cost = 3.25
local EchoOfTheElements = Ability:Add(333919, true, true)
local Icefury = Ability:Add(210714, true, true)
Icefury.buff_duration = 15
Icefury.cooldown_duration = 30
Icefury.mana_cost = 3
Icefury.maelstrom_cost = -25
local LavaBeam = Ability:Add(114074, false, true)
LavaBeam.maelstrom_cost = -3
LavaBeam:AutoAoe(false)
local LiquidMagmaTotem = Ability:Add(192222, false, true)
LiquidMagmaTotem.cooldown_duration = 60
LiquidMagmaTotem.mana_cost = 3.5
local MasterOfTheElements = Ability:Add(16166, true, true, 260734)
MasterOfTheElements.buff_duration = 15
local PrimalElementalist = Ability:Add(117013, true, true)
local StaticDischarge = Ability:Add(342243, false, true)
StaticDischarge.buff_duration = 3
StaticDischarge.cooldown_duration = 30
StaticDischarge.mana_cost = 1.25
StaticDischarge.tick_interval = 0.5
local StormElemental = Ability:Add(192249, true, true)
StormElemental.buff_duration = 30
StormElemental.cooldown_duration = 150
StormElemental.totem_icon = 1020304
local WindGust = Ability:Add(263806, true, true)
WindGust.buff_duration = 30
------ Procs

---- Enhancement
local CrashLightning = Ability:Add(187874, false, true)
CrashLightning.cooldown_duration = 9
CrashLightning.hasted_cooldown = true
CrashLightning.mana_cost = 5.5
CrashLightning:AutoAoe(true)
CrashLightning.buff = Ability:Add(187878, true, true)
CrashLightning.buff.buff_duration = 10
local FeralSpirit = Ability:Add(51533, true, true, 333957)
FeralSpirit.buff_duration = 15
FeralSpirit.cooldown_duration = 120
local LavaLash = Ability:Add(60103, false, true)
LavaLash.cooldown_duration = 12
LavaLash.mana_cost = 4
LavaLash.hasted_cooldown = true
local Stormstrike = Ability:Add(17364, false, true)
Stormstrike.cooldown_duration = 7.5
Stormstrike.mana_cost = 2
Stormstrike.hasted_cooldown = true
local WindfuryTotem = Ability:Add(8512, true, false, 327942)
WindfuryTotem.buff_duration = 120
WindfuryTotem.mana_cost = 12
local WindfuryWeapon = Ability:Add(33757, true, true)
WindfuryWeapon.enchant_id = 5401
------ Talents
local AscendanceAir = Ability:Add(114051, true, true)
AscendanceAir.buff_duration = 15
AscendanceAir.cooldown_duration = 180
local ForcefulWinds = Ability:Add(262647, true, true, 262652)
ForcefulWinds.buff_duration = 15
local Hailstorm = Ability:Add(334195, true, true, 334196)
Hailstorm.buff_duration = 20
local HotHand = Ability:Add(201900, true, true, 215785)
HotHand.buff_duration = 15
local LashingFlames = Ability:Add(334046, true, true, 334168)
LashingFlames.buff_duration = 12
local Sundering = Ability:Add(197214, false, true)
Sundering.cooldown_duration = 40
Sundering.mana_cost = 6
Sundering:AutoAoe(false)
local Windstrike = Ability:Add(115356, false, true)
Windstrike.cooldown_duration = 3.1
Windstrike.mana_cost = 2
Windstrike.hasted_cooldown = true
------ Procs
local GatheringStorms = Ability:Add(198300, true, true)
GatheringStorms.buff_duration = 12
local MaelstromWeapon = Ability:Add(187880, true, true, 344179)
MaelstromWeapon.buff_duration = 30
local Stormbringer = Ability:Add(201846, true, true)
Stormbringer.buff_duration = 12
---- Restoration

------ Talents

------ Procs

-- Covenant abilities
local ChainHarvest = Ability:Add(320674, false, true) -- Venthyr
ChainHarvest.cooldown_duration = 90
ChainHarvest.mana_cost = 10
ChainHarvest.consume_mw = true
ChainHarvest:AutoAoe(true)
local PrimordialWave = Ability:Add(326059, false, true, 327162) -- Necrolord
PrimordialWave.cooldown_duration = 45
PrimordialWave.mana_cost = 3
PrimordialWave:SetVelocity(45)
PrimordialWave.buff = Ability:Add(327164, true, true)
PrimordialWave.buff.buff_duration = 15
-- Soulbind conduits
local CallOfFlame = Ability:Add(338303, true, true)
CallOfFlame.conduit_id = 104
-- Legendary effects
local DoomWinds = Ability:Add(335902, true, true, 335903)
DoomWinds.buff_duration = 12
DoomWinds.cooldown_duration = 60
DoomWinds.bonus_id = 6993
DoomWinds.cooldown = Ability:Add(335904, false, true)
DoomWinds.cooldown.auraTarget = 'player'
DoomWinds.cooldown.bonus_id = DoomWinds.bonus_id
local ElementalEquilibrium = Ability:Add(336730, true, true)
ElementalEquilibrium.bonus_id = 6990
ElementalEquilibrium.debuff = Ability:Add(347349, false, true)
ElementalEquilibrium.debuff.buff_duration = 30
ElementalEquilibrium.debuff.auraTarget = 'player'
ElementalEquilibrium.debuff.bonus_id = ElementalEquilibrium.bonus_id
local SkybreakersFieryDemise = Ability:Add(336734, true, true)
SkybreakersFieryDemise.bonus_id = 6989
local DeeptremorStone = Ability:Add(336739, true, true)
DeeptremorStone.bonus_id = 6986
local EchoesOfGreatSundering = Ability:Add(336215, true, true, 336217)
EchoesOfGreatSundering.buff_duration = 25
EchoesOfGreatSundering.bonus_id = 6991
-- PvP talents

-- Racials

-- Trinket Effects

-- End Abilities

-- Start Inventory Items

local InventoryItem, inventoryItems, Trinket = {}, {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem:Add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
	}
	setmetatable(item, self)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:Charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:Cooldown()
	local startTime, duration
	if self.equip_slot then
		startTime, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		startTime, duration = GetItemCooldown(self.itemId)
	end
	return startTime == 0 and 0 or duration - (Player.ctime - startTime)
end

function InventoryItem:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function InventoryItem:Equipped()
	return self.equip_slot and true
end

function InventoryItem:Usable(seconds)
	if not self.can_use then
		return false
	end
	if not self:Equipped() and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

-- Inventory Items
local SpectralFlaskOfPower = InventoryItem:Add(171276)
SpectralFlaskOfPower.buff = Ability:Add(307185, true, true)
local PotionOfSpectralIntellect = InventoryItem:Add(171273)
PotionOfSpectralIntellect.buff = Ability:Add(307162, true, true)
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Player API

function Player:Enemies()
	if Player.spec == SPEC.ELEMENTAL then
		if self.ability_casting == ChainLightning and self.enemies <= 2 then
			return 3
		end
		if self.ability_casting == LightningBolt and self.enemies >= 3 then
			return 2
		end
	elseif Player.spec == SPEC.ENHANCEMENT then
		if self.ability_casting == ChainLightning and self.enemies <= 1 then
			return 2
		end
		if self.ability_casting == LightningBolt and self.enemies >= 2 then
			return 1
		end
	end
	return self.enemies
end

function Player:Health()
	return self.health
end

function Player:HealthMax()
	return self.health_max
end

function Player:HealthPct()
	return self.health / self.health_max * 100
end

function Player:Maelstrom()
	return self.maelstrom
end

function Player:MaelstromDeficit()
	return self.maelstrom_max - self.maelstrom
end

function Player:UnderAttack()
	return (Player.time - self.last_swing_taken) < 3
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	return 0
end

function Player:BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if not id then
			return false
		elseif (
			id == 2825 or   -- Bloodlust (Horde Shaman)
			id == 32182 or  -- Heroism (Alliance Shaman)
			id == 80353 or  -- Time Warp (Mage)
			id == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			id == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			id == 178207 or -- Drums of Fury (Leatherworking)
			id == 146555 or -- Drums of Rage (Leatherworking)
			id == 230935 or -- Drums of the Mountain (Leatherworking)
			id == 256740    -- Drums of the Maelstrom (Leatherworking)
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
	if slot then
		return GetInventoryItemID('player', slot) == itemID, slot
	end
	local i
	for i = 1, 19 do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:BonusIdEquipped(bonusId)
	local i, id, link, item
	for i = 1, 19 do
		link = GetInventoryItemLink('player', i)
		if link then
			item = link:match('Hitem:%d+:([%d:]+)')
			if item then
				for id in item:gmatch('(%d+)') do
					if tonumber(id) == bonusId then
						return true
					end
				end
			end
		end
	end
	return false
end

function Player:InArenaOrBattleground()
	return self.instance == 'arena' or self.instance == 'pvp'
end

function Player:UpdateAbilities()
	self.mana_base = BaseMana[UnitLevel('player')]
	self.rescan_abilities = false

	local _, ability, spellId, node
	for _, ability in next, abilities.all do
		ability.known = false
		for _, spellId in next, ability.spellIds do
			ability.spellId, ability.name, _, ability.icon = spellId, GetSpellInfo(spellId)
			if IsPlayerSpell(spellId) then
				ability.known = true
				break
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) then
			ability.known = false -- spell is locked, do not mark as known
		end
		if ability.bonus_id then -- used for checking Legendary crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if ability.conduit_id then
			node = C_Soulbinds.FindNodeIDActuallyInstalled(C_Soulbinds.GetActiveSoulbindID(), ability.conduit_id)
			if node then
				node = C_Soulbinds.GetNode(node)
				if node then
					if node.conduitID == 0 then
						self.rescan_abilities = true -- rescan on next target, conduit data has not finished loading
					else
						ability.known = node.state == 3
						ability.rank = node.conduitRank
					end
				end
			end
		end
	end

	if CrashLightning.known then
		CrashLightning.buff.known = true
		GatheringStorms.known = true
	end
	if AscendanceAir.known then
		Windstrike.known = true
	end
	if AscendanceFlame.known then
		LavaBeam.known = true
	end
	if PrimordialWave.known then
		PrimordialWave.buff.known = true
	end
	if FrostShock.known then
		if Hailstorm.known then
			FrostShock:AutoAoe(false)
		else
			FrostShock.auto_aoe = nil
		end
	end
	if StormElemental.known then
		WindGust.known = true
		FireElemental.known = false
	end
	if Player.spec == SPEC.ENHANCEMENT then
		FlameShock.hasted_cooldown = true
		FrostShock.cooldown_duration = 6
		FrostShock.hasted_cooldown = true
	else
		FlameShock.hasted_cooldown = false
		FrostShock.cooldown_duration = 0
		FrostShock.hasted_cooldown = false
	end
	EarthElemental.summon_spell = PrimalElementalist.known and 118323 or 188616
	EarthElemental.npc_id = PrimalElementalist.known and 61056 or 95072
	FireElemental.summon_spell = PrimalElementalist.known and 118291 or 188592
	FireElemental.npc_id = PrimalElementalist.known and 61029 or 95061
	StormElemental.summon_spell = PrimalElementalist.known and 157319 or 157299
	StormElemental.npc_id = PrimalElementalist.known and 77942 or 77936

	abilities.bySpellId = {}
	abilities.velocity = {}
	abilities.autoAoe = {}
	abilities.trackAuras = {}
	for _, ability in next, abilities.all do
		if ability.known then
			abilities.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				abilities.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				abilities.velocity[#abilities.velocity + 1] = ability
			end
			if ability.auto_aoe then
				abilities.autoAoe[#abilities.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				abilities.trackAuras[#abilities.trackAuras + 1] = ability
			end
		end
	end
end

function Player:Update()
	local _, start, duration, remains, spellId, speed, max_speed
	self.ctime = GetTime()
	self.time = self.ctime - self.time_diff
	self.main =  nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	start, duration = GetSpellCooldown(61304)
	self.gcd_remains = start > 0 and duration - (self.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	self.ability_casting = abilities.bySpellId[spellId]
	self.execute_remains = max(remains and (remains / 1000 - self.ctime) or 0, self.gcd_remains)
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	self.gcd = 1.5 * self.haste_factor
	self.health = UnitHealth('player')
	self.health_max = UnitHealthMax('player')
	self.mana_regen = GetPowerRegen()
	self.mana = UnitPower('player', 0) + (self.mana_regen * self.execute_remains)
	self.mana_max = UnitPowerMax('player', 0)
	if self.ability_casting then
		self.mana = self.mana - self.ability_casting:Cost()
	end
	self.mana = min(max(self.mana, 0), self.mana_max)
	if self.spec == SPEC.ELEMENTAL then
		self.maelstrom = UnitPower('player', 11)
		self.maelstrom_max = UnitPowerMax('player', 11)
		if self.ability_casting then
			self.maelstrom = self.maelstrom - self.ability_casting:MaelstromCost()
		end
		self.maelstrom = min(max(self.maelstrom, 0), self.maelstrom_max)
	elseif self.spec == SPEC.ENHANCEMENT then
		self.maelstrom_weapon = MaelstromWeapon:Stack()
	end
	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100
	self.pet = UnitGUID('pet')
	self.pet_active = self.pet and not UnitIsDead('pet')

	trackAuras:Purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		autoAoe:Purge()
	end

	self.elemental_remains = 0
	if FireElemental.known then
		self.elemental_remains = FireElemental:Remains()
	end
	if StormElemental.known and self.elemental_remains == 0 then
		self.elemental_remains = StormElemental:Remains()
	end
	if EarthElemental.known and self.elemental_remains == 0 then
		self.elemental_remains = EarthElemental:Remains()
	end
end

-- End Player API

-- Start Target API

function Target:UpdateHealth()
	timer.health = 0
	self.health = UnitHealth('target')
	self.health_max = UnitHealthMax('target')
	table.remove(self.health_array, 1)
	self.health_array[25] = self.health
	self.timeToDieMax = self.health / Player.health_max * 25
	self.healthPercentage = self.health_max > 0 and (self.health / self.health_max * 100) or 100
	self.healthLostPerSec = (self.health_array[1] - self.health) / 5
	self.timeToDie = self.healthLostPerSec > 0 and min(self.timeToDieMax, self.health / self.healthLostPerSec) or self.timeToDieMax
end

function Target:Update()
	UI:Disappear()
	if UI:ShouldHide() then
		return
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.boss = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = UnitLevel('player')
		self.hostile = true
		local i
		for i = 1, 25 do
			self.health_array[i] = 0
		end
		self:UpdateHealth()
		if Opt.always_on then
			UI:UpdateCombat()
			farseerPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			farseerPreviousPanel:Hide()
		end
		return
	end
	if guid ~= self.guid then
		self.guid = guid
		local i
		for i = 1, 25 do
			self.health_array[i] = UnitHealth('target')
		end
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self:UpdateHealth()
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= UnitLevel('player') + 2) then
			self.boss = true
			self.stunnable = false
		elseif Player.instance == 'raid' or (self.health_max > Player.health_max * 10) then
			self.stunnable = false
		end
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		farseerPanel:Show()
		return true
	end
end

-- End Target API

-- Start Ability Modifications

local function TotemRemains(self)
	local _, i, start, duration, icon
	for i = 1, MAX_TOTEMS do
		_, _, start, duration, icon = GetTotemInfo(i)
		if icon and icon == (self.totem_icon or self.icon) then
			return max(0, start + duration - Player.ctime - Player.execute_remains)
		end
	end
	if (Player.time - self.last_used) < 1 then -- assume full duration immediately when dropped
		return self:Duration()
	end
	return 0
end
LiquidMagmaTotem.Remains = TotemRemains

function WindfuryTotem:Remains()
	local remains = Ability.Remains(self)
	if remains == 0 then
		return 0
	end
	return TotemRemains(self)
end

local function PetRemains(self)
	if not PrimalElementalist.known then
		return TotemRemains(self)
	end
	if Player.pet_active then
		local npcId = Player.pet:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
		if npcId and tonumber(npcId) == self.npc_id then
			return max(0, (self.summon_time or 0) + self:Duration() - Player.time - Player.execute_remains)
		end
	end
	return 0
end
EarthElemental.Remains = PetRemains
FireElemental.Remains = PetRemains
StormElemental.Remains = PetRemains

function FireElemental:Duration()
	local duration = self.buff_duration
	if CallOfFlame.known then
		duration = duration * (1.35 + (CallOfFlame.rank - 1) * 0.01)
	end
	return duration
end
StormElemental.Duration = FireElemental.Duration

local function WeaponEnchantRemains(self)
	local _, remainsMH, chargesMH, idMH, _, remainsOH, chargesOH, idOH = GetWeaponEnchantInfo()
	if idMH and idMH == self.enchant_id then
		return remainsMH / 1000, chargesMH
	end
	if idOH and idOH == self.enchant_id then
		return remainsOH / 1000, chargesOH
	end
	return 0, 0
end
FlametongueWeapon.Remains = WeaponEnchantRemains
WindfuryWeapon.Remains = WeaponEnchantRemains

function ChainLightning:MaelstromCost()
	return Ability.MaelstromCost(self) * min(5, Player:Enemies())
end

function FlameShock:Duration()
	local duration = Ability.Duration(self)
	if FireElemental.known and FireElemental:Up() then
		duration = duration * 2
	end
	return duration
end

function FlameShock:Remains()
	if PrimordialWave.known and PrimordialWave:Traveling() > 0 then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function MaelstromWeapon:Stack()
	local stack = Ability.Stack(self)
	if Player.ability_casting and Player.ability_casting.consume_mw then
		stack = stack - 5
	end
	return max(0, stack)
end

function Hailstorm:Stack()
	local stack = Ability.Stack(self)
	if Player.ability_casting and Player.ability_casting.consume_mw then
		stack = min(5, stack + Player.maelstrom_weapon)
	end
	return max(0, stack)
end

function Windstrike:Usable()
	if AscendanceAir:Down() then
		return false
	end
	return Ability.Usable(self)
end

function LavaBeam:Usable()
	if AscendanceFlame:Down() then
		return false
	end
	return Ability.Usable(self)
end

function DoomWinds:Cooldown()
	return self.cooldown:Remains()
end

function WindGust:Remains()
	return StormElemental:Remains()
end

function MasterOfTheElements:Remains()
	if LavaBurst:Casting() then
		return self:Duration()
	end
	local remains = Ability.Remains(self)
	if remains > 0 and (LightningBolt:Casting() or ChainLightning:Casting() or (Icefury.known and Icefury:Casting())) or (ElementalBlast.known and ElementalBlast:Casting()) then
		return 0
	end
	return remains
end

function StaticDischarge:Usable()
	if LightningShield:Down() then
		return false
	end
	return Ability.Usable(self)
end

-- End Ability Modifications

local function UseCooldown(ability, overwrite)
	if Opt.cooldown and (not Opt.boss_only or Target.boss) and (not Player.cd or overwrite) then
		Player.cd = ability
	end
end

local function UseExtra(ability, overwrite)
	if not Player.extra or overwrite then
		Player.extra = ability
	end
end

-- Begin Action Priority Lists

local APL = {
	[SPEC.NONE] = {
		main = function() end
	},
	[SPEC.ELEMENTAL] = {},
	[SPEC.ENHANCEMENT] = {},
	[SPEC.RESTORATION] = {},
}

APL[SPEC.ELEMENTAL].main = function(self)
	Player.use_cds = Opt.cooldown and (Target.boss or Target.player or (not Opt.boss_only and Target.timeToDie > Opt.cd_ttd) or (AscendanceFlame.known and AscendanceFlame:Up()) or (FireElemental.known and FireElemental:Up()) or (StormElemental.known and StormElemental:Up()))
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
actions.precombat+=/earth_elemental,if=!talent.primal_elementalist.enabled
# Use Stormkeeper precombat unless some adds will spawn soon.
actions.precombat+=/stormkeeper,if=talent.stormkeeper.enabled&(raid_event.adds.count<3|raid_event.adds.in>50)
actions.precombat+=/elemental_blast,if=talent.elemental_blast.enabled
actions.precombat+=/lava_burst,if=!talent.elemental_blast.enabled
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
actions.precombat+=/potion

]]
		if Opt.pot and not Player:InArenaOrBattleground() and SpectralFlaskOfPower:Usable() and SpectralFlaskOfPower.buff:Remains() < 300 then
			UseCooldown(GreaterFlaskOfEndlessFathoms)
		end
		if Opt.shield and LightningShield:Usable() and LightningShield:Remains() < 300 then
			UseCooldown(LightningShield)
		end
		if Opt.earth and Player.use_cds and EarthElemental:Usable() and not PrimalElementalist.known then
			UseExtra(EarthElemental)
		end
		if Player.use_cds and Stormkeeper:Usable() and Stormkeeper:Down() then
			UseCooldown(Stormkeeper)
		end
		if ElementalBlast:Usable() then
			return ElementalBlast
		end
		if LavaBurst:Usable() and LavaSurge:Down() and (not MasterOfTheElements.known or MasterOfTheElements:Down()) then
			return LavaBurst
		end
		if Opt.pot and Target.boss and not Player:InArenaOrBattleground() and PotionOfSpectralIntellect:Usable() then
			UseCooldown(PotionOfSpectralIntellect)
		end

	end
--[[
actions=spiritwalkers_grace,moving=1,if=movement.distance>6
# Interrupt of casts.
actions+=/wind_shear
actions+=/potion
actions+=/use_items
actions+=/flame_shock,if=!ticking
actions+=/fire_elemental
actions+=/storm_elemental
actions+=/blood_fury,if=!talent.ascendance.enabled|buff.ascendance.up|cooldown.ascendance.remains>50
actions+=/berserking,if=!talent.ascendance.enabled|buff.ascendance.up
actions+=/fireblood,if=!talent.ascendance.enabled|buff.ascendance.up|cooldown.ascendance.remains>50
actions+=/ancestral_call,if=!talent.ascendance.enabled|buff.ascendance.up|cooldown.ascendance.remains>50
actions+=/bag_of_tricks,if=!talent.ascendance.enabled|!buff.ascendance.up
actions+=/primordial_wave,target_if=min:dot.flame_shock.remains,cycle_targets=1,if=!buff.primordial_wave.up
actions+=/vesper_totem,if=covenant.kyrian
actions+=/fae_transfusion,if=covenant.night_fae
actions+=/run_action_list,name=aoe,if=active_enemies>2&(spell_targets.chain_lightning>2|spell_targets.lava_beam>2)
actions+=/run_action_list,name=single_target,if=!talent.storm_elemental.enabled&active_enemies<=2
actions+=/run_action_list,name=se_single_target,if=talent.storm_elemental.enabled&active_enemies<=2
]]
	if Player.moving and SpiritwalkersGrace:Usable() then
		UseExtra(SpiritwalkersGrace)
	end
	if FlameShock:Usable() and FlameShock:Down() then
		return FlameShock
	end
	if Player.use_cds then
		if FireElemental:Usable() then
			UseCooldown(FireElemental)
		end
		if StormElemental:Usable() then
			UseCooldown(StormElemental)
		end
	end
	if PrimordialWave:Usable() and PrimordialWave.buff:Down() then
		UseCooldown(PrimordialWave)
	end
	if Player:Enemies() > 2 then
		return self:aoe()
	end
	if StormElemental.known then
		return self:se_single_target()
	end
	return self:single_target()
end

APL[SPEC.ELEMENTAL].aoe = function(self)
--[[
actions.aoe=earthquake,if=buff.echoing_shock.up|buff.echoes_of_great_sundering.up&maelstrom>=(maelstrom.max-4*spell_targets.chain_lightning)
actions.aoe+=/chain_harvest
actions.aoe+=/stormkeeper,if=talent.stormkeeper.enabled
actions.aoe+=/flame_shock,if=!active_dot.flame_shock|runeforge.skybreakers_fiery_demise.equipped,target_if=refreshable
actions.aoe+=/echoing_shock,if=talent.echoing_shock.enabled&maelstrom>=60
actions.aoe+=/ascendance,if=talent.ascendance.enabled&(!pet.storm_elemental.active)&(!talent.icefury.enabled|!buff.icefury.up&!cooldown.icefury.up)
actions.aoe+=/liquid_magma_totem,if=talent.liquid_magma_totem.enabled
actions.aoe+=/earth_shock,if=runeforge.echoes_of_great_sundering.equipped&!buff.echoes_of_great_sundering.up
actions.aoe+=/earth_elemental,if=runeforge.deeptremor_stone.equipped&(!talent.primal_elementalist.enabled|(!pet.storm_elemental.active&!pet.fire_elemental.active))
actions.aoe+=/flame_shock,if=active_dot.flame_shock<3&active_enemies<=5,target_if=refreshable
actions.aoe+=/lava_burst,target_if=dot.flame_shock.remains,if=spell_targets.chain_lightning<4|buff.lava_surge.up|(talent.master_of_the_elements.enabled&!buff.master_of_the_elements.up&maelstrom>=60)
# Try to game Earthquake with Master of the Elements buff when fighting 3 targets. Don't overcap Maelstrom!
actions.aoe+=/earthquake,if=!talent.master_of_the_elements.enabled|buff.stormkeeper.up|maelstrom>=(maelstrom.max-4*spell_targets.chain_lightning)|buff.master_of_the_elements.up|spell_targets.chain_lightning>3
# Make sure you don't lose a Stormkeeper buff.
actions.aoe+=/chain_lightning,if=buff.stormkeeper.remains<3*gcd*buff.stormkeeper.stack
# Only cast Lava Burst on three targets if it is an instant and Storm Elemental is NOT active.
actions.aoe+=/lava_burst,if=buff.lava_surge.up&spell_targets.chain_lightning<4&(!pet.storm_elemental.active)&dot.flame_shock.ticking
# Use Elemental Blast against up to 3 targets as long as Storm Elemental is not active.
actions.aoe+=/elemental_blast,if=talent.elemental_blast.enabled&spell_targets.chain_lightning<5&(!pet.storm_elemental.active)
actions.aoe+=/lava_beam,if=talent.ascendance.enabled
actions.aoe+=/chain_lightning
actions.aoe+=/lava_burst,moving=1,if=buff.lava_surge.up&cooldown_react
actions.aoe+=/flame_shock,moving=1,target_if=refreshable
actions.aoe+=/frost_shock,moving=1
]]
	if Earthquake:Usable() and ((EchoingShock.known and EchoingShock:Up()) or (EchoesOfGreatSundering.known and EchoesOfGreatSundering:Up() and Player:MaelstromDeficit() < (4 * Player:Enemies()))) then
		return Earthquake
	end
	if Player.use_cds and ChainHarvest:Usable() then
		UseCooldown(ChainHarvest)
	end
	if Player.use_cds and Stormkeeper:Usable() and Stormkeeper:Down() then
		UseCooldown(Stormkeeper)
	end
	if FlameShock:Usable() and FlameShock:Refreshable() and Target.timeToDie > FlameShock:Remains() and (FlameShock:Ticking() == 0 or SkybreakersFieryDemise.known) then
		return FlameShock
	end
	if EchoingShock:Usable() and Player:Maelstrom() >= 60 then
		return EchoingShock
	end
	if Player.use_cds and AscendanceFlame:Usable() and (not StormElemental.known or StormElemental:Down()) and (not Icyfury.known or Icefury:Down() and not Icyfury:Ready()) then
		UseCooldown(AscendanceFlame)
	end
	if Player.use_cds and LiquidMagmaTotem:Usable() then
		UseCooldown(LiquidMagmaTotem)
	end
	if EchoesOfGreatSundering.known and EarthShock:Usable() and EchoesOfGreatSundering:Down() then
		return EarthShock
	end
	if Player.use_cds and EarthElemental:Usable() and (DeeptremorStone.known or Player:UnderAttack()) and (not PrimalElementalist.known or (StormElemental.known and StormElemental:Down() and not StormElemental:Ready(60)) or (FireElemental.known and FireElemental:Down() and not FireElemental:Ready(60))) then
		UseExtra(EarthElemental)
	end
	if FlameShock:Usable() and FlameShock:Refreshable() and Target.timeToDie > FlameShock:Remains() and Player:Enemies() <= 5 and FlameShock:Ticking() < 3 then
		return FlameShock
	end
	if LavaBurst:Usable() and FlameShock:Remains() > (LavaBurst:CastTime() + LavaBurst:TravelTime()) and (Player:Enemies() < 4 or LavaSurge:Up() or (MasterOfTheElements.known and MasterOfTheElements:Down() and Player:Maelstrom() >= 60)) then
		return LavaBurst
	end
	if Earthquake:Usable() and (not MasterOfTheElements.known or (Stormkeeper.known and Stormkeeper:Up()) or Player:MaelstromDeficit() < (4 * Player:Enemies()) or MasterOfTheElements:Up() or Player:Enemies() > 3) then
		return Earthquake
	end
	if Stormkeeper.known and ChainLightning:Usable() and Stormkeeper:Up() and Stormkeeper:Remains() < (3 * Player.gcd * Stormkeeper:Stack()) then
		return ChainLightning
	end
	if LavaBurst:Usable() and LavaSurge:Up() and Player:Enemies() < 4 and (not StormElemental.known or StormElemental:Down()) and FlameShock:Ticking() > 0 then
		return LavaBurst
	end
	if ElementalBlast:Usable() and Player:Enemies() < 5 and (not StormElemental.known or StormElemental:Down()) then
		return ElementalBlast
	end
	if LavaBeam:Usable() then
		return LavaBeam
	end
	if ChainLightning:Usable() then
		return ChainLightning
	end
	if Player.moving then
		if LavaBurst:Usable() and LavaSurge:Up() then
			return LavaBurst
		end
		if FlameShock:Usable() and FlameShock:Refreshable() then
			return FlameShock
		end
		if LightningShield:Usable() and LightningShield:Remains() < 30 then
			UseExtra(LightningShield)
		end
		if FrostShock:Usable() then
			return FrostShock
		end
	end
end

APL[SPEC.ELEMENTAL].se_single_target = function(self)
--[[
actions.se_single_target=flame_shock,target_if=(remains<=gcd)&(buff.lava_surge.up|!buff.bloodlust.up)
actions.se_single_target+=/elemental_blast,if=talent.elemental_blast.enabled
actions.se_single_target+=/stormkeeper,if=talent.stormkeeper.enabled&maelstrom<44
actions.se_single_target+=/echoing_shock,if=talent.echoing_shock.enabled
actions.se_single_target+=/lava_burst,if=maelstrom.max-maelstrom>10&((!talent.echo_of_the_elements.enabled|cooldown.lava_burst.charges_fractional>1.5)&buff.wind_gust.stack<18|buff.lava_surge.up&dot.flame_shock.remains>travel_time)
actions.se_single_target+=/earthquake,if=buff.echoes_of_great_sundering.up
actions.se_single_target+=/earthquake,if=!runeforge.echoes_of_great_sundering.equipped&spell_targets.chain_lightning>1&!dot.flame_shock.refreshable
actions.se_single_target+=/earth_shock,if=spell_targets.chain_lightning<2&maelstrom>=60&(buff.wind_gust.stack<20|maelstrom>90)|(runeforge.echoes_of_great_sundering.equipped&!buff.echoes_of_great_sundering.up)
actions.se_single_target+=/lightning_bolt,if=(buff.stormkeeper.remains<1.1*gcd*buff.stormkeeper.stack|buff.stormkeeper.up&buff.master_of_the_elements.up)
actions.se_single_target+=/frost_shock,if=talent.icefury.enabled&talent.master_of_the_elements.enabled&buff.icefury.up&buff.master_of_the_elements.up
actions.se_single_target+=/lava_burst,if=buff.ascendance.up
actions.se_single_target+=/lava_burst,if=cooldown_react&!talent.master_of_the_elements.enabled
actions.se_single_target+=/icefury,if=talent.icefury.enabled&!(maelstrom>75&cooldown.lava_burst.remains<=0)
actions.se_single_target+=/lava_burst,if=cooldown_react&charges>talent.echo_of_the_elements.enabled
actions.se_single_target+=/frost_shock,if=talent.icefury.enabled&buff.icefury.up
actions.se_single_target+=/chain_harvest
actions.se_single_target+=/static_discharge,if=talent.static_discharge.enabled
actions.se_single_target+=/earth_elemental,if=!talent.primal_elementalist.enabled|talent.primal_elementalist.enabled&(!pet.storm_elemental.active)
actions.se_single_target+=/chain_lightning,if=spell_targets.chain_lightning>1&buff.stormkeeper.down
actions.se_single_target+=/lightning_bolt
actions.se_single_target+=/flame_shock,moving=1,target_if=refreshable
actions.se_single_target+=/flame_shock,moving=1,if=movement.distance>6
actions.se_single_target+=/frost_shock,moving=1
]]
	if FlameShock:Usable() and FlameShock:Remains() <= Player.gcd and (LavaSurge:Up() or not Player:BloodlustActive()) then
		return FlameShock
	end
	if ElementalBlast:Usable() then
		return ElementalBlast
	end
	if Player.use_cds and Stormkeeper:Usable() and Player:Maelstrom() < 44 and Stormkeeper:Down() then
		UseCooldown(Stormkeeper)
	end
	if EchoingShock:Usable() then
		return EchoingShock
	end
	if LavaBurst:Usable() and Player:MaelstromDeficit() > 10 and (((not EchoOfTheElements.known or LavaBurst:ChargesFractional() > 1.5) and WindGust:Stack() < 18) or (LavaSurge:Up() and FlameShock:Remains() > LavaBurst:TravelTime())) then
		return LavaBurst
	end
	if Earthquake:Usable() then
		if EchoesOfGreatSundering.known and EchoesOfGreatSundering:Up() then
			return Earthquake
		end
		if not EchoesOfGreatSundering.known and Player:Enemies() > 1 and not FlameShock:Refreshable() then
			return Earthquake
		end
	end
	if EarthShock:Usable() then
		if EchoesOfGreatSundering.known and EchoesOfGreatSundering:Down() then
			return EarthShock
		end
		if Player:Enemies() < 2 and Player:Maelstrom() >= 60 and ((WindGust.known and WindGust:Stack() < 20) or Player:Maelstrom() > 90) then
			return EarthShock
		end
	end
	if Stormkeeper.known and LightningBolt:Usable() and Stormkeeper:Up() and ((MasterOfTheElements.known and MasterOfTheElements:Up()) or Stormkeeper:Remains() < (1.1 * Player.gcd * Stormkeeper:Stack())) then
		return LightningBolt
	end
	if Icefury.known and MasterOfTheElements.known and FrostShock:Usable() and Icefury:Up() and MasterOfTheElements:Up() then
		return FrostShock
	end
	if LavaBurst:Usable() then
		if AscendanceFlame.known and AscendanceFlame:Up() then
			return LavaBurst
		end
		if not MasterOfTheElements.known then
			return LavaBurst
		end
	end
	if Icefury:Usable() and not (Player:Maelstrom() > 75 and LavaBurst:Ready()) then
		return Icefury
	end
	if LavaBurst:Usable() and LavaBurst:Charges() > (EchoOfTheElements.known and 1 or 0) then
		return LavaBurst
	end
	if Icefury.known and FrostShock:Usable() and Icefury:Up() then
		return FrostShock
	end
	if Player.use_cds and ChainHarvest:Usable() then
		UseCooldown(ChainHarvest)
	end
	if StaticDischarge:Usable() then
		return StaticDischarge
	end
	if StaticDischarge.known and LightningShield:Usable() and LightningShield:Down() then
		UseExtra(LightningShield)
	end
	if Opt.earth and Player.use_cds and EarthElemental:Usable() and (not PrimalElementalist.known or (StormElemental:Down() and not StormElemental:Ready(60))) then
		UseExtra(EarthElemental)
	end
	if ChainLightning:Usable() and Player:Enemies() > 1 and (not Stormkeeper.known or Stormkeeper:Down()) then
		return ChainLightning
	end
	if LightningBolt:Usable() then
		return LightningBolt
	end
	if Player.moving then
		if FlameShock:Usable() and FlameShock:Refreshable() then
			return FlameShock
		end
		if LightningShield:Usable() and LightningShield:Remains() < 30 then
			UseExtra(LightningShield)
		end
		if FrostShock:Usable() then
			return FrostShock
		end
	end
end

APL[SPEC.ELEMENTAL].single_target = function(self)
--[[
actions.single_target=flame_shock,target_if=(!ticking|dot.flame_shock.remains<=gcd|talent.ascendance.enabled&dot.flame_shock.remains<(cooldown.ascendance.remains+buff.ascendance.duration)&cooldown.ascendance.remains<4)&(buff.lava_surge.up|!buff.bloodlust.up)
actions.single_target+=/ascendance,if=talent.ascendance.enabled&(time>=60|buff.bloodlust.up)&(cooldown.lava_burst.remains>0)&(!talent.icefury.enabled|!buff.icefury.up&!cooldown.icefury.up)
actions.single_target+=/lightning_bolt,if=buff.stormkeeper.up&buff.stormkeeper.remains<1.1*gcd*buff.stormkeeper.stack
actions.single_target+=/earthquake,if=buff.echoes_of_great_sundering.up&(buff.master_of_the_elements.up|maelstrom.max-maelstrom<9)
actions.single_target+=/lava_burst,if=buff.echoes_of_great_sundering.up&talent.master_of_the_elements.enabled&buff.master_of_the_elements.down&maelstrom>=50
actions.single_target+=/earth_shock,if=maelstrom.max-maelstrom<8
actions.single_target+=/stormkeeper,if=maelstrom<44&(raid_event.adds.count<3|raid_event.adds.in>50)
actions.single_target+=/echoing_shock,if=talent.echoing_shock.enabled&!cooldown.lava_burst.remains
actions.single_target+=/lava_burst,if=talent.echoing_shock.enabled&buff.echoing_shock.up
actions.single_target+=/liquid_magma_totem,if=talent.liquid_magma_totem.enabled
actions.single_target+=/lightning_bolt,if=buff.stormkeeper.up&buff.master_of_the_elements.up
actions.single_target+=/earthquake,if=buff.echoes_of_great_sundering.up&(!talent.master_of_the_elements.enabled|cooldown.elemental_blast.remains<=1.1*gcd*2|cooldown.lava_burst.remains>0&maelstrom>=92|spell_targets.chain_lightning<2&buff.stormkeeper.up&cooldown.lava_burst.remains<=gcd)
actions.single_target+=/earthquake,if=spell_targets.chain_lightning>1&!dot.flame_shock.refreshable&!runeforge.echoes_of_great_sundering.equipped&(!talent.master_of_the_elements.enabled|buff.master_of_the_elements.up|cooldown.lava_burst.remains>0&maelstrom>=92)
actions.single_target+=/earth_shock,if=!talent.master_of_the_elements.enabled|buff.master_of_the_elements.up|spell_targets.chain_lightning<2&buff.stormkeeper.up&cooldown.lava_burst.remains<=gcd
actions.single_target+=/frost_shock,if=talent.icefury.enabled&talent.master_of_the_elements.enabled&buff.icefury.up&buff.master_of_the_elements.up
actions.single_target+=/elemental_blast,if=maelstrom<60|!talent.master_of_the_elements.enabled|!buff.master_of_the_elements.up
actions.single_target+=/lava_burst,if=buff.ascendance.up
actions.single_target+=/lava_burst,if=cooldown_react&!talent.master_of_the_elements.enabled
actions.single_target+=/icefury,if=maelstrom.max-maelstrom>25
actions.single_target+=/lava_burst,if=cooldown_react&charges>talent.echo_of_the_elements.enabled
actions.single_target+=/frost_shock,if=talent.icefury.enabled&buff.icefury.up&buff.icefury.remains<1.1*gcd*buff.icefury.stack
actions.single_target+=/lava_burst,if=cooldown_react&buff.master_of_the_elements.down
actions.single_target+=/flame_shock,target_if=refreshable
actions.single_target+=/earthquake,if=spell_targets.chain_lightning>1&!runeforge.echoes_of_great_sundering.equipped|buff.echoes_of_great_sundering.up
actions.single_target+=/frost_shock,if=talent.icefury.enabled&buff.icefury.up&(buff.icefury.remains<gcd*4*buff.icefury.stack|buff.stormkeeper.up|!talent.master_of_the_elements.enabled)
actions.single_target+=/frost_shock,if=runeforge.elemental_equilibrium.equipped&!buff.elemental_equilibrium_debuff.up&!talent.elemental_blast.enabled&!talent.echoing_shock.enabled
actions.single_target+=/chain_harvest
actions.single_target+=/static_discharge,if=talent.static_discharge.enabled
actions.single_target+=/earth_elemental,if=!talent.primal_elementalist.enabled|!pet.fire_elemental.active
actions.single_target+=/chain_lightning,if=spell_targets.chain_lightning>1&buff.stormkeeper.down
actions.single_target+=/lightning_bolt
actions.single_target+=/flame_shock,moving=1,target_if=refreshable
actions.single_target+=/flame_shock,moving=1,if=movement.distance>6
actions.single_target+=/frost_shock,moving=1
]]
	if FlameShock:Usable() and (FlameShock:Ticking() == 0 or FlameShock:Remains() < Player.gcd or (AscendanceFlame.known and AscendanceFlame:Ready(4) and FlameShock:Remains() < (AscendanceFlame:Cooldown() + AscendanceFlame:Duration()))) and (LavaSurge:Up() or not Player:BloodlustActive()) then
		return FlameShock
	end
	if Player.use_cds and AscendanceFlame:Usable() and not LavaBurst:Ready() and (Player:TimeInCombat() >= 60 or Player:BloodlustActive()) and (not Icefury.known or Icefury:Down() and not Icefury:Ready()) then
		UseCooldown(AscendanceFlame)
	end
	if Stormkeeper.known and LightningBolt:Usable() and Stormkeeper:Up() and Stormkeeper:Remains() < (1.1 * Player.gcd * Stormkeeper:Stack()) then
		return LightningBolt
	end
	if EchoesOfGreatSundering.known and MasterOfTheElements.known and EchoesOfGreatSundering:Up() then
		if Earthquake:Usable() and (MasterOfTheElements:Up() or Player:MaelstromDeficit() < 8) then
			return Earthquake
		end
		if LavaBurst:Usable() and Player:Maelstrom() >= 50 and MasterOfTheElements:Down() then
			return LavaBurst
		end
	end
	if EarthShock:Usable() and Player:MaelstromDeficit() < 8 then
		return EarthShock
	end
	if Player.use_cds and Stormkeeper:Usable() and Player:Maelstrom() < 44 and Stormkeeper:Down() then
		UseCooldown(Stormkeeper)
	end
	if EchoingShock.known then
		if EchoingShock:Usable() and LavaBurst:Ready() then
			return EchoingShock
		end
		if LavaBurst:Usable() and EchoingShock:Up() then
			return LavaBurst
		end
	end
	if Player.use_cds and LiquidMagmaTotem:Usable() then
		UseCooldown(LiquidMagmaTotem)
	end
	if Stormkeeper.known and MasterOfTheElements.known and LightningBolt:Usable() and Stormkeeper:Up() and MasterOfTheElements:Up() then
		return LightningBolt
	end
	if Earthquake:Usable() then
		if EchoesOfGreatSundering.known then
			if EchoesOfGreatSundering:Up() and (not MasterOfTheElements.known or (ElementalBlast.known and ElementalBlast:Ready(1.1 * Player.gcd * 2)) or (Stormkeeper.known and Player:Enemies() < 2 and Stormkeeper:Up() and LavaBurst:Ready(Player.gcd))) then
				return Earthquake
			end
		elseif Player:Enemies() > 1 and not FlameShock:Refreshable() and (not MasterOfTheElements.known or MasterOfTheElements:Up() or (not LavaBurst:Ready() and Player:Maelstrom() >= 92)) then
			return Earthquake
		end
	end
	if EarthShock:Usable() and (not MasterOfTheElements.known or MasterOfTheElements:Up() or (not LavaBurst:Ready() and Player:Maelstrom() >= 92) or (Stormkeeper.known and Player:Enemies() < 2 and Stormkeeper:Up() and LavaBurst:Ready(Player.gcd))) then
		return EarthShock
	end
	if Icefury.known and MasterOfTheElements.known and FrostShock:Usable() and Icefury:Up() and MasterOfTheElements:Up() then
		return FrostShock
	end
	if ElementalBlast:Usable() and (Player:Maelstrom() < 60 or not MasterOfTheElements.known or MasterOfTheElements:Down()) then
		return ElementalBlast
	end
	if LavaBurst:Usable() then
		if AscendanceFlame.known and AscendanceFlame:Up() then
			return LavaBurst
		end
		if not MasterOfTheElements.known then
			return LavaBurst
		end
	end
	if Icefury:Usable() and Player:MaelstromDeficit() > 25 then
		return Icefury
	end
	if LavaBurst:Usable() and LavaBurst:Charges() > (EchoOfTheElements.known and 1 or 0) then
		return LavaBurst
	end
	if Icefury.known and FrostShock:Usable() and Icefury:Up() and Icefury:Remains() < (1.1 * Player.gcd * Icefury:Stack()) then
		return FrostShock
	end
	if LavaBurst:Usable() and (not MasterOfTheElements.known or MasterOfTheElements:Down()) then
		return LavaBurst
	end
	if FlameShock:Usable() and FlameShock:Refreshable() then
		return FlameShock
	end
	if Earthquake:Usable() and Player:Enemies() > 1 and (not EchoesOfGreatSundering.known or EchoesOfGreatSundering:Up()) then
		return Earthquake
	end
	if Icefury.known and FrostShock:Usable() and Icefury:Up() and (not MasterOfTheElements.known or Icefury:Remains() < (Player.gcd * 4 * Icefury:Stack()) or (Stormkeeper.known and Stormkeeper:Up())) then
		return FrostShock
	end
	if ElementalEquilibrium.known and not ElementalBlast.known and not EchoingShock.known and FrostShock:Usable() and ElementalEquilibrium.debuff:Down() then
		return FrostShock
	end
	if Player.use_cds and ChainHarvest:Usable() then
		UseCooldown(ChainHarvest)
	end
	if StaticDischarge:Usable() then
		return StaticDischarge
	end
	if StaticDischarge.known and LightningShield:Usable() and LightningShield:Down() then
		UseExtra(LightningShield)
	end
	if Opt.earth and Player.use_cds and EarthElemental:Usable() and (not PrimalElementalist.known or (FireElemental:Down() and not FireElemental:Ready(60))) then
		UseExtra(EarthElemental)
	end
	if ChainLightning:Usable() and Player:Enemies() > 1 and (not Stormkeeper.known or Stormkeeper:Down()) then
		return ChainLightning
	end
	if LightningBolt:Usable() then
		return LightningBolt
	end
	if Player.moving then
		if LightningShield:Usable() and LightningShield:Remains() < 30 then
			UseExtra(LightningShield)
		end
		if FrostShock:Usable() then
			return FrostShock
		end
	end
end

APL[SPEC.ENHANCEMENT].main = function(self)
	Player.use_cds = Opt.cooldown and (Target.boss or Target.player or (not Opt.boss_only and Target.timeToDie > Opt.cd_ttd) or AscendanceAir:Up() or FeralSpirit:Up())
	if Player:HealthPct() < 60 and Player.maelstrom_weapon >= 5 and HealingSurge:Usable() then
		UseExtra(HealingSurge)
	end
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
actions.precombat+=/windfury_weapon
actions.precombat+=/flametongue_weapon
actions.precombat+=/lightning_shield
actions.precombat+=/stormkeeper,if=talent.stormkeeper.enabled
actions.precombat+=/windfury_totem
actions.precombat+=/potion
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
]]
		if not Player:InArenaOrBattleground() then
			if Opt.pot and SpectralFlaskOfPower:Usable() and SpectralFlaskOfPower.buff:Remains() < 300 then
				UseCooldown(SpectralFlaskOfPower)
			end
			if Opt.pot and Target.boss and PotionOfSpectralIntellect:Usable() then
				UseCooldown(PotionOfSpectralIntellect)
			end
		end
		if WindfuryWeapon:Usable() and WindfuryWeapon:Remains() < 300 then
			UseCooldown(WindfuryWeapon)
		end
		if FlametongueWeapon:Usable() and FlametongueWeapon:Remains() < 300 then
			UseCooldown(FlametongueWeapon)
		end
		if WindfuryTotem:Usable() and WindfuryTotem:Remains() < 30 and (not DoomWinds.known or not DoomWinds:Ready(6)) then
			UseCooldown(WindfuryTotem)
		end
		if Opt.shield and LightningShield:Usable() and LightningShield:Remains() < 300 then
			UseCooldown(LightningShield)
		end
		if Opt.earth and Player.use_cds and EarthElemental:Usable() and not PrimalElementalist.known then
			UseExtra(EarthElemental)
		end
		if Hailstorm.known and FrostShock:Usable() and Hailstorm:Stack() >= 5 then
			return FrostShock
		end
		if Player.maelstrom_weapon >= 5 then
			local apl = self:spenders()
			if apl then return apl end
		end
		if FlameShock:Usable() and (not Hailstorm.known or Hailstorm:Stack() <= 3) then
			return FlameShock
		end
	else
		if WindfuryWeapon:Usable() and WindfuryWeapon:Down() then
			UseExtra(WindfuryWeapon)
		end
		if FlametongueWeapon:Usable() and FlametongueWeapon:Down() then
			UseExtra(FlametongueWeapon)
		end
	end
--[[
actions=bloodlust
actions+=/wind_shear
actions+=/auto_attack
actions+=/potion,if=expected_combat_length-time<60
actions+=/use_items,if=buff.feral_spirit.remains>6
actions+=/frost_shock,if=talent.hailstorm.enabled&buff.hailstorm.stack>=5&(buff.hailstorm.remains<gcd*2|buff.maelstrom_weapon.stack>=9)
actions+=/chain_harvest,if=buff.maelstrom_weapon.stack>=9|(buff.maelstrom_weapon.stack>=5&buff.maelstrom_weapon.remains<gcd*2)
actions+=/elemental_blast,if=active_enemies<4&(buff.maelstrom_weapon.stack>=9|(buff.maelstrom_weapon.stack>=5&buff.maelstrom_weapon.remains<gcd*2))
actions+=/chain_lightning,if=active_enemies>1&(buff.maelstrom_weapon.stack>=9|(buff.maelstrom_weapon.stack>=5&buff.maelstrom_weapon.remains<gcd*2))
actions+=/lightning_bolt,if=buff.maelstrom_weapon.stack>=9|(buff.maelstrom_weapon.stack>=5&buff.maelstrom_weapon.remains<gcd*2)
actions+=/frost_shock,if=active_enemies>1&talent.hailstorm.enabled&buff.hailstorm.stack>=5
actions+=/crash_lightning,if=active_enemies>1&buff.crash_lightning.down
actions+=/windstrike
actions+=/primordial_wave,if=!buff.primordial_wave.up
actions+=/lightning_bolt,if=buff.primordial_wave.up&buff.maelstrom_weapon.stack>=5
actions+=/flame_shock,if=!remains&talent.lashing_flames.enabled&active_enemies=1&target.time_to_die>(4*spell_haste)
actions+=/stormstrike
actions+=/lava_lash
actions+=/flame_shock,if=!remains&(!talent.hailstorm.enabled|(active_enemies=1&buff.hailstorm.stack<=3))&target.time_to_die>(8*spell_haste)
actions+=/sundering
actions+=/feral_spirit
actions+=/flame_shock,if=refreshable&(!talent.hailstorm.enabled|(active_enemies=1&(talent.lashing_flames.enabled|buff.hailstorm.stack<=3)))&target.time_to_die>(remains+8*spell_haste)
actions+=/frost_shock,if=!talent.hailstorm.enabled|buff.hailstorm.up
actions+=/chain_harvest,if=buff.maelstrom_weapon.stack>=5&(!talent.hailstorm.enabled|buff.hailstorm.stack<5)
actions+=/elemental_blast,if=buff.maelstrom_weapon.stack>=5&active_enemies<4&(!talent.hailstorm.enabled|buff.hailstorm.stack<5)
actions+=/chain_lightning,if=buff.maelstrom_weapon.stack>=5&active_enemies>1&(!talent.hailstorm.enabled|buff.hailstorm.stack<5)
actions+=/lightning_bolt,if=buff.maelstrom_weapon.stack>=5&(!talent.hailstorm.enabled|buff.hailstorm.stack<5)
actions+=/crash_lightning,if=active_enemies>1
actions+=/earth_elemental,if=buff.feral_spirit.down
actions+=/crash_lightning
actions+=/flame_shock,target_if=min:remains,if=remains<(10*spell_haste)&target.time_to_die>(remains+4*spell_haste)
actions+=/windfury_totem,if=buff.windfury_totem.remains<30
actions+=/frost_shock
]]
	if Player.use_cds and ((not FeralSpirit.known and not AscendanceAir.known) or FeralSpirit:Remains() > 6 or AscendanceAir:Remains() > 6) then
		if Opt.trinket then
			if Trinket1:Usable() then
				UseCooldown(Trinket1)
			elseif Trinket2:Usable() then
				UseCooldown(Trinket2)
			end
		end
	end
	if Hailstorm.known and FrostShock:Usable() and Hailstorm:Stack() >= 5 and (between(Hailstorm:Remains(), 0.1, Player.gcd * 2) or Player.maelstrom_weapon >= 9) then
		return FrostShock
	end
	if (Player.maelstrom_weapon >= 9 or (Player.maelstrom_weapon >= 5 and MaelstromWeapon:Remains() < Player.gcd * 2)) then
		local apl = self:spenders()
		if apl then return apl end
	end
	if Hailstorm.known and FrostShock:Usable() and Player:Enemies() > 1 and Hailstorm:Stack() >= 5 then
		return FrostShock
	end
	if CrashLightning:Usable() and Player:Enemies() > 1 and CrashLightning.buff:Down() then
		return CrashLightning
	end
	if DoomWinds.known then
		if DoomWinds:Ready() and WindfuryTotem:Usable() and (Player:Enemies() == 1 or (CrashLightning:Remains() > 6 and (not Sundering.known or Sundering:Ready(12)))) then
			UseCooldown(WindfuryTotem)
		elseif Sundering:Usable() and between(DoomWinds:Remains(), 0.2, 4) then
			UseCooldown(Sundering)
		end
	end
	if Windstrike:Usable() then
		return Windstrike
	end
	if PrimordialWave:Usable() and PrimordialWave.buff:Down() then
		UseCooldown(PrimordialWave)
	end
	if PrimordialWave.known and LightningBolt:Usable() and PrimordialWave.buff:Up() and Player.maelstrom_weapon >= 5 then
		return LightningBolt
	end
	if LashingFlames.known and FlameShock:Usable() and FlameShock:Down() and Player:Enemies() == 1 and Target.timeToDie > (4 * Player.haste_factor) then
		return FlameShock
	end
	if Stormstrike:Usable() then
		return Stormstrike
	end
	if LavaLash:Usable() then
		return LavaLash
	end
	if FlameShock:Usable() and FlameShock:Down() and (not Hailstorm.known or (Player:Enemies() == 1 and Hailstorm:Stack() <= 3)) and Target.timeToDie > (8 * Player.haste_factor) then
		return FlameShock
	end
	if Player.use_cds and AscendanceAir:Usable() then
		UseCooldown(AscendanceAir)
	elseif Sundering:Usable() and (not DoomWinds.known or Player:Enemies() == 1 or not DoomWinds:Ready(12)) then
		UseCooldown(Sundering)
	elseif Player.use_cds and FeralSpirit:Usable() then
		UseCooldown(FeralSpirit)
	end
	if FlameShock:Usable() and FlameShock:Refreshable() and (not Hailstorm.known or (Player:Enemies() == 1 and (LashingFlames.known or Hailstorm:Stack() <= 3))) and Target.timeToDie > (FlameShock:Remains() + 8 * Player.haste_factor) then
		return FlameShock
	end
	if FrostShock:Usable() and (not Hailstorm.known or Hailstorm:Up()) then
		return FrostShock
	end
	if Player.maelstrom_weapon >= 5 and (not Hailstorm.known or Hailstorm:Stack() < 5) then
		local apl = self:spenders()
		if apl then return apl end
	end
	if CrashLightning:Usable() and Player:Enemies() > 1 then
		return CrashLightning
	end
	if EarthElemental:Usable() and FeralSpirit:Down() and Player:UnderAttack() then
		UseExtra(EarthElemental)
	end
	if Stormstrike:Usable(Player.haste_factor) then
		return Stormstrike
	end
	if CrashLightning:Usable() then
		return CrashLightning
	end
	if FlameShock:Usable() and FlameShock:Remains() < (10 * Player.haste_factor) and Target.timeToDie > (FlameShock:Remains() + 4 * Player.haste_factor) then
		return FlameShock
	end
	if WindfuryWeapon:Usable() and WindfuryWeapon:Remains() < 30 then
		UseExtra(WindfuryWeapon)
	end
	if FlametongueWeapon:Usable() and FlametongueWeapon:Remains() < 30 then
		UseExtra(FlametongueWeapon)
	end
	if LightningShield:Usable() and LightningShield:Remains() < 30 then
		UseExtra(LightningShield)
	end
	if Opt.earth and EarthElemental:Usable() then
		UseExtra(EarthElemental)
	end
	if WindfuryTotem:Usable() and WindfuryTotem:Remains() < 30 then
		return WindfuryTotem
	end
	if FrostShock:Usable() then
		return FrostShock
	end
end

APL[SPEC.ENHANCEMENT].spenders = function(self)
	if ChainHarvest:Usable() then
		UseCooldown(ChainHarvest, true)
	end
	if ElementalBlast:Usable() and Player:Enemies() < 4 then
		return ElementalBlast
	end
	if ChainLightning:Usable() and Player:Enemies() > 1 then
		return ChainLightning
	end
	if LightningBolt:Usable() then
		return LightningBolt
	end
end

APL[SPEC.RESTORATION].main = function(self)
	if Player:TimeInCombat() == 0 then
		if not Player:InArenaOrBattleground() then
			if Opt.pot and SpectralFlaskOfPower:Usable() and SpectralFlaskOfPower.buff:Remains() < 300 then
				UseCooldown(SpectralFlaskOfPower)
			end
		end
	end
end

APL.Interrupt = function(self)
	if WindShear:Usable() then
		return WindShear
	end
end

-- End Action Priority Lists

-- Start UI API

function UI.DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow, i
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.spark:SetVertexColor(r, g, b)
		glow.innerGlow:SetVertexColor(r, g, b)
		glow.innerGlowOver:SetVertexColor(r, g, b)
		glow.outerGlow:SetVertexColor(r, g, b)
		glow.outerGlowOver:SetVertexColor(r, g, b)
		glow.ants:SetVertexColor(r, g, b)
	end
end

function UI:CreateOverlayGlows()
	local b, i
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.button = button
			self.glows[#self.glows + 1] = glow
		end
	end
	for i = 1, 12 do
		GenerateGlow(_G['ActionButton' .. i])
		GenerateGlow(_G['MultiBarLeftButton' .. i])
		GenerateGlow(_G['MultiBarRightButton' .. i])
		GenerateGlow(_G['MultiBarBottomLeftButton' .. i])
		GenerateGlow(_G['MultiBarBottomRightButton' .. i])
	end
	for i = 1, 10 do
		GenerateGlow(_G['PetActionButton' .. i])
	end
	if Bartender4 then
		for i = 1, 120 do
			GenerateGlow(_G['BT4Button' .. i])
		end
	end
	if Dominos then
		for i = 1, 60 do
			GenerateGlow(_G['DominosActionButton' .. i])
		end
	end
	if ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['ElvUI_Bar' .. b .. 'Button' .. i])
			end
		end
	end
	if LUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['LUIBarBottom' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarLeft' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarRight' .. b .. 'Button' .. i])
			end
		end
	end
	UI:UpdateGlowColorAndScale()
end

function UI:UpdateGlows()
	local glow, icon, i
	for i = 1, #self.glows do
		glow = self.glows[i]
		icon = glow.button.icon:GetTexture()
		if icon and glow.button.icon:IsVisible() and (
			(Opt.glow.main and Player.main and icon == Player.main.icon) or
			(Opt.glow.cooldown and Player.cd and icon == Player.cd.icon) or
			(Opt.glow.interrupt and Player.interrupt and icon == Player.interrupt.icon) or
			(Opt.glow.extra and Player.extra and icon == Player.extra.icon)
			) then
			if not glow:IsVisible() then
				glow.animIn:Play()
			end
		elseif glow:IsVisible() then
			glow.animIn:Stop()
			glow:Hide()
		end
	end
end

function UI:UpdateDraggable()
	farseerPanel:EnableMouse(Opt.aoe or not Opt.locked)
	farseerPanel.button:SetShown(Opt.aoe)
	if Opt.locked then
		farseerPanel:SetScript('OnDragStart', nil)
		farseerPanel:SetScript('OnDragStop', nil)
		farseerPanel:RegisterForDrag(nil)
		farseerPreviousPanel:EnableMouse(false)
		farseerCooldownPanel:EnableMouse(false)
		farseerInterruptPanel:EnableMouse(false)
		farseerExtraPanel:EnableMouse(false)
	else
		if not Opt.aoe then
			farseerPanel:SetScript('OnDragStart', farseerPanel.StartMoving)
			farseerPanel:SetScript('OnDragStop', farseerPanel.StopMovingOrSizing)
			farseerPanel:RegisterForDrag('LeftButton')
		end
		farseerPreviousPanel:EnableMouse(true)
		farseerCooldownPanel:EnableMouse(true)
		farseerInterruptPanel:EnableMouse(true)
		farseerExtraPanel:EnableMouse(true)
	end
end

function UI:UpdateAlpha()
	farseerPanel:SetAlpha(Opt.alpha)
	farseerPreviousPanel:SetAlpha(Opt.alpha)
	farseerCooldownPanel:SetAlpha(Opt.alpha)
	farseerInterruptPanel:SetAlpha(Opt.alpha)
	farseerExtraPanel:SetAlpha(Opt.alpha)
end

function UI:UpdateScale()
	farseerPanel:SetSize(64 * Opt.scale.main, 64 * Opt.scale.main)
	farseerPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	farseerCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
	farseerInterruptPanel:SetSize(64 * Opt.scale.interrupt, 64 * Opt.scale.interrupt)
	farseerExtraPanel:SetSize(64 * Opt.scale.extra, 64 * Opt.scale.extra)
end

function UI:SnapAllPanels()
	farseerPreviousPanel:ClearAllPoints()
	farseerPreviousPanel:SetPoint('TOPRIGHT', farseerPanel, 'BOTTOMLEFT', -3, 40)
	farseerCooldownPanel:ClearAllPoints()
	farseerCooldownPanel:SetPoint('TOPLEFT', farseerPanel, 'BOTTOMRIGHT', 3, 40)
	farseerInterruptPanel:ClearAllPoints()
	farseerInterruptPanel:SetPoint('BOTTOMLEFT', farseerPanel, 'TOPRIGHT', 3, -21)
	farseerExtraPanel:ClearAllPoints()
	farseerExtraPanel:SetPoint('BOTTOMRIGHT', farseerPanel, 'TOPLEFT', -3, -21)
end

UI.anchor_points = {
	blizzard = { -- Blizzard Personal Resource Display (Default)
		[SPEC.ELEMENTAL] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
		[SPEC.ENHANCEMENT] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
		[SPEC.RESTORATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
	},
	kui = { -- Kui Nameplates
		[SPEC.ELEMENTAL] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 4 }
		},
		[SPEC.ENHANCEMENT] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 4 }
		},
		[SPEC.RESTORATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 4 }
		},
	},
}

function UI.OnResourceFrameHide()
	if Opt.snap then
		farseerPanel:ClearAllPoints()
	end
end

function UI.OnResourceFrameShow()
	if Opt.snap and UI.anchor.points then
		local p = UI.anchor.points[Player.spec][Opt.snap]
		farseerPanel:ClearAllPoints()
		farseerPanel:SetPoint(p[1], UI.anchor.frame, p[2], p[3], p[4])
		UI:SnapAllPanels()
	end
end

function UI:HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		self.anchor.points = self.anchor_points.kui
		self.anchor.frame = KuiNameplatesPlayerAnchor
	else
		self.anchor.points = self.anchor_points.blizzard
		self.anchor.frame = NamePlateDriverFrame:GetClassNameplateManaBar()
	end
	if self.anchor.frame then
		self.anchor.frame:HookScript('OnHide', self.OnResourceFrameHide)
		self.anchor.frame:HookScript('OnShow', self.OnResourceFrameShow)
	end
end

function UI:ShouldHide()
	return (Player.spec == SPEC.NONE or
		   (Player.spec == SPEC.ELEMENTAL and Opt.hide.elemental) or
		   (Player.spec == SPEC.ENHANCEMENT and Opt.hide.enhancement) or
		   (Player.spec == SPEC.RESTORATION and Opt.hide.restoration))
end

function UI:Disappear()
	farseerPanel:Hide()
	farseerPanel.icon:Hide()
	farseerPanel.border:Hide()
	farseerCooldownPanel:Hide()
	farseerInterruptPanel:Hide()
	farseerExtraPanel:Hide()
	Player.main = nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	UI:UpdateGlows()
end

function UI:UpdateDisplay()
	timer.display = 0
	local dim, text_tl, text_center
	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
	end
	if MaelstromWeapon.known then
		text_tl = Player.maelstrom_weapon
	end
	if Player.elemental_remains > 0 then
		text_center = format('%.1fs', Player.elemental_remains)
	end
	farseerPanel.dimmer:SetShown(dim)
	farseerPanel.text.tl:SetText(text_tl)
	farseerPanel.text.center:SetText(text_center)
	--farseerPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
end

function UI:UpdateCombat()
	timer.combat = 0

	Player:Update()

	Player.main = APL[Player.spec]:main()
	if Player.main then
		farseerPanel.icon:SetTexture(Player.main.icon)
	end
	if Player.cd then
		farseerCooldownPanel.icon:SetTexture(Player.cd.icon)
	end
	if Player.extra then
		farseerExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			farseerInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			farseerInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		farseerInterruptPanel.icon:SetShown(Player.interrupt)
		farseerInterruptPanel.border:SetShown(Player.interrupt)
		farseerInterruptPanel:SetShown(start and not notInterruptible)
	end
	farseerPanel.icon:SetShown(Player.main)
	farseerPanel.border:SetShown(Player.main)
	farseerCooldownPanel:SetShown(Player.cd)
	farseerExtraPanel:SetShown(Player.extra)

	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI API

-- Start Event Handling

function events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = Farseer
		if not Opt.frequency then
			print('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Farseer1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 10 then
			print('[|cFFFFD000Warning|r] ' .. ADDON .. ' is not designed for players under level 10, and almost certainly will not operate properly!')
		end
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		UI:SnapAllPanels()
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, _, srcGUID, _, _, _, dstGUID, _, _, _, spellId, spellName, _, missType = CombatLogGetCurrentEventInfo()
	Player.time = timeStamp
	Player.ctime = GetTime()
	Player.time_diff = Player.ctime - Player.time

	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		trackAuras:Remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:Remove(dstGUID)
		end
		return
	end
	if eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED' then
		if dstGUID == Player.guid then
			Player.last_swing_taken = Player.time
		end
		if Opt.auto_aoe then
			if dstGUID == Player.guid then
				autoAoe:Add(srcGUID, true)
			elseif srcGUID == Player.guid and not (missType == 'EVADE' or missType == 'IMMUNE') then
				autoAoe:Add(dstGUID, true)
			end
		end
	end

	if srcGUID ~= Player.guid then
		return
	end

	if eventType == 'SPELL_SUMMON' then
		if spellId == EarthElemental.summon_spell then
			EarthElemental.summon_time = timeStamp
		elseif spellId == FireElemental.summon_spell then
			FireElemental.summon_time = timeStamp
		elseif spellId == StormElemental.summon_spell then
			StormElemental.summon_time = timeStamp
		end
	end

	local ability = spellId and abilities.bySpellId[spellId]
	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', eventType, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
		return
	end

	if not (
	   eventType == 'SPELL_CAST_START' or
	   eventType == 'SPELL_CAST_SUCCESS' or
	   eventType == 'SPELL_CAST_FAILED' or
	   eventType == 'SPELL_DAMAGE' or
	   eventType == 'SPELL_ABSORBED' or
	   eventType == 'SPELL_PERIODIC_DAMAGE' or
	   eventType == 'SPELL_MISSED' or
	   eventType == 'SPELL_ENERGIZE' or
	   eventType == 'SPELL_AURA_APPLIED' or
	   eventType == 'SPELL_AURA_REFRESH' or
	   eventType == 'SPELL_AURA_REMOVED')
	then
		return
	end

	UI:UpdateCombatWithin(0.05)
	if eventType == 'SPELL_CAST_SUCCESS' then
		ability:CastSuccess(dstGUID, timeStamp)
		if Opt.previous and farseerPanel:IsVisible() then
			farseerPreviousPanel.ability = ability
			farseerPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
			farseerPreviousPanel.icon:SetTexture(ability.icon)
			farseerPreviousPanel:Show()
		end
		return
	end
	if dstGUID == Player.guid then
		return -- ignore buffs beyond here
	end
	if ability.aura_targets then
		if eventType == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if Opt.auto_aoe then
		if eventType == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (eventType == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and eventType == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		end
	end
	if eventType == 'SPELL_ABSORBED' or eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, timeStamp, eventType)
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and farseerPanel:IsVisible() and ability == farseerPreviousPanel.ability then
			farseerPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
		end
	end
end

function events:PLAYER_TARGET_CHANGED()
	Target:Update()
	if Player.rescan_abilities then
		Player:UpdateAbilities()
	end
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.last_swing_taken = 0
	Target.estimated_range = 30
	Player.previous_gcd = {}
	if Player.last_ability then
		Player.last_ability = nil
		farseerPreviousPanel:Hide()
	end
	local _, ability, guid
	for _, ability in next, abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
		end
	end
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability.auto_aoe.start_time = nil
			for guid in next, ability.auto_aoe.targets do
				ability.auto_aoe.targets[guid] = nil
			end
		end
		autoAoe:Clear()
		autoAoe:Update()
	end
end

function events:PLAYER_EQUIPMENT_CHANGED()
	local _, i, equipType, hasCooldown
	Trinket1.itemId = GetInventoryItemID('player', 13) or 0
	Trinket2.itemId = GetInventoryItemID('player', 14) or 0
	for _, i in next, Trinket do -- use custom APL lines for these trinkets
		if Trinket1.itemId == i.itemId then
			Trinket1.itemId = 0
		end
		if Trinket2.itemId == i.itemId then
			Trinket2.itemId = 0
		end
	end
	for i = 1, #inventoryItems do
		inventoryItems[i].name, _, _, _, _, _, _, _, equipType, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId or 0)
		inventoryItems[i].can_use = inventoryItems[i].name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, inventoryItems[i].equip_slot = Player:Equipped(inventoryItems[i].itemId)
			if inventoryItems[i].equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', inventoryItems[i].equip_slot)
			end
			inventoryItems[i].can_use = hasCooldown == 1
		end
		if Player.item_use_blacklist[inventoryItems[i].itemId] then
			inventoryItems[i].can_use = false
		end
	end
	Player:UpdateAbilities()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	farseerPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Target:Update()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, start, duration, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(61304)
		end
		farseerPanel.swipe:SetCooldown(start, duration)
	end
end

function events:UNIT_POWER_UPDATE(srcName, powerType)
	if srcName == 'player' and powerType == 'MAELSTROM' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_START(srcName)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(srcName)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_SUCCEEDED(srcName, castGUID, spellId)
	if srcName ~= 'player' or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = spellId and abilities.bySpellId[spellId]
	if not ability or not ability.traveling then
		return
	end
	ability.next_castGUID = castGUID
end

function events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateAbilities()
end

function events:SOULBIND_ACTIVATED()
	Player:UpdateAbilities()
end

function events:SOULBIND_NODE_UPDATED()
	Player:UpdateAbilities()
end

function events:SOULBIND_PATH_CHANGED()
	Player:UpdateAbilities()
end

function events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function events:PLAYER_ENTERING_WORLD()
	if #UI.glows == 0 then
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	local _
	_, Player.instance = IsInInstance()
	Player.guid = UnitGUID('player')
	events:PLAYER_SPECIALIZATION_CHANGED('player')
	Player:Update()
end

farseerPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			Player:ToggleTargetMode()
		elseif button == 'RightButton' then
			Player:ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			Player:SetTargetMode(1)
		end
	end
end)

farseerPanel:SetScript('OnUpdate', function(self, elapsed)
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

farseerPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
	farseerPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local ChatFrame_OnHyperlinkShow_Original = ChatFrame_OnHyperlinkShow
function ChatFrame_OnHyperlinkShow(chatFrame, link, ...)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		return BattleTagInviteFrame_Show(linkData)
	end
	return ChatFrame_OnHyperlinkShow_Original(chatFrame, link, ...)
end

local function Status(desc, opt, ...)
	local opt_view
	if type(opt) == 'string' then
		if opt:sub(1, 2) == '|c' then
			opt_view = opt
		else
			opt_view = '|cFFFFD000' .. opt .. '|r'
		end
	elseif type(opt) == 'number' then
		opt_view = '|cFFFFD000' .. opt .. '|r'
	else
		opt_view = opt and '|cFF00C000On|r' or '|cFFC00000Off|r'
	end
	print(ADDON, '-', desc .. ':', opt_view, ...)
end

SlashCmdList[ADDON] = function(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
			else
				Opt.snap = false
				farseerPanel:ClearAllPoints()
			end
			UI.OnResourceFrameShow()
		end
		return Status('Snap to the Personal Resource Display frame', Opt.snap)
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Previous ability icon scale', Opt.scale.previous, 'times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				UI:UpdateScale()
			end
			return Status('Main ability icon scale', Opt.scale.main, 'times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Cooldown ability icon scale', Opt.scale.cooldown, 'times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Interrupt ability icon scale', Opt.scale.interrupt, 'times')
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Extra cooldown ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UI:UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000extra 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
			UI:UpdateAlpha()
		end
		return Status('Icon transparency', Opt.alpha * 100 .. '%')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.2
		end
		return Status('Calculation frequency (max time to wait between each update): Every', Opt.frequency, 'seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (main icon)', Opt.glow.main)
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (cooldown icon)', Opt.glow.cooldown)
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (interrupt icon)', Opt.glow.interrupt)
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (extra cooldown icon)', Opt.glow.extra)
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Blizzard default proc glow', Opt.glow.blizzard)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			Target:Update()
		end
		return Status('Previous ability icon', Opt.previous)
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			Target:Update()
		end
		return Status('Show the ' .. ADDON .. ' UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use ' .. ADDON .. ' for cooldown management', Opt.cooldown)
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
		end
		return Status('Spell casting swipe animation', Opt.spell_swipe)
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
		end
		return Status('Dim main ability icon when you don\'t have enough resources to use it', Opt.dimmer)
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return Status('Red border around previous ability when it fails to hit', Opt.miss_effect)
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			Player:SetTargetMode(1)
			UI:UpdateDraggable()
		end
		return Status('Allow clicking main ability icon to toggle amount of targets (disables moving)', Opt.aoe)
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return Status('Only use cooldowns on bosses', Opt.boss_only)
	end
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'el') then
				Opt.hide.elemental = not Opt.hide.elemental
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Elemental specialization', not Opt.hide.elemental)
			end
			if startsWith(msg[2], 'en') then
				Opt.hide.enhancement = not Opt.hide.enhancement
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Enhancement specialization', not Opt.hide.enhancement)
			end
			if startsWith(msg[2], 'r') then
				Opt.hide.restoration = not Opt.hide.restoration
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Restoration specialization', not Opt.hide.restoration)
			end
		end
		return Status('Possible hidespec options', '|cFFFFD000elemental|r/|cFFFFD000enhancement|r/|cFFFFD000restoration|r')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return Status('Show an icon for interruptable spells', Opt.interrupt)
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return Status('Automatically change target mode on AoE spells', Opt.auto_aoe)
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return Status('Length of time target exists in auto AoE after being hit', Opt.auto_aoe_ttl, 'seconds')
	end
	if msg[1] == 'ttd' then
		if msg[2] then
			Opt.cd_ttd = tonumber(msg[2]) or 8
		end
		return Status('Minimum enemy lifetime to use cooldowns on (ignored on bosses)', Opt.cd_ttd, 'seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return Status('Show flasks and battle potions in cooldown UI', Opt.pot)
	end
	if startsWith(msg[1], 'tri') then
		if msg[2] then
			Opt.trinket = msg[2] == 'on'
		end
		return Status('Show on-use trinkets in cooldown UI', Opt.trinket)
	end
	if startsWith(msg[1], 'sh') then
		if msg[2] then
			Opt.shield = msg[2] == 'on'
		end
		return Status('Show Lightning Shield refresh reminder out of combat', Opt.shield)
	end
	if startsWith(msg[1], 'ea') then
		if msg[2] then
			Opt.earth = msg[2] == 'on'
		end
		return Status('Use Earth Elemental as a DPS cooldown (still uses after melee hits)', Opt.earth)
	end
	if msg[1] == 'reset' then
		farseerPanel:ClearAllPoints()
		farseerPanel:SetPoint('CENTER', 0, -169)
		UI:SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the ' .. ADDON .. ' UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use ' .. ADDON .. ' for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000elemental|r/|cFFFFD000enhancement|r/|cFFFFD000restoration|r - toggle disabling ' .. ADDON .. ' for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r  - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'shield |cFF00C000on|r/|cFFC00000off|r - show Lightning Shield refresh reminder out of combat',
		'earth |cFF00C000on|r/|cFFC00000off|r - use Earth Elemental as a DPS cooldown (still uses after melee hits)',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_Farseer1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
