local ADDON = 'Farseer'
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

BINDING_CATEGORY_FARSEER = ADDON
BINDING_NAME_FARSEER_TARGETMORE = "Toggle Targets +"
BINDING_NAME_FARSEER_TARGETLESS = "Toggle Targets -"
BINDING_NAME_FARSEER_TARGET1 = "Set Targets to 1"
BINDING_NAME_FARSEER_TARGET2 = "Set Targets to 2"
BINDING_NAME_FARSEER_TARGET3 = "Set Targets to 3"
BINDING_NAME_FARSEER_TARGET4 = "Set Targets to 4"
BINDING_NAME_FARSEER_TARGET5 = "Set Targets to 5+"

local function log(...)
	print(ADDON, '-', ...)
end

if select(2, UnitClass('player')) ~= 'SHAMAN' then
	log('[|cFFFF0000Error|r]', 'Not loading because you are not the correct class! Consider disabling', ADDON, 'for this character.')
	return
end

-- reference heavily accessed global functions from local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
local GetPowerRegenForPowerType = _G.GetPowerRegenForPowerType
local GetShapeshiftForm = _G.GetShapeshiftForm
local GetSpellCharges = C_Spell.GetSpellCharges
local GetSpellCooldown = C_Spell.GetSpellCooldown
local GetSpellInfo = C_Spell.GetSpellInfo
local GetItemCount = C_Item.GetItemCount
local GetItemCooldown = C_Item.GetItemCooldown
local GetInventoryItemCooldown = _G.GetInventoryItemCooldown
local GetItemInfo = C_Item.GetItemInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local IsSpellUsable = C_Spell.IsSpellUsable
local IsItemUsable = C_Item.IsUsableItem
local UnitAttackSpeed = _G.UnitAttackSpeed
local UnitAura = C_UnitAuras.GetAuraDataByIndex
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitSpellHaste = _G.UnitSpellHaste
-- end reference global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function clamp(n, min, max)
	return (n < min and min) or (n > max and max) or n
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
	return string.lower(str:sub(1, start:len())) == start:lower()
end

local function ToUID(guid)
	local uid = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	return uid and tonumber(uid)
end
-- end useful functions

Farseer = {}
local Opt -- use this as a local table reference to Farseer

SLASH_Farseer1, SLASH_Farseer2 = '/fs', '/farseer'

local function InitOpts()
	local function SetDefaults(t, ref)
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
			animation = false,
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
		heal = 60,
		shield = true,
		earth = true,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	glows = {},
}

-- combat event related functions container
local CombatEvent = {}

-- automatically registered events container
local Events = {}

-- player ability template
local Ability = {}
Ability.__index = Ability

-- classified player abilities
local Abilities = {
	all = {},
	bySpellId = {},
	velocity = {},
	autoAoe = {},
	trackAuras = {},
}

-- summoned pet template
local SummonedPet = {}
SummonedPet.__index = SummonedPet

-- classified summoned pets
local SummonedPets = {
	all = {},
	known = {},
	byUnitId = {},
}

-- methods for target tracking / aoe modes
local AutoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {},
}

-- timers for updating combat/display/hp info
local Timer = {
	combat = 0,
	display = 0,
	health = 0,
}

-- specialization constants
local SPEC = {
	NONE = 0,
	ELEMENTAL = 1,
	ENHANCEMENT = 2,
	RESTORATION = 3,
}

-- action priority list container
local APL = {
	[SPEC.NONE] = {},
	[SPEC.ELEMENTAL] = {},
	[SPEC.ENHANCEMENT] = {},
	[SPEC.RESTORATION] = {},
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	level = 1,
	spec = 0,
	group_size = 1,
	target_mode = 0,
	gcd = 1.5,
	gcd_remains = 0,
	execute_remains = 0,
	haste_factor = 1,
	moving = false,
	movement_speed = 100,
	health = {
		current = 0,
		max = 100,
		pct = 100,
	},
	mana = {
		base = 0,
		current = 0,
		max = 100,
		pct = 100,
		regen = 0,
	},
	maelstrom = {
		current = 0,
		max = 100,
		deficit = 100,
	},
	maelstrom_weapon = {
		current = 0,
		max = 10,
	},
	cast = {
		start = 0,
		ends = 0,
		remains = 0,
	},
	channel = {
		chained = false,
		start = 0,
		ends = 0,
		remains = 0,
		tick_count = 0,
		tick_interval = 0,
		ticks = 0,
		ticks_remain = 0,
		ticks_extra = 0,
		interruptible = false,
		early_chainable = false,
	},
	threat = {
		status = 0,
		pct = 0,
		lead = 0,
	},
	swing = {
		mh = {
			last = 0,
			speed = 0,
			remains = 0,
		},
		oh = {
			last = 0,
			speed = 0,
			remains = 0,
		},
		last_taken = 0,
	},
	set_bonus = {
		t29 = 0, -- Elements of Infused Earth
		t30 = 0, -- Runes of the Cinderwolf
		t31 = 0, -- Vision of the Greatwolf Outcast
		t32 = 0, -- Vision of the Greatwolf Outcast (Awakened)
		t33 = 0, -- Waves of the Forgotten Reservoir
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
		[190958] = true, -- Soleah's Secret Technique
		[193757] = true, -- Ruby Whelp Shell
		[202612] = true, -- Screaming Black Dragonscale
		[203729] = true, -- Ominous Chromatic Essence
	},
	main_freecast = false,
	elemental_remains = 0,
}

-- base mana pool max for each level
Player.BaseMana = {
	260,	270,	285,	300,	310,	--  5
	330,	345,	360,	380,	400,	-- 10
	430,	465,	505,	550,	595,	-- 15
	645,	700,	760,	825,	890,	-- 20
	965,	1050,	1135,	1230,	1335,	-- 25
	1445,	1570,	1700,	1845,	2000,	-- 30
	2165,	2345,	2545,	2755,	2990,	-- 35
	3240,	3510,	3805,	4125,	4470,	-- 40
	4845,	5250,	5690,	6170,	6685,	-- 45
	7245,	7855,	8510,	9225,	10000,	-- 50
	11745,	13795,	16205,	19035,	22360,	-- 55
	26265,	30850,	36235,	42565,	50000,	-- 60
	58730,	68985,	81030,	95180,	111800,	-- 65
	131325,	154255,	181190,	212830,	250000,	-- 70
}

-- current pet information (used only to store summoned pets for priests)
local Pet = {}

-- current target information
local Target = {
	boss = false,
	dummy = false,
	health = {
		current = 0,
		loss_per_sec = 0,
		max = 100,
		pct = 100,
		history = {},
	},
	hostile = false,
	estimated_range = 30,
}

-- target dummy unit IDs (count these units as bosses)
Target.Dummies = {
	[189617] = true,
	[189632] = true,
	[194643] = true,
	[194644] = true,
	[194648] = true,
	[194649] = true,
	[197833] = true,
	[198594] = true,
}

-- Start AoE

Player.target_modes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.ELEMENTAL] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
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

function AutoAoe:Add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local uid = ToUID(guid)
	if uid and self.ignored_units[uid] then
		self.blacklist[guid] = Player.time + 10
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = Player.time
	if update and new then
		self:Update()
	end
end

function AutoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function AutoAoe:Clear()
	for _, ability in next, Abilities.autoAoe do
		ability.auto_aoe.start_time = nil
		for guid in next, ability.auto_aoe.targets do
			ability.auto_aoe.targets[guid] = nil
		end
	end
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
	self:Update()
end

function AutoAoe:Update()
	local count = 0
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

function AutoAoe:Purge()
	local update
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

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		requires_react = false,
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
		summon_count = 0,
		max_range = 40,
		velocity = 0,
		last_gained = 0,
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or ''),
	}
	setmetatable(ability, self)
	Abilities.all[#Abilities.all + 1] = ability
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
	return self:Cooldown() <= (seconds or 0) and (not self.requires_react or self:React() > (seconds or 0))
end

function Ability:Usable(seconds)
	if not self.known then
		return false
	end
	if self:ManaCost() > Player.mana.current then
		return false
	end
	if Player.spec == SPEC.ELEMENTAL and self:MaelstromCost() > Player.maelstrom.current then
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
	local aura
	for i = 1, 40 do
		aura = UnitAura(self.aura_target, i, self.aura_filter)
		if not aura then
			return 0
		elseif self:Match(aura.spellId) then
			if aura.expirationTime == 0 then
				return 600 -- infinite duration
			end
			return max(0, aura.expirationTime - Player.ctime - (self.off_gcd and 0 or Player.execute_remains))
		end
	end
	return 0
end

function Ability:Expiring(seconds)
	local remains = self:Remains()
	return remains > 0 and remains < (seconds or Player.gcd)
end

function Ability:Refreshable()
	if self.buff_duration > 0 then
		return self:Remains() < self:Duration() * 0.3
	end
	return self:Down()
end

function Ability:Up(...)
	return self:Remains(...) > 0
end

function Ability:Down(...)
	return self:Remains(...) <= 0
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
	local count = 0
	for _, cast in next, self.traveling do
		if all or cast.dstGUID == Target.guid then
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity + (self.travel_delay or 0)
end

function Ability:Ticking()
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > (self.off_gcd and 0 or Player.execute_remains) then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				ticking[cast.dstGUID] = true
			end
		end
	end
	for _ in next, ticking do
		count = count + 1
	end
	return count
end

function Ability:HighestRemains()
	local highest
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				highest = self:Duration()
			end
		end
	end
	if self.aura_targets then
		local remains
		for _, aura in next, self.aura_targets do
			remains = max(0, aura.expires - Player.time - Player.execute_remains)
			if remains > 0 and (not highest or remains > highest) then
				highest = remains
			end
		end
	end
	return highest or 0
end

function Ability:LowestRemains()
	local lowest
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				lowest = self:Duration()
			end
		end
	end
	if self.aura_targets then
		local remains
		for _, aura in next, self.aura_targets do
			remains = max(0, aura.expires - Player.time - Player.execute_remains)
			if remains > 0 and (not lowest or remains < lowest) then
				lowest = remains
			end
		end
	end
	return lowest or 0
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local cooldown = GetSpellCooldown(self.spellId)
	if cooldown.startTime == 0 then
		return 0
	end
	return max(0, cooldown.duration - (Player.ctime - cooldown.startTime) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:CooldownExpected()
	if self.last_used == 0 then
		return self:Cooldown()
	end
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local cooldown = GetSpellCooldown(self.spellId)
	if cooldown.startTime == 0 then
		return 0
	end
	local remains = cooldown.duration - (Player.ctime - cooldown.startTime)
	local reduction = (Player.time - self.last_used) / (self:CooldownDuration() - remains)
	return max(0, (remains * reduction) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Stack()
	local aura
	for i = 1, 40 do
		aura = UnitAura(self.aura_target, i, self.aura_filter)
		if not aura then
			return 0
		elseif self:Match(aura.spellId) then
			return (aura.expirationTime == 0 or aura.expirationTime - Player.ctime > (self.off_gcd and 0 or Player.execute_remains)) and aura.applications or 0
		end
	end
	return 0
end

function Ability:ManaCost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * Player.mana.base) or 0
end

function Ability:MaelstromCost()
	return self.maelstrom_cost
end

function Ability:ChargesFractional()
	local info = GetSpellCharges(self.spellId)
	if not info then
		return 0
	end
	local charges = info.currentCharges
	if self:Casting() then
		if charges >= info.maxCharges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= info.maxCharges then
		return charges
	end
	return charges + ((max(0, Player.ctime - info.cooldownStartTime + (self.off_gcd and 0 or Player.execute_remains))) / info.cooldownDuration)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:MaxCharges()
	local info = GetSpellCharges(self.spellId)
	return info and info.maxCharges or 0
end

function Ability:FullRechargeTime()
	local info = GetSpellCharges(self.spellId)
	if not info then
		return 0
	end
	local charges = info.currentCharges
	if self:Casting() then
		if charges >= info.maxCharges then
			return info.cooldownDuration
		end
		charges = charges - 1
	end
	if charges >= info.maxCharges then
		return 0
	end
	return (info.maxCharges - charges - 1) * info.cooldownDuration + (info.cooldownDuration - (Player.ctime - info.cooldownStartTime) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.cast.ability == self
end

function Ability:Channeling()
	return Player.channel.ability == self
end

function Ability:CastTime()
	local info = GetSpellInfo(self.spellId)
	return info and info.castTime / 1000 or 0
end

function Ability:CastRegen()
	return Player.mana.regen * self:CastTime() - self:ManaCost()
end

function Ability:Previous(n)
	local i = n or 1
	if Player.cast.ability then
		if i == 1 then
			return Player.cast.ability == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:UsedWithin(seconds)
	return self.last_used >= (Player.time - seconds)
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {},
		target_count = 0,
		trigger = 'SPELL_DAMAGE',
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	elseif trigger == 'cast' then
		self.auto_aoe.trigger = 'SPELL_CAST_SUCCESS'
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
		self.auto_aoe.target_count = 0
		if self.auto_aoe.remove then
			for guid in next, AutoAoe.targets do
				AutoAoe.targets[guid] = nil
			end
		end
		for guid in next, self.auto_aoe.targets do
			AutoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		AutoAoe:Update()
	end
end

function Ability:Targets()
	if self.auto_aoe and self:Up() then
		return self.auto_aoe.target_count
	end
	return 0
end

function Ability:CastSuccess(dstGUID)
	self.last_used = Player.time
	if self.ignore_cast then
		return
	end
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.aura_targets and self.requires_react then
		self:RemoveAura(self.aura_target == 'player' and Player.guid or dstGUID)
	end
	if Opt.auto_aoe and self.auto_aoe and self.auto_aoe.trigger == 'SPELL_CAST_SUCCESS' then
		AutoAoe:Add(dstGUID, true)
	end
	if self.traveling and self.next_castGUID then
		self.traveling[self.next_castGUID] = {
			guid = self.next_castGUID,
			start = self.last_used,
			dstGUID = dstGUID,
		}
		self.next_castGUID = nil
	end
	if Opt.previous then
		farseerPreviousPanel.ability = self
		farseerPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
		farseerPreviousPanel.icon:SetTexture(self.icon)
		farseerPreviousPanel:SetShown(farseerPanel:IsVisible())
	end
end

function Ability:CastLanded(dstGUID, event, missType)
	if self.traveling then
		local oldest
		for guid, cast in next, self.traveling do
			if Player.time - cast.start >= self.max_range / self.velocity + (self.travel_delay or 0) + 0.2 then
				self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
			elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
				oldest = cast
			end
		end
		if oldest then
			Target.estimated_range = floor(clamp(self.velocity * max(0, Player.time - oldest.start - (self.travel_delay or 0)), 0, self.max_range))
			self.traveling[oldest.guid] = nil
		end
	end
	if self.range_est_start then
		Target.estimated_range = floor(clamp(self.velocity * (Player.time - self.range_est_start - (self.travel_delay or 0)), 5, self.max_range))
		self.range_est_start = nil
	elseif self.max_range < Target.estimated_range then
		Target.estimated_range = self.max_range
	end
	if Opt.auto_aoe and self.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or (missType == 'IMMUNE' and not self.ignore_immune)) then
			AutoAoe:Remove(dstGUID)
		elseif event == self.auto_aoe.trigger or (self.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			self:RecordTargetHit(dstGUID)
		end
	end
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and farseerPreviousPanel.ability == self then
		farseerPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	for _, ability in next, Abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	for _, ability in next, Abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid] or {}
	aura.expires = Player.time + self:Duration()
	self.aura_targets[guid] = aura
	return aura
end

function Ability:RefreshAura(guid, extend)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		return self:ApplyAura(guid)
	end
	local duration = self:Duration()
	aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + (extend or duration)))
	return aura
end

function Ability:RefreshAuraAll(extend)
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + (extend or duration)))
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT tracking

--[[
Note: To get talent_node value for a talent, hover over talent and use macro:
/dump GetMouseFoci()[1]:GetNodeID()
]]

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
EarthElemental.summon_count = 1
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
ElementalBlast.mana_cost = 2.75
ElementalBlast.maelstrom_cost = 80
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
FireElemental.summon_count = 1
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
StormElemental.summon_count = 1
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
-- Tier set bonuses

-- Racials

-- PvP talents

-- Trinket effects

-- Class cooldowns

-- End Abilities

-- Start Summoned Pets

function SummonedPets:Purge()
	for _, pet in next, self.known do
		for guid, unit in next, pet.active_units do
			if unit.expires <= Player.time then
				pet.active_units[guid] = nil
			end
		end
	end
end

function SummonedPets:Update()
	wipe(self.known)
	wipe(self.byUnitId)
	for _, pet in next, self.all do
		pet.known = pet.summon_spell and pet.summon_spell.known
		if pet.known then
			self.known[#SummonedPets.known + 1] = pet
			self.byUnitId[pet.unitId] = pet
		end
	end
end

function SummonedPets:Count()
	local count = 0
	for _, pet in next, self.known do
		count = count + pet:Count()
	end
	return count
end

function SummonedPets:Clear()
	for _, pet in next, self.known do
		pet:Clear()
	end
end

function SummonedPet:Add(unitId, duration, summonSpell)
	local pet = {
		unitId = unitId,
		duration = duration,
		active_units = {},
		summon_spell = summonSpell,
		known = false,
	}
	setmetatable(pet, self)
	SummonedPets.all[#SummonedPets.all + 1] = pet
	return pet
end

function SummonedPet:Remains(initial)
	if self.summon_spell and self.summon_spell.summon_count > 0 and self.summon_spell:Casting() then
		return self.duration
	end
	local expires_max = 0
	for guid, unit in next, self.active_units do
		if (not initial or unit.initial) and unit.expires > expires_max then
			expires_max = unit.expires
		end
	end
	return max(0, expires_max - Player.time - Player.execute_remains)
end

function SummonedPet:Up(...)
	return self:Remains(...) > 0
end

function SummonedPet:Down(...)
	return self:Remains(...) <= 0
end

function SummonedPet:Count()
	local count = 0
	if self.summon_spell and self.summon_spell:Casting() then
		count = count + self.summon_spell.summon_count
	end
	for guid, unit in next, self.active_units do
		if unit.expires - Player.time > Player.execute_remains then
			count = count + 1
		end
	end
	return count
end

function SummonedPet:Expiring(seconds)
	local count = 0
	for guid, unit in next, self.active_units do
		if unit.expires - Player.time <= (seconds or Player.execute_remains) then
			count = count + 1
		end
	end
	return count
end

function SummonedPet:AddUnit(guid)
	local unit = {
		guid = guid,
		spawn = Player.time,
		expires = Player.time + self.duration,
	}
	self.active_units[guid] = unit
	return unit
end

function SummonedPet:RemoveUnit(guid)
	if self.active_units[guid] then
		self.active_units[guid] = nil
	end
end

function SummonedPet:ExtendAll(seconds)
	for guid, unit in next, self.active_units do
		if unit.expires > Player.time then
			unit.expires = unit.expires + seconds
		end
	end
end

function SummonedPet:Clear()
	for guid in next, self.active_units do
		self.active_units[guid] = nil
	end
end

-- Summoned Pets
Pet.GreaterEarthElemental = SummonedPet:Add(95072, 60, EarthElemental)
Pet.GreaterFireElemental = SummonedPet:Add(95061, 30, FireElemental)
Pet.GreaterStormElemental = SummonedPet:Add(77936, 30, StormElemental)
Pet.PrimalEarthElemental = SummonedPet:Add(61056, 60, EarthElemental)
Pet.PrimalFireElemental = SummonedPet:Add(61029, 30, FireElemental)
Pet.PrimalStormElemental = SummonedPet:Add(77942, 30, StormElemental)
-- End Summoned Pets

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
		off_gcd = true,
	}
	setmetatable(item, self)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:Charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(self.max_charges, charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(1, count)
	end
	return count
end

function InventoryItem:Cooldown()
	local start, duration
	if self.equip_slot then
		start, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		start, duration = GetItemCooldown(self.itemId)
	end
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - (self.off_gcd and 0 or Player.execute_remains))
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
local Healthstone = InventoryItem:Add(5512)
Healthstone.max_charges = 3
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Abilities Functions

function Abilities:Update()
	wipe(self.bySpellId)
	wipe(self.velocity)
	wipe(self.autoAoe)
	wipe(self.trackAuras)
	for _, ability in next, self.all do
		if ability.known then
			self.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				self.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				self.velocity[#self.velocity + 1] = ability
			end
			if ability.auto_aoe then
				self.autoAoe[#self.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				self.trackAuras[#self.trackAuras + 1] = ability
			end
		end
	end
end

-- End Abilities Functions

-- Start Player Functions

function Player:ResetSwing(mainHand, offHand, missed)
	local mh, oh = UnitAttackSpeed('player')
	if mainHand then
		self.swing.mh.speed = (mh or 0)
		self.swing.mh.last = self.time
	end
	if offHand then
		self.swing.oh.speed = (oh or 0)
		self.swing.oh.last = self.time
	end
end

function Player:ManaTimeToMax()
	local deficit = self.mana.max - self.mana.current
	if deficit <= 0 then
		return 0
	end
	return deficit / self.mana.regen
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	if self.cast.ability and self.cast.ability.triggers_combat then
		return 0.1
	end
	return 0
end

function Player:UnderMeleeAttack()
	return (self.time - self.swing.last_taken) < 3
end

function Player:UnderAttack()
	return self.threat.status >= 3 or self:UnderMeleeAttack()
end

function Player:BloodlustActive()
	local aura
	for i = 1, 40 do
		aura = UnitAura('player', i, 'HELPFUL')
		if not aura then
			return false
		elseif (
			aura.spellId == 2825 or   -- Bloodlust (Horde Shaman)
			aura.spellId == 32182 or  -- Heroism (Alliance Shaman)
			aura.spellId == 80353 or  -- Time Warp (Mage)
			aura.spellId == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			aura.spellId == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			aura.spellId == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			aura.spellId == 381301 or -- Feral Hide Drums (Leatherworking)
			aura.spellId == 390386    -- Fury of the Aspects (Evoker)
		) then
			return true
		end
	end
end

function Player:Exhausted()
	local aura
	for i = 1, 40 do
		aura = UnitAura('player', i, 'HARMFUL')
		if not aura then
			return false
		elseif (
			aura.spellId == 57724 or -- Sated (Alliance Shaman)
			aura.spellId == 57723 or -- Exhaustion (Horde Shaman)
			aura.spellId == 80354 or -- Temporal Displacement (Mage)
			aura.spellId == 264689 or-- Fatigued (Hunter)
			aura.spellId == 390435   -- Exhaustion (Evoker)
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
	for i = (slot or 1), (slot or 19) do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:BonusIdEquipped(bonusId, slot)
	local link, item
	for i = (slot or 1), (slot or 19) do
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

function Player:UpdateTime(timeStamp)
	self.ctime = GetTime()
	if timeStamp then
		self.time_diff = self.ctime - timeStamp
	end
	self.time = self.ctime - self.time_diff
end

function Player:UpdateKnown()
	local info, node
	local configId = C_ClassTalents.GetActiveConfigID()
	for _, ability in next, Abilities.all do
		ability.known = false
		ability.rank = 0
		for _, spellId in next, ability.spellIds do
			info = GetSpellInfo(spellId)
			if info then
				ability.spellId, ability.name, ability.icon = info.spellID, info.name, info.originalIconID
			end
			if IsPlayerSpell(spellId) or (ability.learn_spellId and IsPlayerSpell(ability.learn_spellId)) then
				ability.known = true
				break
			end
		end
		if ability.bonus_id then -- used for checking enchants and crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if ability.talent_node and configId then
			node = C_Traits.GetNodeInfo(configId, ability.talent_node)
			if node then
				ability.rank = node.activeRank
				ability.known = ability.rank > 0
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.check_usable and not IsSpellUsable(ability.spellId)) then
			ability.known = false -- spell is locked, do not mark as known
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

	Abilities:Update()
	SummonedPets:Update()

	if APL[self.spec].precombat_variables then
		APL[self.spec]:precombat_variables()
	end
end

function Player:UpdateChannelInfo()
	local channel = self.channel
	local _, _, _, start, ends, _, _, spellId = UnitChannelInfo('player')
	if not spellId then
		channel.ability = nil
		channel.chained = false
		channel.start = 0
		channel.ends = 0
		channel.tick_count = 0
		channel.tick_interval = 0
		channel.ticks = 0
		channel.ticks_remain = 0
		channel.ticks_extra = 0
		channel.interrupt_if = nil
		channel.interruptible = false
		channel.early_chain_if = nil
		channel.early_chainable = false
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if ability then
		if ability == channel.ability then
			channel.chained = true
		end
		channel.interrupt_if = ability.interrupt_if
	else
		channel.interrupt_if = nil
	end
	channel.ability = ability
	channel.ticks = 0
	channel.start = start / 1000
	channel.ends = ends / 1000
	if ability and ability.tick_interval then
		channel.tick_interval = ability:TickTime()
	else
		channel.tick_interval = channel.ends - channel.start
	end
	channel.tick_count = (channel.ends - channel.start) / channel.tick_interval
	if channel.chained then
		channel.ticks_extra = channel.tick_count - floor(channel.tick_count)
	else
		channel.ticks_extra = 0
	end
	channel.ticks_remain = channel.tick_count
end

function Player:UpdateThreat()
	local _, status, pct
	_, status, pct = UnitDetailedThreatSituation('player', 'target')
	self.threat.status = status or 0
	self.threat.pct = pct or 0
	self.threat.lead = 0
	if self.threat.status >= 3 and DETAILS_PLUGIN_TINY_THREAT then
		local threat_table = DETAILS_PLUGIN_TINY_THREAT.player_list_indexes
		if threat_table and threat_table[1] and threat_table[2] and threat_table[1][1] == self.name then
			self.threat.lead = max(0, threat_table[1][6] - threat_table[2][6])
		end
	end
end

function Player:Update()
	local _, cooldown, start, ends, spellId, speed, max_speed, speed_mh, speed_oh
	self.main = nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self.wait_time = nil
	self:UpdateTime()
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	self.gcd = 1.5 * self.haste_factor
	cooldown = GetSpellCooldown(61304)
	self.gcd_remains = cooldown.startTime > 0 and cooldown.duration - (self.ctime - cooldown.startTime) or 0
	_, _, _, start, ends, _, _, _, spellId = UnitCastingInfo('player')
	if spellId then
		self.cast.ability = Abilities.bySpellId[spellId]
		self.cast.start = start / 1000
		self.cast.ends = ends / 1000
		self.cast.remains = self.cast.ends - self.ctime
	else
		self.cast.ability = nil
		self.cast.start = 0
		self.cast.ends = 0
		self.cast.remains = 0
	end
	self.execute_remains = max(self.cast.remains, self.gcd_remains)
	if self.channel.tick_count > 1 then
		self.channel.ticks = ((self.ctime - self.channel.start) / self.channel.tick_interval) - self.channel.ticks_extra
		self.channel.ticks_remain = (self.channel.ends - self.ctime) / self.channel.tick_interval
	end
	self.mana.regen = GetPowerRegenForPowerType(0)
	self.mana.current = UnitPower('player', 0) + (self.mana.regen * self.execute_remains)
	if self.cast.ability and self.cast.ability.mana_cost > 0 then
		self.mana.current = self.mana.current - self.cast.ability:ManaCost()
	end
	self.mana.current = clamp(self.mana.current, 0, self.mana.max)
	self.mana.pct = self.mana.current / self.mana.max * 100
	if self.spec == SPEC.ELEMENTAL then
		self.maelstrom.current = UnitPower('player', 11)
		if self.cast.ability and self.cast.ability.maelstrom_cost > 0 then
			self.maelstrom.current = self.maelstrom.current - self.cast.ability:MaelstromCost()
		end
		self.maelstrom.current = clamp(self.maelstrom.current, 0, self.maelstrom.max)
		self.maelstrom.deficit = self.maelstrom.max - self.maelstrom.current
	elseif self.spec == SPEC.ENHANCEMENT then
		self.maelstrom_weapon.current = MaelstromWeapon:Stack()
	end
	speed_mh, speed_oh = UnitAttackSpeed('player')
	self.swing.mh.speed = speed_mh or 0
	self.swing.oh.speed = speed_oh or 0
	self.swing.mh.remains = max(0, self.swing.mh.last + self.swing.mh.speed - self.time)
	self.swing.oh.remains = max(0, self.swing.oh.last + self.swing.oh.speed - self.time)
	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100
	self:UpdateThreat()

	SummonedPets:Purge()
	trackAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, Abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		AutoAoe:Purge()
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

	self.main = APL[self.spec]:Main()

	if self.channel.interrupt_if then
		self.channel.interruptible = self.channel.ability ~= self.main and self.channel.interrupt_if()
	end
	if self.channel.early_chain_if then
		self.channel.early_chainable = self.channel.ability == self.main and self.channel.early_chain_if()
	end
end

function Player:Init()
	local _
	if #UI.glows == 0 then
		UI:DisableOverlayGlows()
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	farseerPreviousPanel.ability = nil
	self.guid = UnitGUID('player')
	self.name = UnitName('player')
	_, self.instance = IsInInstance()
	Events:GROUP_ROSTER_UPDATE()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

-- End Player Functions

-- Start Target Functions

function Target:UpdateHealth(reset)
	Timer.health = 0
	self.health.current = UnitHealth('target')
	self.health.max = UnitHealthMax('target')
	if self.health.current <= 0 then
		self.health.current = Player.health.max
		self.health.max = self.health.current
	end
	if reset then
		for i = 1, 25 do
			self.health.history[i] = self.health.current
		end
	else
		table.remove(self.health.history, 1)
		self.health.history[25] = self.health.current
	end
	self.timeToDieMax = self.health.current / Player.health.max * (Player.spec == SPEC.RESTORATION and 20 or 10)
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = (
		(self.dummy and 600) or
		(self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec)) or
		self.timeToDieMax
	)
end

function Target:Update()
	if UI:ShouldHide() then
		return UI:Disappear()
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.uid = nil
		self.boss = false
		self.dummy = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = Player.level
		self.hostile = false
		self:UpdateHealth(true)
		if Opt.always_on then
			UI:UpdateCombat()
			farseerPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			farseerPreviousPanel:Hide()
		end
		return UI:Disappear()
	end
	if guid ~= self.guid then
		self.guid = guid
		self.uid = ToUID(guid) or 0
		self:UpdateHealth(true)
	end
	self.boss = false
	self.dummy = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self.level = UnitLevel('target')
	if self.level == -1 then
		self.level = Player.level + 3
	end
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		self.boss = self.level >= (Player.level + 3)
		self.stunnable = self.level < (Player.level + 2)
	end
	if self.Dummies[self.uid] then
		self.boss = true
		self.dummy = true
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		farseerPanel:Show()
		return true
	end
	UI:Disappear()
end

function Target:TimeToPct(pct)
	if self.health.pct <= pct then
		return 0
	end
	if self.health.loss_per_sec <= 0 then
		return self.timeToDieMax
	end
	return min(self.timeToDieMax, (self.health.current - (self.health.max * (pct / 100))) / self.health.loss_per_sec)
end

-- End Target Functions

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

function EarthElemental:Remains()
	return PrimalElementalist.known and Pet.PrimalEarthElemental:Remains() or Pet.GreaterEarthElemental:Remains()
end

function FireElemental:Remains()
	return PrimalElementalist.known and Pet.PrimalFireElemental:Remains() or Pet.GreaterFireElemental:Remains()
end

function StormElemental:Remains()
	return PrimalElementalist.known and Pet.PrimalStormElemental:Remains() or Pet.GreaterStormElemental:Remains()
end

function WindfuryTotem:Remains()
	local remains = Ability.Remains(self)
	if remains == 0 then
		return 0
	end
	return TotemRemains(self)
end

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
	return Ability.MaelstromCost(self) * min(5, Player.enemies)
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

function FlameShock:Ticking()
	local count, ticking, _ = 0, {}
	if self.aura_targets then
		local guid, aura
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				ticking[guid] = true
			end
		end
	end
	if PrimordialWave.known then
		local cast
		for _, cast in next, PrimordialWave.traveling do
			if Player.time - cast.start < PrimordialWave.max_range / PrimordialWave.velocity then
				ticking[cast.dstGUID] = true
			end
		end
	end
	for _ in next, ticking do
		count = count + 1
	end
	return count
end

function MaelstromWeapon:Stack()
	local stack = Ability.Stack(self)
	if Player.cast.ability and Player.cast.ability.consume_mw then
		stack = stack - 5
	end
	return max(0, stack)
end

function Hailstorm:Stack()
	local stack = Ability.Stack(self)
	if Player.cast.ability and Player.cast.ability.consume_mw then
		stack = min(5, stack + Player.maelstrom_weapon.current)
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

local function WaitFor(ability, wait_time)
	Player.wait_time = wait_time and (Player.ctime + wait_time) or (Player.ctime + ability:Cooldown())
	return ability
end

-- Begin Action Priority Lists

APL[SPEC.NONE].Main = function(self)
end

APL[SPEC.ELEMENTAL].Main = function(self)
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
		if Opt.trinket and ((FireElemental.known and FireElemental:Up()) or (StormElemental.known and StormElemental:Up()) or (Stormkeeper.known and Stormkeeper:Up())) then
			if Trinket1:Usable() then
				UseCooldown(Trinket1)
			elseif Trinket2:Usable() then
				UseCooldown(Trinket2)
			end
		end
	end
	if PrimordialWave:Usable() and PrimordialWave.buff:Down() then
		UseCooldown(PrimordialWave)
	end
	if Player.enemies > 2 then
		return self:aoe()
	end
	if StormElemental.known then
		return self:se_single_target()
	end
	return self:single_target()
end

APL[SPEC.ELEMENTAL].aoe = function(self)
--[[
actions.aoe=earthquake,if=buff.echoing_shock.up|buff.echoes_of_great_sundering.up&(maelstrom>=(maelstrom.max-4*spell_targets.chain_lightning)|buff.echoes_of_great_sundering.remains<2*spell_haste|buff.master_of_the_elements.up)
actions.aoe+=/chain_harvest
actions.aoe+=/flame_shock,if=!active_dot.flame_shock|runeforge.skybreakers_fiery_demise.equipped,target_if=refreshable
actions.aoe+=/echoing_shock,if=talent.echoing_shock.enabled&maelstrom>=60
actions.aoe+=/ascendance,if=talent.ascendance.enabled&(!pet.storm_elemental.active)&(!talent.icefury.enabled|!buff.icefury.up&!cooldown.icefury.up)
actions.aoe+=/liquid_magma_totem,if=talent.liquid_magma_totem.enabled
actions.aoe+=/earth_shock,if=runeforge.echoes_of_great_sundering.equipped&!buff.echoes_of_great_sundering.up
actions.aoe+=/earth_elemental,if=runeforge.deeptremor_stone.equipped&(!talent.primal_elementalist.enabled|(!pet.storm_elemental.active&!pet.fire_elemental.active))
actions.aoe+=/lava_burst,target_if=max:dot.flame_shock.remains,if=dot.flame_shock.remains>cast_time+travel_time&buff.master_of_the_elements.down&(buff.lava_surge.up|talent.master_of_the_elements.enabled&maelstrom>=60|buff.stormkeeper.up&maelstrom<50)
actions.aoe+=/flame_shock,if=active_dot.flame_shock<3&active_enemies<=5,target_if=refreshable
# Try to game Earthquake with Master of the Elements buff when fighting 3 targets. Don't overcap Maelstrom!
actions.aoe+=/earthquake,if=!talent.master_of_the_elements.enabled|buff.stormkeeper.up|buff.master_of_the_elements.up|spell_targets.chain_lightning>3|maelstrom>=(maelstrom.max-4*spell_targets.chain_lightning)
# Make sure you don't lose a Stormkeeper buff.
actions.aoe+=/chain_lightning,if=buff.stormkeeper.up&(maelstrom<60&buff.master_of_the_elements.up|buff.stormkeeper.remains<3*gcd*buff.stormkeeper.stack)
# Use Elemental Blast against up to 3 targets as long as Storm Elemental is not active.
actions.aoe+=/stormkeeper
actions.aoe+=/elemental_blast,if=spell_targets.chain_lightning<5&!pet.storm_elemental.active
actions.aoe+=/lava_beam,if=talent.ascendance.enabled
actions.aoe+=/chain_lightning
actions.aoe+=/lava_burst,moving=1,if=buff.lava_surge.up&cooldown_react
actions.aoe+=/flame_shock,moving=1,target_if=refreshable
actions.aoe+=/frost_shock,moving=1
]]
	if Earthquake:Usable() and ((EchoingShock.known and EchoingShock:Up()) or (EchoesOfGreatSundering.known and EchoesOfGreatSundering:Up() and (Player.maelstrom.deficit < (4 * Player.enemies) or EchoesOfGreatSundering:Remains() < (2 * Player.haste_factor) or (MasterOfTheElements.known and MasterOfTheElements:Up())))) then
		return Earthquake
	end
	if Player.use_cds and ChainHarvest:Usable() then
		UseCooldown(ChainHarvest)
	end
	if FlameShock:Usable() and FlameShock:Refreshable() and Target.timeToDie > FlameShock:Remains() and (FlameShock:Ticking() == 0 or SkybreakersFieryDemise.known) then
		return FlameShock
	end
	if EchoingShock:Usable() and Player.maelstrom.current >= 60 then
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
	if LavaBurst:Usable() and FlameShock:Remains() > (LavaBurst:CastTime() + LavaBurst:TravelTime()) and (not MasterOfTheElements.known or MasterOfTheElements:Down()) and (LavaSurge:Up() or (MasterOfTheElements.known and Player.maelstrom.current >= 60) or (Stormkeeper.known and Stormkeeper:Up() and Player.maelstrom.current < 50)) then
		return LavaBurst
	end
	if FlameShock:Usable() and FlameShock:Refreshable() and Target.timeToDie > FlameShock:Remains() and Player.enemies <= 5 and FlameShock:Ticking() < 3 then
		return FlameShock
	end
	if Earthquake:Usable() and (not MasterOfTheElements.known or (Stormkeeper.known and Stormkeeper:Up()) or MasterOfTheElements:Up() or Player.enemies > 3 or Player.maelstrom.deficit < (4 * Player.enemies)) then
		return Earthquake
	end
	if Stormkeeper.known and ChainLightning:Usable() and Stormkeeper:Up() and ((Player.maelstrom.current < 60 and MasterOfTheElements:Up()) or Stormkeeper:Remains() < (3 * Player.gcd * Stormkeeper:Stack())) then
		return ChainLightning
	end
	if Player.use_cds and Stormkeeper:Usable() and Stormkeeper:Down() then
		UseCooldown(Stormkeeper)
	end
	if ElementalBlast:Usable() and Player.enemies < 5 and (not StormElemental.known or StormElemental:Down()) then
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
	if Player.use_cds and Stormkeeper:Usable() and Player.maelstrom.current < 44 and Stormkeeper:Down() then
		UseCooldown(Stormkeeper)
	end
	if EchoingShock:Usable() then
		return EchoingShock
	end
	if LavaBurst:Usable() and Player.maelstrom.deficit > 10 and (((not EchoOfTheElements.known or LavaBurst:ChargesFractional() > 1.5) and WindGust:Stack() < 18) or (LavaSurge:Up() and FlameShock:Remains() > LavaBurst:TravelTime())) then
		return LavaBurst
	end
	if Earthquake:Usable() then
		if EchoesOfGreatSundering.known and EchoesOfGreatSundering:Up() then
			return Earthquake
		end
		if not EchoesOfGreatSundering.known and Player.enemies > 1 and not FlameShock:Refreshable() then
			return Earthquake
		end
	end
	if EarthShock:Usable() then
		if EchoesOfGreatSundering.known and EchoesOfGreatSundering:Down() then
			return EarthShock
		end
		if Player.enemies < 2 and Player.maelstrom.current >= 60 and ((WindGust.known and WindGust:Stack() < 20) or Player.maelstrom.current > 90) then
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
	if Icefury:Usable() and not (Player.maelstrom.current > 75 and LavaBurst:Ready()) then
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
	if ChainLightning:Usable() and Player.enemies > 1 and (not Stormkeeper.known or Stormkeeper:Down()) then
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
	if EchoesOfGreatSundering.known and EchoesOfGreatSundering:Up() then
		if Earthquake:Usable() and ((MasterOfTheElements.known and MasterOfTheElements:Up()) or Player.maelstrom.deficit < 8) then
			return Earthquake
		end
		if MasterOfTheElements.known and LavaBurst:Usable() and Player.maelstrom.current >= 50 and MasterOfTheElements:Down() then
			return LavaBurst
		end
	end
	if EarthShock:Usable() and Player.maelstrom.deficit < 8 and (not EchoesOfGreatSundering.known or EchoesOfGreatSundering:Down()) then
		return EarthShock
	end
	if Player.use_cds and Stormkeeper:Usable() and Player.maelstrom.current < 44 and Stormkeeper:Down() then
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
			if EchoesOfGreatSundering:Up() and (not MasterOfTheElements.known or (ElementalBlast.known and ElementalBlast:Ready(1.1 * Player.gcd * 2)) or (Stormkeeper.known and Player.enemies < 2 and Stormkeeper:Up() and LavaBurst:Ready(Player.gcd))) then
				return Earthquake
			end
		elseif Player.enemies > 1 and not FlameShock:Refreshable() and (not MasterOfTheElements.known or MasterOfTheElements:Up() or (not LavaBurst:Ready() and Player.maelstrom.current >= 92)) then
			return Earthquake
		end
	end
	if EarthShock:Usable() and (not EchoesOfGreatSundering.known or EchoesOfGreatSundering:Down()) and (not MasterOfTheElements.known or MasterOfTheElements:Up() or (not LavaBurst:Ready() and Player.maelstrom.current >= 92) or (Stormkeeper.known and Player.enemies < 2 and Stormkeeper:Up() and LavaBurst:Ready(Player.gcd))) then
		return EarthShock
	end
	if Icefury.known and MasterOfTheElements.known and FrostShock:Usable() and Icefury:Up() and MasterOfTheElements:Up() then
		return FrostShock
	end
	if ElementalBlast:Usable() and (Player.maelstrom.current < 60 or not MasterOfTheElements.known or MasterOfTheElements:Down()) then
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
	if Icefury:Usable() and Player.maelstrom.deficit > 25 then
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
	if FlameShock:Usable() and FlameShock:Refreshable() and Target.timeToDie > (FlameShock:Remains() + 2) then
		return FlameShock
	end
	if Earthquake:Usable() and Player.enemies > 1 and (not EchoesOfGreatSundering.known or EchoesOfGreatSundering:Up()) then
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
	if ChainLightning:Usable() and Player.enemies > 1 and (not Stormkeeper.known or Stormkeeper:Down()) then
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

APL[SPEC.ENHANCEMENT].Main = function(self)
	Player.use_cds = Opt.cooldown and (Target.boss or Target.player or (not Opt.boss_only and Target.timeToDie > Opt.cd_ttd) or AscendanceAir:Up() or FeralSpirit:Up())
	if Player.health.pct < Opt.heal and Player.maelstrom_weapon.current >= 5 and HealingSurge:Usable() then
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
		if Player.maelstrom_weapon.current >= 5 then
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
	if Hailstorm.known and FrostShock:Usable() and Hailstorm:Stack() >= 5 and (between(Hailstorm:Remains(), 0.1, Player.gcd * 2) or Player.maelstrom_weapon.current >= 9) then
		return FrostShock
	end
	if (Player.maelstrom_weapon.current >= 9 or (Player.maelstrom_weapon.current >= 5 and MaelstromWeapon:Remains() < Player.gcd * 2)) then
		local apl = self:spenders()
		if apl then return apl end
	end
	if Hailstorm.known and FrostShock:Usable() and Player.enemies > 1 and Hailstorm:Stack() >= 5 then
		return FrostShock
	end
	if CrashLightning:Usable() and Player.enemies > 1 and CrashLightning.buff:Down() then
		return CrashLightning
	end
	if DoomWinds.known then
		if DoomWinds:Ready() and WindfuryTotem:Usable() and (Player.enemies == 1 or (CrashLightning:Remains() > 6 and (not Sundering.known or Sundering:Ready(12)))) then
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
	if PrimordialWave.known and LightningBolt:Usable() and PrimordialWave.buff:Up() and Player.maelstrom_weapon.current >= 5 then
		return LightningBolt
	end
	if LashingFlames.known and FlameShock:Usable() and FlameShock:Down() and Player.enemies == 1 and Target.timeToDie > (4 * Player.haste_factor) then
		return FlameShock
	end
	if Stormstrike:Usable() then
		return Stormstrike
	end
	if LavaLash:Usable() then
		return LavaLash
	end
	if FlameShock:Usable() and FlameShock:Down() and (not Hailstorm.known or (Player.enemies == 1 and Hailstorm:Stack() <= 3)) and Target.timeToDie > (8 * Player.haste_factor) then
		return FlameShock
	end
	if Player.use_cds and AscendanceAir:Usable() then
		UseCooldown(AscendanceAir)
	elseif Sundering:Usable() and (not DoomWinds.known or Player.enemies == 1 or not DoomWinds:Ready(12)) then
		UseCooldown(Sundering)
	elseif Player.use_cds and FeralSpirit:Usable() then
		UseCooldown(FeralSpirit)
	end
	if FlameShock:Usable() and FlameShock:Refreshable() and (not Hailstorm.known or (Player.enemies == 1 and (LashingFlames.known or Hailstorm:Stack() <= 3))) and Target.timeToDie > (FlameShock:Remains() + 8 * Player.haste_factor) then
		return FlameShock
	end
	if FrostShock:Usable() and (not Hailstorm.known or Hailstorm:Up()) then
		return FrostShock
	end
	if Player.maelstrom_weapon.current >= 5 and (not Hailstorm.known or Hailstorm:Stack() < 5) then
		local apl = self:spenders()
		if apl then return apl end
	end
	if CrashLightning:Usable() and Player.enemies > 1 then
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
	if ElementalBlast:Usable() and Player.enemies < 4 then
		return ElementalBlast
	end
	if ChainLightning:Usable() and Player.enemies > 1 then
		return ChainLightning
	end
	if LightningBolt:Usable() then
		return LightningBolt
	end
end

APL[SPEC.RESTORATION].Main = function(self)
	if Player:TimeInCombat() == 0 then

	end
end

APL.Interrupt = function(self)
	if WindShear:Usable() then
		return WindShear
	end
end

-- End Action Priority Lists

-- Start UI Functions

function UI.DenyOverlayGlow(actionButton)
	if Opt.glow.blizzard then
		return
	end
	local alert = actionButton.SpellActivationAlert
	if not alert then
		return
	end
	if alert.ProcStartAnim:IsPlaying() then
		alert.ProcStartAnim:Stop()
	end
	alert:Hide()
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow
	local r, g, b = Opt.glow.color.r, Opt.glow.color.g, Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.ProcStartFlipbook:SetVertexColor(r, g, b)
		glow.ProcLoopFlipbook:SetVertexColor(r, g, b)
	end
end

function UI:DisableOverlayGlows()
	if LibStub and LibStub.GetLibrary and not Opt.glow.blizzard then
		local lib = LibStub:GetLibrary('LibButtonGlow-1.0', true)
		if lib then
			lib.ShowOverlayGlow = function(self)
				return
			end
		end
	end
end

function UI:CreateOverlayGlows()
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.ProcStartAnim:Play() -- will bug out if ProcLoop plays first
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
	self:UpdateGlowColorAndScale()
end

function UI:UpdateGlows()
	local glow, icon
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
				glow:Show()
				if Opt.glow.animation then
					glow.ProcStartAnim:Play()
				else
					glow.ProcLoop:Play()
				end
			end
		elseif glow:IsVisible() then
			if glow.ProcStartAnim:IsPlaying() then
				glow.ProcStartAnim:Stop()
			end
			if glow.ProcLoop:IsPlaying() then
				glow.ProcLoop:Stop()
			end
			glow:Hide()
		end
	end
end

function UI:UpdateDraggable()
	local draggable = not (Opt.locked or Opt.snap or Opt.aoe)
	farseerPanel:SetMovable(not Opt.snap)
	farseerPreviousPanel:SetMovable(not Opt.snap)
	farseerCooldownPanel:SetMovable(not Opt.snap)
	farseerInterruptPanel:SetMovable(not Opt.snap)
	farseerExtraPanel:SetMovable(not Opt.snap)
	if not Opt.snap then
		farseerPanel:SetUserPlaced(true)
		farseerPreviousPanel:SetUserPlaced(true)
		farseerCooldownPanel:SetUserPlaced(true)
		farseerInterruptPanel:SetUserPlaced(true)
		farseerExtraPanel:SetUserPlaced(true)
	end
	farseerPanel:EnableMouse(draggable or Opt.aoe)
	farseerPanel.button:SetShown(Opt.aoe)
	farseerPreviousPanel:EnableMouse(draggable)
	farseerCooldownPanel:EnableMouse(draggable)
	farseerInterruptPanel:EnableMouse(draggable)
	farseerExtraPanel:EnableMouse(draggable)
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
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
		[SPEC.ENHANCEMENT] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
		[SPEC.RESTORATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
	},
	kui = { -- Kui Nameplates
		[SPEC.ELEMENTAL] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 4 },
		},
		[SPEC.ENHANCEMENT] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 4 },
		},
		[SPEC.RESTORATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 4 },
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
		self.anchor.frame = NamePlateDriverFrame:GetClassNameplateBar()
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

function UI:Reset()
	farseerPanel:ClearAllPoints()
	farseerPanel:SetPoint('CENTER', 0, -169)
	self:SnapAllPanels()
end

function UI:UpdateDisplay()
	Timer.display = 0
	local border, dim, dim_cd, text_cd, text_center, text_tl
	local channel = Player.channel

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsSpellUsable(Player.main.spellId)) or
		           (Player.main.itemId and IsItemUsable(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsSpellUsable(Player.cd.spellId)) or
		           (Player.cd.itemId and IsItemUsable(Player.cd.itemId)))
	end
	if Player.main then
		if Player.main.requires_react then
			local react = Player.main:React()
			if react > 0 then
				text_center = format('%.1f', react)
			end
		end
		if Player.main_freecast then
			border = 'freecast'
		end
	end
	if Player.cd then
		if Player.cd.requires_react then
			local react = Player.cd:React()
			if react > 0 then
				text_cd = format('%.1f', react)
			end
		end
	end
	if Player.wait_time then
		local deficit = Player.wait_time - GetTime()
		if deficit > 0 then
			text_center = format('WAIT\n%.1fs', deficit)
			dim = Opt.dimmer
		end
	end
	if channel.ability and not channel.ability.ignore_channel and channel.tick_count > 0 then
		dim = Opt.dimmer
		if channel.tick_count > 1 then
			local ctime = GetTime()
			channel.ticks = ((ctime - channel.start) / channel.tick_interval) - channel.ticks_extra
			channel.ticks_remain = (channel.ends - ctime) / channel.tick_interval
			text_center = format('TICKS\n%.1f', max(0, channel.ticks))
			if channel.ability == Player.main then
				if channel.ticks_remain < 1 or channel.early_chainable then
					dim = false
					text_center = '|cFF00FF00CHAIN'
				end
			elseif channel.interruptible then
				dim = false
			end
		end
	end
	if MaelstromWeapon.known then
		text_tl = Player.maelstrom_weapon.current
	end
	if Player.elemental_remains > 0 then
		text_center = format('%.1fs', Player.elemental_remains)
	end
	farseerPanel.dimmer:SetShown(dim)
	farseerPanel.text.center:SetText(text_center)
	farseerPanel.text.tl:SetText(text_tl)
	--farseerPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
	farseerCooldownPanel.text:SetText(text_cd)
	farseerCooldownPanel.dimmer:SetShown(dim_cd)
end

function UI:UpdateCombat()
	Timer.combat = 0

	Player:Update()

	if Player.main then
		farseerPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = (Player.main.mana_cost > 0 and Player.main:ManaCost() == 0) or (Player.spec == SPEC.ELEMENTAL and Player.main.maelstrom_cost > 0 and Player.main:MaelstromCost() == 0) or (Player.main.Free and Player.main.Free())
	end
	if Player.cd then
		farseerCooldownPanel.icon:SetTexture(Player.cd.icon)
		if Player.cd.spellId then
			local cooldown = GetSpellCooldown(Player.cd.spellId)
			farseerCooldownPanel.swipe:SetCooldown(cooldown.startTime, cooldown.duration)
		end
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
			farseerInterruptPanel.swipe:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			farseerInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		farseerInterruptPanel.icon:SetShown(Player.interrupt)
		farseerInterruptPanel.border:SetShown(Player.interrupt)
		farseerInterruptPanel:SetShown(start and not notInterruptible)
	end
	if Opt.previous and farseerPreviousPanel.ability then
		if (Player.time - farseerPreviousPanel.ability.last_used) > 10 then
			farseerPreviousPanel.ability = nil
			farseerPreviousPanel:Hide()
		end
	end

	farseerPanel.icon:SetShown(Player.main)
	farseerPanel.border:SetShown(Player.main)
	farseerCooldownPanel:SetShown(Player.cd)
	farseerExtraPanel:SetShown(Player.extra)

	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - Timer.combat > seconds then
		Timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI Functions

-- Start Event Handling

function Events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = Farseer
		local firstRun = not Opt.frequency
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		if firstRun then
			log('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			log('Type |cFFFFD000' .. SLASH_Farseer1 .. '|r for a list of commands.')
			UI:SnapAllPanels()
		end
		if UnitLevel('player') < 10 then
			log('[|cFFFFD000Warning|r]', ADDON, 'is not designed for players under level 10, and almost certainly will not operate properly!')
		end
	end
end

CombatEvent.TRIGGER = function(timeStamp, event, _, srcGUID, _, _, _, dstGUID, _, _, _, ...)
	Player:UpdateTime(timeStamp)
	local e = event
	if (
	   e == 'UNIT_DESTROYED' or
	   e == 'UNIT_DISSIPATES' or
	   e == 'SPELL_INSTAKILL' or
	   e == 'PARTY_KILL')
	then
		e = 'UNIT_DIED'
	elseif (
	   e == 'SPELL_CAST_START' or
	   e == 'SPELL_CAST_SUCCESS' or
	   e == 'SPELL_CAST_FAILED' or
	   e == 'SPELL_DAMAGE' or
	   e == 'SPELL_ABSORBED' or
	   e == 'SPELL_ENERGIZE' or
	   e == 'SPELL_PERIODIC_DAMAGE' or
	   e == 'SPELL_MISSED' or
	   e == 'SPELL_AURA_APPLIED' or
	   e == 'SPELL_AURA_REFRESH' or
	   e == 'SPELL_AURA_REMOVED')
	then
		e = 'SPELL'
	end
	if CombatEvent[e] then
		return CombatEvent[e](event, srcGUID, dstGUID, ...)
	end
end

CombatEvent.UNIT_DIED = function(event, srcGUID, dstGUID)
	local uid = ToUID(dstGUID)
	if not uid or Target.Dummies[uid] then
		return
	end
	trackAuras:Remove(dstGUID)
	if Opt.auto_aoe then
		AutoAoe:Remove(dstGUID)
	end
	local pet = SummonedPets.byUnitId[uid]
	if pet then
		pet:RemoveUnit(dstGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.guid then
		if Opt.auto_aoe then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if srcGUID == Player.guid then
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SPELL_SUMMON = function(event, srcGUID, dstGUID)
	if srcGUID ~= Player.guid then
		return
	end
	local uid = ToUID(dstGUID)
	if not uid then
		return
	end
	local pet = SummonedPets.byUnitId[uid]
	if pet then
		pet:AddUnit(dstGUID)
	end
end

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	if srcGUID ~= Player.guid then
		local uid = ToUID(srcGUID)
		if uid then
			local pet = SummonedPets.byUnitId[uid]
			if pet then
				local unit = pet.active_units[srcGUID]
				if unit then
					if event == 'SPELL_CAST_SUCCESS' and pet.CastSuccess then
						pet:CastSuccess(unit, spellId, dstGUID)
					elseif event == 'SPELL_CAST_START' and pet.CastStart then
						pet:CastStart(unit, spellId, dstGUID)
					elseif event == 'SPELL_CAST_FAILED' and pet.CastFailed then
						pet:CastFailed(unit, spellId, dstGUID, missType)
					elseif (event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH') and pet.CastLanded then
						pet:CastLanded(unit, spellId, dstGUID, event, missType)
					end
					--log(format('PET %d EVENT %s SPELL %s ID %d', pet.unitId, event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
				end
			end
		end
		return
	end

	local ability = spellId and Abilities.bySpellId[spellId]
	if not ability then
		--log(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
		return
	end

	UI:UpdateCombatWithin(0.05)
	if event == 'SPELL_CAST_SUCCESS' then
		return ability:CastSuccess(dstGUID)
	elseif event == 'SPELL_CAST_START' then
		return ability.CastStart and ability:CastStart(dstGUID)
	elseif event == 'SPELL_CAST_FAILED'  then
		return ability.CastFailed and ability:CastFailed(dstGUID, missType)
	elseif event == 'SPELL_ENERGIZE' then
		return ability.Energize and ability:Energize(missType, overCap, powerType)
	end
	if ability.aura_targets then
		if event == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif event == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif event == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if dstGUID == Player.guid then
		if event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
			ability.last_gained = Player.time
		end
		return -- ignore buffs beyond here
	end
	if event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event, missType)
	end
end

function Events:COMBAT_LOG_EVENT_UNFILTERED()
	CombatEvent.TRIGGER(CombatLogGetCurrentEventInfo())
end

function Events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function Events:UNIT_FACTION(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_FLAGS(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_HEALTH(unitId)
	if unitId == 'player' then
		Player.health.current = UnitHealth(unitId)
		Player.health.max = UnitHealthMax(unitId)
		Player.health.pct = Player.health.current / Player.health.max * 100
	end
end

function Events:UNIT_MAXPOWER(unitId)
	if unitId == 'player' then
		Player.level = UnitLevel(unitId)
		Player.mana.base = Player.BaseMana[Player.level]
		Player.mana.max = UnitPowerMax(unitId, 0)
		Player.maelstrom.max = UnitPowerMax(unitId, 11)
	end
end

function Events:UNIT_SPELLCAST_START(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function Events:UNIT_SPELLCAST_STOP(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
Events.UNIT_SPELLCAST_FAILED = Events.UNIT_SPELLCAST_STOP
Events.UNIT_SPELLCAST_INTERRUPTED = Events.UNIT_SPELLCAST_STOP

function Events:UNIT_SPELLCAST_SUCCEEDED(unitId, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.traveling then
		ability.next_castGUID = castGUID
	end
end

function Events:UNIT_SPELLCAST_CHANNEL_UPDATE(unitId, castGUID, spellId)
	if unitId == 'player' then
		Player:UpdateChannelInfo()
	end
end
Events.UNIT_SPELLCAST_CHANNEL_START = Events.UNIT_SPELLCAST_CHANNEL_UPDATE
Events.UNIT_SPELLCAST_CHANNEL_STOP = Events.UNIT_SPELLCAST_CHANNEL_UPDATE

function Events:PLAYER_REGEN_DISABLED()
	Player:UpdateTime()
	Player.combat_start = Player.time
end

function Events:PLAYER_REGEN_ENABLED()
	Player:UpdateTime()
	Player.combat_start = 0
	Player.swing.last_taken = 0
	Target.estimated_range = 30
	wipe(Player.previous_gcd)
	if Player.last_ability then
		Player.last_ability = nil
		farseerPreviousPanel:Hide()
	end
	for _, ability in next, Abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
		end
	end
	if Opt.auto_aoe then
		AutoAoe:Clear()
	end
	if APL[Player.spec].precombat_variables then
		APL[Player.spec]:precombat_variables()
	end
end

function Events:PLAYER_EQUIPMENT_CHANGED()
	local _, equipType, hasCooldown
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

	Player.set_bonus.t29 = (Player:Equipped(200396) and 1 or 0) + (Player:Equipped(200398) and 1 or 0) + (Player:Equipped(200399) and 1 or 0) + (Player:Equipped(200400) and 1 or 0) + (Player:Equipped(200401) and 1 or 0)
	Player.set_bonus.t30 = (Player:Equipped(202468) and 1 or 0) + (Player:Equipped(202469) and 1 or 0) + (Player:Equipped(202470) and 1 or 0) + (Player:Equipped(202471) and 1 or 0) + (Player:Equipped(202473) and 1 or 0)
	Player.set_bonus.t31 = (Player:Equipped(207207) and 1 or 0) + (Player:Equipped(207208) and 1 or 0) + (Player:Equipped(207209) and 1 or 0) + (Player:Equipped(207210) and 1 or 0) + (Player:Equipped(207212) and 1 or 0)
	Player.set_bonus.t32 = (Player:Equipped(217236) and 1 or 0) + (Player:Equipped(217237) and 1 or 0) + (Player:Equipped(217238) and 1 or 0) + (Player:Equipped(217239) and 1 or 0) + (Player:Equipped(217240) and 1 or 0)
	Player.set_bonus.t33 = (Player:Equipped(212009) and 1 or 0) + (Player:Equipped(212010) and 1 or 0) + (Player:Equipped(212011) and 1 or 0) + (Player:Equipped(212012) and 1 or 0) + (Player:Equipped(212014) and 1 or 0)

	Player:UpdateKnown()
end

function Events:PLAYER_SPECIALIZATION_CHANGED(unitId)
	if unitId ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	farseerPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Events:PLAYER_EQUIPMENT_CHANGED()
	Events:PLAYER_REGEN_ENABLED()
	Events:UNIT_HEALTH('player')
	Events:UNIT_MAXPOWER('player')
	UI.OnResourceFrameShow()
	Target:Update()
	Player:Update()
end

function Events:TRAIT_CONFIG_UPDATED()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

function Events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, cooldown, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			cooldown = {
				startTime = castStart / 1000,
				duration = (castEnd - castStart) / 1000
			}
		else
			cooldown = GetSpellCooldown(61304)
		end
		farseerPanel.swipe:SetCooldown(cooldown.startTime, cooldown.duration)
	end
end

function Events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateKnown()
end

function Events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function Events:GROUP_ROSTER_UPDATE()
	Player.group_size = clamp(GetNumGroupMembers(), 1, 40)
end

function Events:PLAYER_ENTERING_WORLD()
	Player:Init()
	Target:Update()
	C_Timer.After(5, function() Events:PLAYER_EQUIPMENT_CHANGED() end)
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
	Timer.combat = Timer.combat + elapsed
	Timer.display = Timer.display + elapsed
	Timer.health = Timer.health + elapsed
	if Timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if Timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if Timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

farseerPanel:SetScript('OnEvent', function(self, event, ...) Events[event](self, ...) end)
for event in next, Events do
	farseerPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local SetHyperlink = ItemRefTooltip.SetHyperlink
ItemRefTooltip.SetHyperlink = function(self, link)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		BattleTagInviteFrame_Show(linkData)
		return
	end
	SetHyperlink(self, link)
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
	log(desc .. ':', opt_view, ...)
end

SlashCmdList[ADDON] = function(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		if Opt.aoe or Opt.snap then
			Status('Warning', 'Panels cannot be moved when aoe or snap are enabled!')
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
				Opt.locked = true
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
				Opt.locked = true
			else
				Opt.snap = false
				Opt.locked = false
				UI:Reset()
			end
			UI:UpdateDraggable()
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
			Opt.alpha = clamp(tonumber(msg[2]) or 100, 0, 100) / 100
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
		if startsWith(msg[2], 'anim') then
			if msg[3] then
				Opt.glow.animation = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Use extended animation (shrinking circle)', Opt.glow.animation)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = clamp(tonumber(msg[3]) or 0, 0, 1)
				Opt.glow.color.g = clamp(tonumber(msg[4]) or 0, 0, 1)
				Opt.glow.color.b = clamp(tonumber(msg[5]) or 0, 0, 1)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, |cFFFFD000animation|r, and |cFFFFD000color')
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
			Opt.cd_ttd = tonumber(msg[2]) or 10
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
	if startsWith(msg[1], 'he') then
		if msg[2] then
			Opt.heal = clamp(tonumber(msg[2]) or 60, 0, 100)
		end
		return Status('Health percentage threshold to recommend self healing spells', Opt.heal .. '%')
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
		UI:Reset()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. C_AddOns.GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r/|cFFFFD000animation|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
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
		'heal |cFFFFD000[percent]|r - health percentage threshold to recommend self healing spells (default is 60%, 0 to disable)',
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
