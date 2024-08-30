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
local GetTotemInfo = _G.GetTotemInfo
local GetWeaponEnchantInfo = _G.GetWeaponEnchantInfo
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
		funnel = false,
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
	tracked = {},
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

-- methods for tracking ticking debuffs on targets
local TrackedAuras = {}

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
	major_cd_remains = 0,
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
	293650, 344930, 405160, 475910, 559015, -- 75
	656630, 771290, -- 80
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
		{5, '5'},
		{6, '6+'},
	},
	[SPEC.ENHANCEMENT] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5'},
		{6, '6+'},
	},
	[SPEC.RESTORATION] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5'},
		{6, '6+'},
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
		maelstrom_gain = 0,
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

function Ability:React()
	return self:Remains()
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

function Ability:MaxStack()
	return self.max_stack
end

function Ability:ManaCost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * Player.mana.base) or 0
end

function Ability:MaelstromCost()
	return self.maelstrom_cost
end

function Ability:MaelstromGain()
	return self.maelstrom_gain
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

function TrackedAuras:Purge()
	for _, ability in next, Abilities.tracked do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function TrackedAuras:Remove(guid)
	for _, ability in next, Abilities.tracked do
		ability:RemoveAura(guid)
	end
end

function Ability:Track()
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
local FlameShock = Ability:Add(188389, false, true)
FlameShock.buff_duration = 18
FlameShock.cooldown_duration = 6
FlameShock.mana_cost = 0.3
FlameShock.tick_interval = 2
FlameShock.hasted_ticks = true
FlameShock:AutoAoe(false, 'apply')
FlameShock:Track()
local FlametongueWeapon = Ability:Add(318038, true, true)
FlametongueWeapon.enchant_id = 5400
local FrostShock = Ability:Add(196840, false, true)
FrostShock.buff_duration = 6
FrostShock.mana_cost = 0.2
local GhostWolf = Ability:Add(2645, true, true)
local HealingStreamTotem = Ability:Add(5394, true, true, 5672)
HealingStreamTotem.buff_duration = 15
HealingStreamTotem.cooldown_duration = 30
HealingStreamTotem.mana_cost = 5
HealingStreamTotem.summon_count = 1
local HealingSurge = Ability:Add(8004, true, true)
HealingSurge.mana_cost = 10
HealingSurge.consume_mw = true
local IceStrike = Ability:Add(342240, false, true)
IceStrike.buff_duration = 6
IceStrike.cooldown_duration = 15
IceStrike.hasted_cooldown = true
IceStrike.buff = Ability:Add(384357, true, true)
IceStrike.buff.buff_duration = 12
local LightningBolt = Ability:Add(188196, false, true)
LightningBolt.mana_cost = 0.2
LightningBolt.maelstrom_gain = 6
LightningBolt.consume_mw = true
LightningBolt.triggers_combat = true
LightningBolt:AutoAoe(false)
local LightningShield = Ability:Add(192106, true, true)
LightningShield.buff_duration = 3600
LightningShield.mana_cost = 0.3
local Skyfury = Ability:Add(462854, true, false)
Skyfury.buff_duration = 3600
Skyfury.mana_cost = 4
local Stormkeeper = Ability:Add({191634, 320137}, true, true)
Stormkeeper.buff_duration = 15
Stormkeeper.cooldown_duration = 60
------ Talents
local AstralShift = Ability:Add(108271, true, true)
AstralShift.buff_duration = 12
AstralShift.cooldown_duration = 120
local CapacitorTotem = Ability:Add(192058, false, true)
CapacitorTotem.buff_duration = 3
CapacitorTotem.cooldown_duration = 60
CapacitorTotem.mana_cost = 2
CapacitorTotem.summon_count = 1
local ChainHeal = Ability:Add(1064, true, true)
ChainHeal.mana_cost = 15
ChainHeal.consume_mw = true
local ChainLightning = Ability:Add(188443, false, true)
ChainLightning.mana_cost = 0.2
ChainLightning.maelstrom_gain = 2
ChainLightning.consume_mw = true
ChainLightning.triggers_combat = true
ChainLightning:AutoAoe(false)
local CleanseSpirit = Ability:Add(51886, false, true)
CleanseSpirit.cooldown_duration = 8
CleanseSpirit.mana_cost = 10
local DeeplyRootedElements = Ability:Add(378270, false, true)
local EarthElemental = Ability:Add(198103, true, true, 188616)
EarthElemental.buff_duration = 60
EarthElemental.cooldown_duration = 300
EarthElemental.summon_count = 1
local EarthShield = Ability:Add(974, true, true, 383648)
EarthShield.buff_duration = 600
EarthShield.cooldown_duration = 3
EarthShield.mana_cost = 5
local EchoOfTheElements = Ability:Add(333919, true, true)
local ElementalOrbit = Ability:Add(383010, false, true)
local EyeOfTheStorm = Ability:Add(381708, false, true)
local Hex = Ability:Add(51514, false, true)
Hex.buff_duration = 60
Hex.cooldown_duration = 30
Hex.triggers_combat = true
local LavaBurst = Ability:Add(51505, false, true, 285452)
LavaBurst.cooldown_duration = 8
LavaBurst.mana_cost = 0.5
LavaBurst.maelstrom_gain = 8
LavaBurst.requires_charge = true
LavaBurst.triggers_combat = true
LavaBurst:SetVelocity(50)
LavaBurst:AutoAoe(false)
local NaturesSwiftness = Ability:Add(378081, true, true)
NaturesSwiftness.buff_duration = 3600
NaturesSwiftness.cooldown_duration = 60
local PrimordialWave = Ability:Add(375982, false, true, 375984)
PrimordialWave.cooldown_duration = 30
PrimordialWave.mana_cost = 0.6
PrimordialWave.requires_charge = true
PrimordialWave.triggers_combat = true
PrimordialWave:SetVelocity(40)
PrimordialWave.buff = Ability:Add(375986, true, true)
PrimordialWave.buff.buff_duration = 15
PrimordialWave.buff.value = 1.75
local SpiritWalk = Ability:Add(58875, true, true)
SpiritWalk.buff_duration = 8
SpiritWalk.cooldown_duration = 60
local SpiritwalkersGrace = Ability:Add(79206, true, true)
SpiritwalkersGrace.buff_duration = 15
SpiritwalkersGrace.cooldown_duration = 120
SpiritwalkersGrace.mana_cost = 2.82
local SplinteredElements = Ability:Add(382042, true, true, 382043)
SplinteredElements.buff_duration = 12
local ThunderousPaws = Ability:Add(378075, true, true, 378076)
ThunderousPaws.buff_duration = 3
ThunderousPaws.cooldown_duration = 20
local Thunderstorm = Ability:Add(51490, false, true)
Thunderstorm.cooldown_duration = 30
Thunderstorm.buff_duration = 5
Thunderstorm:AutoAoe(false)
local TotemicProjection = Ability:Add(108287, false, true)
TotemicProjection.cooldown_duration = 10
local TotemicRecall = Ability:Add(108285, false, true)
TotemicRecall.cooldown_duration = 180
local WindShear = Ability:Add(57994, false, true)
WindShear.buff_duration = 2
WindShear.cooldown_duration = 12
-- Hero Talents
local AncestralSwiftness = Ability:Add(443454, true, true)
AncestralSwiftness.buff_duration = 3600
AncestralSwiftness.learn_spellId = 448861
AncestralSwiftness.cooldown_duration = 30
local ArcDischarge = Ability:Add(455096, true, true, 455097) -- Granted by Tempest
ArcDischarge.buff_duration = 15
local AwakeningStorms = Ability:Add(455129, true, true, 462131)
AwakeningStorms.buff_duration = 3600
AwakeningStorms.max_stack = 3
local Earthsurge = Ability:Add(455590, false, true)
local LivelyTotems = Ability:Add(445034, true, true, 458101)
LivelyTotems.buff_duration = 8
local Supercharge = Ability:Add(455110, false, true)
local SurgingTotem = Ability:Add(444995, false, true)
SurgingTotem.buff_duration = 24
SurgingTotem.cooldown_duration = 30
SurgingTotem.mana_cost = 0.4
SurgingTotem.summon_count = 1
local Tempest = Ability:Add(452201, false, true)
Tempest.learn_spellId = 454009
Tempest.mana_cost = 0.2
Tempest.maelstrom_spent = 0
Tempest.consume_mw = true
Tempest.requires_react = true
Tempest:AutoAoe(false)
Tempest.buff = Ability:Add(454015, true, true)
Tempest.buff.buff_duration = 30
Tempest.buff:Track()
local TotemicRebound = Ability:Add(445025, true, true, 458269)
TotemicRebound.buff_duration = 25
TotemicRebound.max_stack = 10
------ Procs
local LavaSurge = Ability:Add(77756, true, true, 77762)
LavaSurge.buff_duration = 10
---- Elemental
local MasterOfTheElements = Ability:Add(16166, true, true, 260734)
MasterOfTheElements.buff_duration = 15
------ Talents
local AscendanceFlame = Ability:Add(114050, true, true)
AscendanceFlame.buff_duration = 15
AscendanceFlame.cooldown_duration = 180
local EarthShock = Ability:Add(8042, false, true)
EarthShock.maelstrom_cost = 60
local Earthquake = Ability:Add({61882, 462620}, false, true, 77478)
Earthquake.buff_duration = 6
Earthquake.maelstrom_cost = 60
Earthquake:AutoAoe(true)
local EchoChamber = Ability:Add(382032, false, true)
local EchoesOfGreatSundering = Ability:Add(384087, true, true, 384088)
EchoesOfGreatSundering.buff_duration = 25
local ElementalBlast = Ability:Add(117014, false, true)
ElementalBlast.mana_cost = 0.55
ElementalBlast.maelstrom_cost = 90
ElementalBlast.cooldown_duration = 12
ElementalBlast.consume_mw = true
ElementalBlast.requires_charge = true
ElementalBlast.triggers_combat = true
ElementalBlast:SetVelocity(40)
ElementalBlast.crit = Ability:Add(118522, true, true)
ElementalBlast.crit.buff_duration = 10
ElementalBlast.haste = Ability:Add(173183, true, true)
ElementalBlast.haste.buff_duration = 10
ElementalBlast.mastery = Ability:Add(173184, true, true)
ElementalBlast.mastery.buff_duration = 10
local FireElemental = Ability:Add(198067, true, true, 188592)
FireElemental.buff_duration = 30
FireElemental.cooldown_duration = 150
FireElemental.mana_cost = 1
FireElemental.summon_count = 1
local FlamesOfTheCauldron = Ability:Add(378266, true, true)
local FlowOfPower = Ability:Add(385923, false, true)
local FusionOfElements = Ability:Add(462840, true, true)
FusionOfElements.fire = Ability:Add(462843, true, true)
FusionOfElements.fire.buff_duration = 20
FusionOfElements.nature = Ability:Add(462841, true, true)
FusionOfElements.nature.buff_duration = 20
local ImprovedFlametongueWeapon = Ability:Add(382027, true, true, 382028)
ImprovedFlametongueWeapon.buff_duration = 3600
local LavaBeam = Ability:Add(114074, false, true) -- Replaces Lava Burst during AscendanceFlame
LavaBeam.triggers_combat = true
LavaBeam:AutoAoe(false)
local LightningRod = Ability:Add(210689, true, true, 197209)
LightningRod.buff_duration = 8
LightningRod.value = 0.20
local LiquidMagmaTotem = Ability:Add(192222, false, true)
LiquidMagmaTotem.buff_duration = 6
LiquidMagmaTotem.cooldown_duration = 30
LiquidMagmaTotem.mana_cost = 0.7
LiquidMagmaTotem.summon_count = 1
LiquidMagmaTotem:AutoAoe(false)
local MagmaChamber = Ability:Add(381932, true, true, 381933)
MagmaChamber.buff_duration = 21
MagmaChamber.max_stack = 10
local PowerOfTheMaelstrom = Ability:Add(191861, true, true, 191877)
PowerOfTheMaelstrom.buff_duration = 20
PowerOfTheMaelstrom.max_stack = 2
local PrimalElementalist = Ability:Add(117013, true, true)
local SearingFlames = Ability:Add(381782, false, true)
local StormElemental = Ability:Add(192249, true, true, 157299)
StormElemental.buff_duration = 30
StormElemental.cooldown_duration = 150
StormElemental.mana_cost = 1
StormElemental.totem_icon = 1020304
StormElemental.summon_count = 1
local StormFrenzy = Ability:Add(462695, true, true, 462725)
StormFrenzy.buff_duration = 12
StormFrenzy.max_stack = 2
local SurgeOfPower = Ability:Add(262303, true, true, 285514)
SurgeOfPower.buff_duration = 15
local ThunderstrikeWard = Ability:Add(462757, true, true)
ThunderstrikeWard.buff_duration = 3600
ThunderstrikeWard.enchant_id = 7587
------ Procs
local Icefury = Ability:Add(462816, true, true, 462818)
Icefury.buff_duration = 30
Icefury.mana_cost = 0.6
Icefury.max_stack = 2
Icefury.requires_react = true
Icefury.triggers_combat = true
Icefury:SetVelocity(40)
Icefury.damage = Ability:Add(210714, false, true)
Icefury.damage.buff_duration = 25
Icefury.damage.max_stack = 4
---- Enhancement
local MaelstromWeapon = Ability:Add(187880, true, true, 344179)
MaelstromWeapon.buff_duration = 30
MaelstromWeapon.max_stack = 5
------ Talents
local AlphaWolf = Ability:Add(198434, true, true, 198486)
AlphaWolf.buff_duration = 8
local AscendanceAir = Ability:Add(114051, true, true)
AscendanceAir.buff_duration = 15
AscendanceAir.cooldown_duration = 180
local AshenCatalyst = Ability:Add(390370, true, true, 390371)
AshenCatalyst.buff_duration = 15
AshenCatalyst.max_stack = 8
local ConvergingStorms = Ability:Add(384363, true, true, 198300)
ConvergingStorms.buff_duration = 12
ConvergingStorms.max_stack = 6
local CrashingStorms = Ability:Add(334308, true, true)
local CrashLightning = Ability:Add(187874, false, true)
CrashLightning.cooldown_duration = 12
CrashLightning.mana_cost = 0.2
CrashLightning.hasted_cooldown = true
CrashLightning:AutoAoe(true)
CrashLightning.buff = Ability:Add(187878, true, true)
CrashLightning.buff.buff_duration = 12
local DoomWinds = Ability:Add(384352, true, true)
DoomWinds.buff_duration = 8
DoomWinds.cooldown_duration = 60
local ElementalAssault = Ability:Add(210853, false, true)
local ElementalSpirits = Ability:Add(262624, false, true)
local FeralSpirit = Ability:Add(51533, true, true, 333957)
FeralSpirit.buff_duration = 15
FeralSpirit.cooldown_duration = 180
FeralSpirit.summon_count = 2
local FireNova = Ability:Add(333974, false, true, 333977)
FireNova.mana_cost = 0.2
FireNova.cooldown_duration = 15
FireNova:AutoAoe(true)
local ForcefulWinds = Ability:Add(262647, true, true, 262652)
ForcefulWinds.buff_duration = 15
ForcefulWinds.max_stack = 5
local Hailstorm = Ability:Add(334195, true, true, 334196)
Hailstorm.buff_duration = 20
Hailstorm.max_stack = 10
local HotHand = Ability:Add(201900, true, true, 215785)
HotHand.buff_duration = 15
local LashingFlames = Ability:Add(334046, false, true, 334168)
LashingFlames.buff_duration = 20
local LavaLash = Ability:Add(60103, false, true)
LavaLash.cooldown_duration = 18
LavaLash.mana_cost = 0.16
LavaLash.hasted_cooldown = true
local MoltenAssault = Ability:Add(334033, false, true)
local RagingMaelstrom = Ability:Add(384143, false, true)
local StaticAccumulation = Ability:Add(384411, true, true, 384437)
StaticAccumulation.buff_duration = 15
StaticAccumulation.tick_interval = 1
local Stormblast = Ability:Add(319930, true, true)
local Stormstrike = Ability:Add(17364, false, true)
Stormstrike.cooldown_duration = 7.5
Stormstrike.mana_cost = 0.4
Stormstrike.hasted_cooldown = true
local Sundering = Ability:Add(197214, false, true)
Sundering.buff_duration = 2
Sundering.cooldown_duration = 40
Sundering.mana_cost = 1.2
Sundering:AutoAoe(false)
local SwirlingMaelstrom = Ability:Add(384359, false, true)
local ThorimsInvocation = Ability:Add(384444, true, true)
local UnrulyWinds = Ability:Add(390288, false, true)
local WindfuryWeapon = Ability:Add(33757, true, true)
WindfuryWeapon.enchant_id = 5401
local Windstrike = Ability:Add(115356, false, true) -- Replaces Stormstrike during AscendanceAir
Windstrike.cooldown_duration = 7.5
Windstrike.hasted_cooldown = true
local WitchDoctorsAncestry = Ability:Add(384447, false, true)
local LegacyOfTheFrostWitch = Ability:Add(384450, true, true, 384451)
LegacyOfTheFrostWitch.buff_duration = 5
------ Procs
local ClCrashLightning = Ability:Add(333964, true, true)
ClCrashLightning.buff_duration = 15
ClCrashLightning.max_stack = 3
local CracklingSurge = Ability:Add(224127, true, true) -- Granted by Elemental Spirits
CracklingSurge.buff_duration = 15
local IcyEdge = Ability:Add(224126, true, true) -- Granted by Elemental Spirits
IcyEdge.buff_duration = 15
local MoltenWeapon = Ability:Add(224125, true, true) -- Granted by Elemental Spirits
MoltenWeapon.buff_duration = 15
local Stormbringer = Ability:Add(201845, true, true, 201846)
Stormbringer.buff_duration = 12
---- Restoration

------ Talents

------ Procs

-- Tier set bonuses
local CracklingThunder = Ability:Add(409834, true, true) -- T30 4pc (Enhancement)
CracklingThunder.buff_duration = 15
local MaelstromSurge = Ability:Add(457727, true, true) -- T33 4pc (Elemental)
MaelstromSurge.buff_duration = 5
local VolcanicStrength = Ability:Add(409833, true, true) -- T30 4pc (Enhancement)
VolcanicStrength.buff_duration = 15
-- Racials

-- PvP talents

-- Trinket effects

-- Class buffs
local ChaosBrand = Ability:Add(1490, false, false)
ChaosBrand.value = 0.03
local HuntersMark = Ability:Add(257284, false, false)
HuntersMark.value = 0.05

-- Class cooldowns
local Bloodlust = Ability:Add(2825, false, true)
Bloodlust.buff_duration = 40
Bloodlust.cooldown_duration = 300
Bloodlust.mana_cost = 0.4
local Heroism = Ability:Add(32182, true, false)
Heroism.buff_duration = 40
Heroism.cooldown_duration = 300
Heroism.mana_cost = 0.4
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
Pet.SpiritWolf = SummonedPet:Add(29264, 15, FeralSpirit)
Pet.ElementalSpiritWolf = SummonedPet:Add(100820, 15, ElementalSpirits)
-- Totems
Pet.CapacitorTotem = SummonedPet:Add(61245, 2, CapacitorTotem)
Pet.HealingStreamTotem = SummonedPet:Add(3527, 15, HealingStreamTotem)
Pet.LiquidMagmaTotem = SummonedPet:Add(97369, 5, LiquidMagmaTotem)
Pet.SurgingTotem = SummonedPet:Add(225409, 24, SurgingTotem)
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
	wipe(self.tracked)
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
				self.tracked[#self.tracked + 1] = ability
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

	CrashLightning.buff.known = CrashLightning.known
	IceStrike.buff.known = IceStrike.known
	Windstrike.known = AscendanceAir.known or DeeplyRootedElements.known
	LavaBeam.known = AscendanceFlame.known or DeeplyRootedElements.known
	PrimordialWave.buff.known = PrimordialWave.known
	Tempest.buff.known = Tempest.known
	if FrostShock.known then
		if Hailstorm.known then
			FrostShock:AutoAoe(false)
		else
			FrostShock.auto_aoe = nil
		end
	end
	if self.spec == SPEC.ENHANCEMENT then
		FlameShock.hasted_cooldown = true
		FrostShock.cooldown_duration = 6
		FrostShock.hasted_cooldown = true
		if ElementalBlast.known then
			LavaBurst.known = false
		end
		if self.set_bonus.t30 >= 4 then
			CracklingThunder.known = true
			VolcanicStrength.known = true
		end
	else
		FlameShock.hasted_cooldown = false
		FrostShock.cooldown_duration = 0
		FrostShock.hasted_cooldown = false
	end
	if self.spec == SPEC.ELEMENTAL then
		if self.set_bonus.t33 >= 4 then
			MaelstromSurge.known = true
		end
	end
	if ElementalSpirits.known then
		CracklingSurge.known = true
		IcyEdge.known = true
		MoltenWeapon.known = true
	end
	if FusionOfElements.known then
		FusionOfElements.fire.known = true
		FusionOfElements.nature.known = true
	end
	if ElementalBlast.known then
		ElementalBlast.crit.known = true
		ElementalBlast.haste.known = true
		ElementalBlast.mastery.known = true
	end
	MaelstromWeapon.max = MaelstromWeapon.max_stack + (RagingMaelstrom.known and 5 or 0)

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
		if self.cast.ability then
			if self.cast.ability.maelstrom_cost > 0 then
				self.maelstrom.current = self.maelstrom.current - self.cast.ability:MaelstromCost()
			end
			if self.cast.ability.maelstrom_gain > 0 then
				self.maelstrom.current = self.maelstrom.current + self.cast.ability:MaelstromGain()
			end
		end
		self.maelstrom.current = clamp(self.maelstrom.current, 0, self.maelstrom.max)
		self.maelstrom.deficit = self.maelstrom.max - self.maelstrom.current
	elseif self.spec == SPEC.ENHANCEMENT then
		if self.cast.ability and self.cast.ability.consume_mw then
			MaelstromWeapon.current = 0
		else
			MaelstromWeapon.current = MaelstromWeapon:Stack()
		end
		MaelstromWeapon.deficit = MaelstromWeapon.max - MaelstromWeapon.current
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
	TrackedAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, Abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		AutoAoe:Purge()
	end

	self.major_cd_remains = max(AscendanceAir:Remains(), AscendanceFlame:Remains())

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

EyeOfTheStorm.cost_reduction = {
	[EarthShock] = 5,
	[Earthquake] = 5,
	[ElementalBlast] = 10,
}

FlowOfPower.gain_increase = {
	[LavaBurst] = 2,
	[LightningBolt] = 2,
}

local function TotemRemains(self)
	local _, start, duration, icon
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
CapacitorTotem.Remains = TotemRemains
HealingStreamTotem.Remains = TotemRemains
LiquidMagmaTotem.Remains = TotemRemains
SurgingTotem.Remains = TotemRemains
EarthElemental.Remains = TotemRemains
FireElemental.Remains = TotemRemains
StormElemental.Remains = TotemRemains

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
ThunderstrikeWard.Remains = WeaponEnchantRemains

function LavaBurst:Free()
	return LavaSurge:Up()
end

function Stormstrike:Usable()
	if AscendanceAir:Up() then
		return false
	end
	return Ability.Usable(self)
end

function LightningBolt:Usable()
	if Tempest.known and Tempest:React() > 0 then
		return false
	end
	return Ability.Usable(self)
end

function ChainLightning:Usable()
	if AscendanceFlame:Up() then
		return false
	end
	return Ability.Usable(self)
end

function LightningBolt:Free()
	return (Stormkeeper.known and Stormkeeper:Up()) or (NaturesSwiftness.known and NaturesSwiftness:Up())
end
ChainLightning.Free = LightningBolt.Free

function LightningBolt:MaelstromGain()
	local gain = Ability.MaelstromGain(self)
	if FlowOfPower.known then
		gain = gain + FlowOfPower.gain_increase[self]
	end
	return gain
end
LavaBurst.MaelstromGain = LightningBolt.MaelstromGain

function ChainLightning:MaelstromGain()
	return Ability.MaelstromGain(self) * min(5, Player.enemies)
end

function ChainLightning:Damage()
	return 613 -- TODO: Calculate actual damage
end

function ChainLightning:Targets()
	return min(Player.enemies, (Player.spec == SPEC.ELEMENTAL and 5 or 3) + (CrashingStorms.known and 2 or 0))
end

function LightningBolt:Damage()
	return 1000 -- TODO: Calculate actual damage
end

function LightningBolt:Targets()
	if PrimordialWave.known and PrimordialWave.buff:Up() then
		return FlameShock:Ticking()
	end
	return 1
end

function EarthShock:MaelstromCost()
	local cost = Ability.MaelstromCost(self)
	if EyeOfTheStorm.known then
		cost = cost - EyeOfTheStorm.cost_reduction[self]
	end
	return max(0, cost)
end
Earthquake.MaelstromCost = EarthShock.MaelstromCost
ElementalBlast.MaelstromCost = EarthShock.MaelstromCost

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
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				ticking[guid] = true
			end
		end
	end
	if PrimordialWave.known then
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

function MaelstromWeapon:MaxStack()
	local stack = Ability.MaxStack(self)
	if RagingMaelstrom.known then
		stack = stack + 5
	end
	return stack
end

function Hailstorm:Stack()
	local stack = Ability.Stack(self)
	if Player.cast.ability and Player.cast.ability.consume_mw then
		stack = stack + MaelstromWeapon.current
	end
	return clamp(stack, 0, self.max_stack)
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

function MasterOfTheElements:Remains()
	if LavaBurst:Casting() then
		return self:Duration()
	end
	local remains = Ability.Remains(self)
	if remains > 0 and (LightningBolt:Casting() or ChainLightning:Casting() or (ElementalBlast.known and ElementalBlast:Casting())) then
		return 0
	end
	return remains
end

function AlphaWolf:MinRemains()
	return 0 -- TODO
end

function ThorimsInvocation:LightningBolt()
	return ChainLightning.last_used <= LightningBolt.last_used
end

function ThorimsInvocation:ChainLightning()
	return ChainLightning.last_used > LightningBolt.last_used
end

function Tempest:React()
	return self.buff:Remains()
end

function Tempest:Maelstrom()
	return self.maelstrom_spent
end

function Tempest.buff:ApplyAura()
	Tempest.maelstrom_spent = max(0, Tempest.maelstrom_spent - 40)
end
Tempest.buff.RefreshAura = Tempest.buff.ApplyAura

function ClCrashLightning:MaxStack()
	local stack = Ability.MaxStack(self)
	if CrashingStorms.known then
		stack = stack + 2
	end
	return stack
end

-- End Ability Modifications

-- Start Summoned Pet Modifications

function Pet.LiquidMagmaTotem:CastLanded(unit, spellId, dstGUID, event, missType)
	if Opt.auto_aoe and event == 'SPELL_DAMAGE' then
		LiquidMagmaTotem:RecordTargetHit(dstGUID)
	end
end

-- End Summoned Pet Modifications

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
	self.cds_active = (AscendanceFlame.known and AscendanceFlame:Up()) or (FireElemental.known and FireElemental:Up()) or (StormElemental.known and StormElemental:Up())
	self.use_cds = Opt.cooldown and (self.cds_active or Target.boss or Target.player or (not Opt.boss_only and Target.timeToDie > Opt.cd_ttd))
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
actions.precombat+=/snapshot_stats
actions.precombat+=/flametongue_weapon,if=talent.improved_flametongue_weapon.enabled
actions.precombat+=/potion
actions.precombat+=/stormkeeper
actions.precombat+=/lightning_shield
actions.precombat+=/thunderstrike_ward
actions.precombat+=/variable,name=mael_cap,value=100+50*talent.swelling_maelstrom.enabled+25*talent.primordial_capacity.enabled,op=set
actions.precombat+=/variable,name=spymaster_in_1st,value=trinket.1.is.spymasters_web
actions.precombat+=/variable,name=spymaster_in_2nd,value=trinket.2.is.spymasters_web
]]
		if Skyfury:Usable() and Skyfury:Remains() < 300 then
			UseCooldown(Skyfury)
		elseif ImprovedFlametongueWeapon.known and FlametongueWeapon:Usable() and FlametongueWeapon:Remains() < 300 then
			UseCooldown(FlametongueWeapon)
		elseif ThunderstrikeWard:Usable() and ThunderstrikeWard:Remains() < 300 then
			UseCooldown(ThunderstrikeWard)
		elseif Opt.shield and LightningShield:Usable() and LightningShield:Remains() < 300 then
			UseCooldown(LightningShield)
		elseif Opt.shield and ElementalOrbit.known and EarthShield:Usable() and (EarthShield:Remains() < 150 or EarthShield:Stack() <= 3) then
			UseCooldown(EarthShield)
		end
		if Opt.earth and self.use_cds and EarthElemental:Usable() and not PrimalElementalist.known then
			UseExtra(EarthElemental)
		end
		if self.use_cds and Stormkeeper:Usable() and Stormkeeper:Down() then
			UseCooldown(Stormkeeper)
		end
	else
		if Skyfury:Usable() and Skyfury:Down() then
			UseExtra(Skyfury)
		elseif ImprovedFlametongueWeapon.known and FlametongueWeapon:Usable() and FlametongueWeapon:Down() then
			UseExtra(FlametongueWeapon)
		elseif ThunderstrikeWard:Usable() and ThunderstrikeWard:Down() then
			UseExtra(ThunderstrikeWard)
		elseif Opt.shield and LightningShield:Usable() and LightningShield:Down() then
			UseExtra(LightningShield)
		elseif Opt.shield and ElementalOrbit.known and EarthShield:Usable() and EarthShield:Down() then
			UseExtra(EarthShield)
		elseif Player.moving and SpiritwalkersGrace:Usable() then
			UseExtra(SpiritwalkersGrace)
		end
	end
--[[
actions=spiritwalkers_grace,moving=1,if=movement.distance>6
actions+=/wind_shear
actions+=/blood_fury,if=!talent.ascendance.enabled|buff.ascendance.up|cooldown.ascendance.remains>50
actions+=/berserking,if=!talent.ascendance.enabled|buff.ascendance.up
actions+=/fireblood,if=!talent.ascendance.enabled|buff.ascendance.up|cooldown.ascendance.remains>50
actions+=/ancestral_call,if=!talent.ascendance.enabled|buff.ascendance.up|cooldown.ascendance.remains>50
actions+=/use_item,slot=trinket1,if=!variable.spymaster_in_1st|target.time_to_die<45&cooldown.stormkeeper.remains<5|fight_remains<22
actions+=/use_item,slot=trinket2,if=!variable.spymaster_in_2nd|target.time_to_die<45&cooldown.stormkeeper.remains<5|fight_remains<22
actions+=/use_item,slot=main_hand
actions+=/lightning_shield,if=buff.lightning_shield.down
actions+=/natures_swiftness
actions+=/invoke_external_buff,name=power_infusion
actions+=/potion
actions+=/run_action_list,name=aoe,if=spell_targets.chain_lightning>2
actions+=/run_action_list,name=single_target
]]
	if self.use_cds then
		if Opt.trinket and (
			self.cds_active or
			(Target.boss and (Target.timeToDie < 22 or Stormkeeper:Ready(5) and Target.timeToDie < 45))
		) then
			if Trinket1:Usable() then
				UseCooldown(Trinket1)
			elseif Trinket2:Usable() then
				UseCooldown(Trinket2)
			end
		end
		if NaturesSwiftness:Usable() and NaturesSwiftness:Down() then
			UseCooldown(NaturesSwiftness)
		end
	end
	if Player.enemies > 2 then
		return self:aoe()
	end
	return self:single_target()
end

APL[SPEC.ELEMENTAL].aoe_cds = function(self)
--[[
actions.aoe=fire_elemental,if=!buff.fire_elemental.up
actions.aoe+=/storm_elemental,if=!buff.storm_elemental.up
actions.aoe+=/stormkeeper,if=!buff.stormkeeper.up
actions.aoe+=/totemic_recall,if=cooldown.liquid_magma_totem.remains>15&talent.fire_elemental.enabled
actions.aoe+=/liquid_magma_totem
actions.aoe+=/primordial_wave,target_if=min:dot.flame_shock.remains,if=buff.surge_of_power.up|!talent.surge_of_power.enabled|maelstrom<60-5*talent.eye_of_the_storm.enabled
actions.aoe+=/ancestral_swiftness
]]
	if FireElemental:Usable() and FireElemental:Down() then
		UseCooldown(FireElemental)
	end
	if StormElemental:Usable() and StormElemental:Down() then
		UseCooldown(StormElemental)
	end
	if Stormkeeper:Usable() and Stormkeeper:Down() then
		UseCooldown(Stormkeeper)
	end
	if FireElemental.known and TotemicRecall:Usable() and not LiquidMagmaTotem:Ready(15) then
		UseCooldown(TotemicRecall)
	end
	if LiquidMagmaTotem:Usable() then
		UseCooldown(LiquidMagmaTotem)
	end
	if PrimordialWave:Usable() and (not SurgeOfPower.known or SurgeOfPower:Up() or Player.maelstrom.current < (60 - (EyeOfTheStorm.known and 5 or 0))) then
		UseCooldown(PrimordialWave)
	end
	if AncestralSwiftness:Usable() then
		UseCooldown(AncestralSwiftness)
	end
end

APL[SPEC.ELEMENTAL].aoe = function(self)
--[[
actions.aoe+=/flame_shock,target_if=refreshable,if=buff.surge_of_power.up&talent.lightning_rod.enabled&dot.flame_shock.remains<target.time_to_die-16&active_dot.flame_shock<(spell_targets.chain_lightning>?6)&!talent.liquid_magma_totem.enabled
actions.aoe+=/flame_shock,target_if=min:dot.flame_shock.remains,if=buff.primordial_wave.up&buff.stormkeeper.up&maelstrom<60-5*talent.eye_of_the_storm.enabled-(8+2*talent.flow_of_power.enabled)*active_dot.flame_shock&spell_targets.chain_lightning>=6&active_dot.flame_shock<6
actions.aoe+=/flame_shock,target_if=refreshable,if=talent.fire_elemental.enabled&(buff.surge_of_power.up|!talent.surge_of_power.enabled)&dot.flame_shock.remains<target.time_to_die-5&(active_dot.flame_shock<6|dot.flame_shock.remains>0)
actions.aoe+=/tempest,target_if=min:debuff.lightning_rod.remains,if=!buff.arc_discharge.up
actions.aoe+=/ascendance
actions.aoe+=/lava_beam,if=active_enemies>=6&buff.surge_of_power.up&buff.ascendance.remains>cast_time
actions.aoe+=/chain_lightning,if=active_enemies>=6&buff.surge_of_power.up
actions.aoe+=/lava_burst,target_if=dot.flame_shock.remains>2,if=buff.primordial_wave.up&buff.stormkeeper.up&maelstrom<60-5*talent.eye_of_the_storm.enabled&spell_targets.chain_lightning>=6&talent.surge_of_power.enabled
actions.aoe+=/lava_burst,target_if=dot.flame_shock.remains>2,if=buff.primordial_wave.up&(buff.primordial_wave.remains<4|buff.lava_surge.up)
actions.aoe+=/lava_burst,target_if=dot.flame_shock.remains,if=cooldown_react&buff.lava_surge.up&!buff.master_of_the_elements.up&talent.master_of_the_elements.enabled&talent.fire_elemental.enabled
actions.aoe+=/earthquake,if=cooldown.primordial_wave.remains<gcd&talent.surge_of_power.enabled&(buff.echoes_of_great_sundering_es.up|buff.echoes_of_great_sundering_eb.up|!talent.echoes_of_great_sundering.enabled)
actions.aoe+=/earthquake,target_if=max:debuff.lightning_rod.remains,if=(debuff.lightning_rod.remains=0&talent.lightning_rod.enabled|maelstrom>variable.mael_cap-30)&(buff.echoes_of_great_sundering_es.up|buff.echoes_of_great_sundering_eb.up|!talent.echoes_of_great_sundering.enabled)
actions.aoe+=/earthquake,if=buff.stormkeeper.up&spell_targets.chain_lightning>=6&talent.surge_of_power.enabled&(buff.echoes_of_great_sundering_es.up|buff.echoes_of_great_sundering_eb.up|!talent.echoes_of_great_sundering.enabled)
actions.aoe+=/earthquake,if=(buff.master_of_the_elements.up|spell_targets.chain_lightning>=5)&(buff.fusion_of_elements_nature.up|buff.ascendance.remains>9|!buff.ascendance.up)&(buff.echoes_of_great_sundering_es.up|buff.echoes_of_great_sundering_eb.up|!talent.echoes_of_great_sundering.enabled)&talent.fire_elemental.enabled
actions.aoe+=/elemental_blast,target_if=min:debuff.lightning_rod.remains,if=talent.echoes_of_great_sundering.enabled&!buff.echoes_of_great_sundering_eb.up&(!buff.maelstrom_surge.up&set_bonus.tww1_4pc|maelstrom>variable.mael_cap-30)
actions.aoe+=/earth_shock,target_if=min:debuff.lightning_rod.remains,if=talent.echoes_of_great_sundering.enabled&!buff.echoes_of_great_sundering_es.up&(!buff.maelstrom_surge.up&set_bonus.tww1_4pc|maelstrom>variable.mael_cap-30)
actions.aoe+=/icefury,if=talent.fusion_of_elements.enabled&!(buff.fusion_of_elements_nature.up|buff.fusion_of_elements_fire.up)
actions.aoe+=/lava_burst,target_if=dot.flame_shock.remains>2,if=talent.master_of_the_elements.enabled&!buff.master_of_the_elements.up&!buff.ascendance.up&talent.fire_elemental.enabled
actions.aoe+=/lava_beam,if=buff.stormkeeper.up&(buff.surge_of_power.up|spell_targets.lava_beam<6)
actions.aoe+=/chain_lightning,if=buff.stormkeeper.up&(buff.surge_of_power.up|spell_targets.chain_lightning<6)
actions.aoe+=/lava_beam,if=buff.power_of_the_maelstrom.up&buff.ascendance.remains>cast_time&!buff.stormkeeper.up
actions.aoe+=/chain_lightning,if=buff.power_of_the_maelstrom.up&!buff.stormkeeper.up
actions.aoe+=/lava_beam,if=(buff.master_of_the_elements.up&spell_targets.lava_beam>=4|spell_targets.lava_beam>=5)&buff.ascendance.remains>cast_time&!buff.stormkeeper.up
actions.aoe+=/lava_burst,target_if=dot.flame_shock.remains>2,if=talent.deeply_rooted_elements.enabled
actions.aoe+=/lava_beam,if=buff.ascendance.remains>cast_time
actions.aoe+=/chain_lightning
actions.aoe+=/flame_shock,moving=1,target_if=refreshable
actions.aoe+=/frost_shock,moving=1
]]
	if self.use_cds then
		self:aoe_cds()
	end
	if FlameShock:Usable() and FlameShock:Refreshable() and (
		(not self.use_cds and FlameShock:Down()) or
		(LightningRod.known and SurgeOfPower.known and not LiquidMagmaTotem.known and SurgeOfPower:Up() and Target.timeToDie > (FlameShock:Remains() + 16) and FlameShock:Ticking() < min(Player.enemies, 6)) or
		(Stormkeeper.known and Player.enemies >= 6 and PrimordialWave.buff:Up() and Stormkeeper:Up() and FlameShock:Ticking() < 6 and Player.maelstrom.current < (60 - (EyeOfTheStorm.known and 5 or 0) - ((8 + (FlowOfPower.known and 2 or 0)) * FlameShock:Ticking()))) or
		(FireElemental.known and (not SurgeOfPower.known or SurgeOfPower:Up()) and Target.timeToDie > (FlameShock:Remains() + 5) and (FlameShock:Ticking() < 6 or FlameShock:Up()))
	) then
		return FlameShock
	end
	if Tempest:Usable() and (ArcDischarge:Down() or Tempest.buff:Remains() < 4) then
		return Tempest
	end
	if self.use_cds and AscendanceFlame:Usable() and AscendanceFlame:Down() then
		UseCooldown(AscendanceFlame)
	end
	if SurgeOfPower.known and Player.enemies >= 6 then
		if LavaBeam:Usable() and SurgeOfPower:Up() and AscendanceFlame:Remains() > LavaBeam:CastTime() then
			return LavaBeam
		end
		if ChainLightning:Usable() and SurgeOfPower:Up() then
			return ChainLightning
		end
		if Stormkeeper.known and LavaBurst:Usable() and PrimordialWave.buff:Up() and Stormkeeper:Up() and Player.maelstrom.current < (60 - (EyeOfTheStorm.known and 5 or 0)) then
			return LavaBurst
		end
	end
	if LavaBurst:Usable() and PrimordialWave.buff:Up() and (PrimordialWave.buff:Remains() < 4 or LavaSurge:Up()) then
		return LavaBurst
	end
	if MasterOfTheElements.known and FireElemental.known and LavaBurst:Usable() and LavaSurge:Up() and MasterOfTheElements:Down() then
		return LavaBurst
	end
	if Earthquake:Usable() and (not EchoesOfGreatSundering.known or EchoesOfGreatSundering:Up()) and (
		Player.maelstrom.deficit < 30 or
		(SurgeOfPower.known and (PrimordialWave:Ready(Player.gcd) or (Player.enemies >= 6 and Stormkeeper:Up()))) or
		(LightningRod.known and LightningRod:Down()) or
		(FireElemental.known and (Player.enemies >= 5 or MasterOfTheElements:Up() and (FusionOfElements.nature:Up() or AscendanceFlame:Remains() > 9 or AscendanceFlame:Down())))
	) then
		return Earthquake
	end
	if EchoesOfGreatSundering.known then
		if ElementalBlast:Usable() and EchoesOfGreatSundering:Down() and (Player.maelstrom.deficit < 30 or (MaelstromSurge.known and MaelstromSurge:Down())) then
			return ElementalBlast
		end
		if EarthShock:Usable() and EchoesOfGreatSundering:Down() and (Player.maelstrom.deficit < 30 or (MaelstromSurge.known and MaelstromSurge:Down())) then
			return EarthShock
		end
	end
	if FusionOfElements.known and Icefury:Usable() and not (FusionOfElements.nature:Up() or FusionOfElements.fire:Up()) then
		return Icefury
	end
	if MasterOfTheElements.known and FireElemental.known and LavaBurst:Usable() and MasterOfTheElements:Down() and AscendanceFlame:Down() then
		return LavaBurst
	end
	if LavaBeam:Usable() and Stormkeeper:Up() and (Player.enemies < 6 or SurgeOfPower:Up()) then
		return LavaBeam
	end
	if ChainLightning:Usable() and Stormkeeper:Up() and (Player.enemies < 6 or SurgeOfPower:Up()) then
		return ChainLightning
	end
	if LavaBeam:Usable() and Stormkeeper:Down() and PowerOfTheMaelstrom:Up() and AscendanceFlame:Remains() > LavaBeam:CastTime() then
		return LavaBeam
	end
	if ChainLightning:Usable() and Stormkeeper:Down() and PowerOfTheMaelstrom:Up() then
		return ChainLightning
	end
	if LavaBeam:Usable() and Stormkeeper:Down() and Player.enemies >= (MasterOfTheElements:Up() and 4 or 5) and AscendanceFlame:Remains() > LavaBeam:CastTime() then
		return LavaBeam
	end
	if DeeplyRootedElements.known and LavaBurst:Usable() then
		return LavaBurst
	end
	if LavaBeam:Usable() and AscendanceFlame:Remains() > LavaBeam:CastTime() then
		return LavaBeam
	end
	if ChainLightning:Usable() then
		return ChainLightning
	end
	if Player.moving then
		if FlameShock:Usable() then
			return FlameShock
		end
		if FrostShock:Usable() then
			return FrostShock
		end
	end
end

APL[SPEC.ELEMENTAL].st_cds = function(self)
--[[
actions.single_target=fire_elemental,if=!buff.fire_elemental.up
actions.single_target+=/storm_elemental,if=!buff.storm_elemental.up
actions.single_target+=/stormkeeper,if=!buff.ascendance.up&!buff.stormkeeper.up
actions.single_target+=/totemic_recall,if=cooldown.liquid_magma_totem.remains>15&spell_targets.chain_lightning>1&talent.fire_elemental.enabled
actions.single_target+=/liquid_magma_totem,if=!buff.ascendance.up&(talent.fire_elemental.enabled|spell_targets.chain_lightning>1)
actions.single_target+=/primordial_wave,target_if=min:dot.flame_shock.remains
actions.single_target+=/ancestral_swiftness
]]
	if FireElemental:Usable() and FireElemental:Down() then
		return UseCooldown(FireElemental)
	end
	if StormElemental:Usable() and StormElemental:Down() then
		return UseCooldown(StormElemental)
	end
	if Stormkeeper:Usable() and AscendanceFlame:Down() and Stormkeeper:Down() then
		return UseCooldown(Stormkeeper)
	end
	if FireElemental.known and TotemicRecall:Usable() and Player.enemies > 1 and not LiquidMagmaTotem:Ready(15) then
		return UseCooldown(TotemicRecall)
	end
	if LiquidMagmaTotem:Usable() and AscendanceFlame:Down() and (FireElemental.known or Player.enemies > 1) then
		return UseCooldown(LiquidMagmaTotem)
	end
	if PrimordialWave:Usable() then
		return UseCooldown(PrimordialWave)
	end
	if AncestralSwiftness:Usable() then
		return UseCooldown(AncestralSwiftness)
	end
end

APL[SPEC.ELEMENTAL].single_target = function(self)
--[[
actions.single_target+=/flame_shock,target_if=min:dot.flame_shock.remains,if=active_enemies=1&(dot.flame_shock.remains<2|active_dot.flame_shock=0)&(dot.flame_shock.remains<cooldown.primordial_wave.remains|!talent.primordial_wave.enabled)&(dot.flame_shock.remains<cooldown.liquid_magma_totem.remains|!talent.liquid_magma_totem.enabled)&!buff.surge_of_power.up&talent.fire_elemental.enabled
actions.single_target+=/flame_shock,target_if=min:dot.flame_shock.remains,if=active_dot.flame_shock<active_enemies&spell_targets.chain_lightning>1&(talent.deeply_rooted_elements.enabled|talent.ascendance.enabled|talent.primordial_wave.enabled|talent.searing_flames.enabled|talent.magma_chamber.enabled)&(!buff.surge_of_power.up&buff.stormkeeper.up|!talent.surge_of_power.enabled|cooldown.ascendance.remains=0)
actions.single_target+=/flame_shock,target_if=min:dot.flame_shock.remains,if=spell_targets.chain_lightning>1&(talent.deeply_rooted_elements.enabled|talent.ascendance.enabled|talent.primordial_wave.enabled|talent.searing_flames.enabled|talent.magma_chamber.enabled)&(buff.surge_of_power.up&!buff.stormkeeper.up|!talent.surge_of_power.enabled)&dot.flame_shock.remains<6,cycle_targets=1
actions.single_target+=/tempest
actions.single_target+=/lightning_bolt,if=buff.stormkeeper.up&buff.surge_of_power.up
actions.single_target+=/lava_burst,target_if=dot.flame_shock.remains>2,if=buff.stormkeeper.up&!buff.master_of_the_elements.up&!talent.surge_of_power.enabled&talent.master_of_the_elements.enabled
actions.single_target+=/lightning_bolt,if=buff.stormkeeper.up&!talent.surge_of_power.enabled&(buff.master_of_the_elements.up|!talent.master_of_the_elements.enabled)
actions.single_target+=/lightning_bolt,if=buff.surge_of_power.up&!buff.ascendance.up&talent.echo_chamber.enabled
actions.single_target+=/ascendance,if=cooldown.lava_burst.charges_fractional<1.0
actions.single_target+=/lava_burst,if=cooldown_react&buff.lava_surge.up&talent.fire_elemental.enabled
actions.single_target+=/lava_burst,target_if=dot.flame_shock.remains>2,if=buff.primordial_wave.up
actions.single_target+=/earthquake,if=buff.master_of_the_elements.up&(buff.echoes_of_great_sundering_es.up|buff.echoes_of_great_sundering_eb.up|spell_targets.chain_lightning>1&!talent.echoes_of_great_sundering.enabled&!talent.elemental_blast.enabled)&(buff.fusion_of_elements_nature.up|maelstrom>variable.mael_cap-15|buff.ascendance.remains>9|!buff.ascendance.up)&talent.fire_elemental.enabled
actions.single_target+=/elemental_blast,if=buff.master_of_the_elements.up&(buff.fusion_of_elements_nature.up|buff.fusion_of_elements_fire.up|maelstrom>variable.mael_cap-15|buff.ascendance.remains>6|!buff.ascendance.up)&talent.fire_elemental.enabled
actions.single_target+=/earth_shock,if=buff.master_of_the_elements.up&(buff.fusion_of_elements_nature.up|maelstrom>variable.mael_cap-15|buff.ascendance.remains>9|!buff.ascendance.up)&talent.fire_elemental.enabled
actions.single_target+=/earthquake,if=(buff.echoes_of_great_sundering_es.up|buff.echoes_of_great_sundering_eb.up|spell_targets.chain_lightning>1&!talent.echoes_of_great_sundering.enabled&!talent.elemental_blast.enabled)&(buff.master_of_the_elements.up&cooldown.stormkeeper.remains>10|maelstrom>variable.mael_cap-15|buff.stormkeeper.up)&talent.storm_elemental.enabled
actions.single_target+=/elemental_blast,target_if=min:debuff.lightning_rod.remains,if=(buff.master_of_the_elements.up&cooldown.stormkeeper.remains>10|maelstrom>variable.mael_cap-15|buff.stormkeeper.up)&talent.storm_elemental.enabled
actions.single_target+=/earth_shock,target_if=min:debuff.lightning_rod.remains,if=(buff.master_of_the_elements.up&cooldown.stormkeeper.remains>10|maelstrom>variable.mael_cap-15|buff.stormkeeper.up)&talent.storm_elemental.enabled
actions.single_target+=/icefury,if=!(buff.fusion_of_elements_nature.up|buff.fusion_of_elements_fire.up)&buff.icefury.stack=2&(talent.fusion_of_elements.enabled|!buff.ascendance.up)
actions.single_target+=/lava_burst,target_if=dot.flame_shock.remains>2,if=buff.ascendance.up
actions.single_target+=/lava_burst,target_if=dot.flame_shock.remains>2,if=talent.master_of_the_elements.enabled&!buff.master_of_the_elements.up&talent.fire_elemental.enabled
actions.single_target+=/lava_burst,target_if=dot.flame_shock.remains>2,if=buff.stormkeeper.up&(buff.lava_surge.up|time<10)
actions.single_target+=/earthquake,target_if=max:debuff.lightning_rod.remains,if=(buff.echoes_of_great_sundering_es.up|buff.echoes_of_great_sundering_eb.up|spell_targets.chain_lightning>1&!talent.echoes_of_great_sundering.enabled&!talent.elemental_blast.enabled)&(maelstrom>variable.mael_cap-15|debuff.lightning_rod.remains<gcd|fight_remains<5)
actions.single_target+=/elemental_blast,target_if=max:debuff.lightning_rod.remains,if=maelstrom>variable.mael_cap-15|debuff.lightning_rod.remains<gcd|fight_remains<5
actions.single_target+=/earth_shock,target_if=max:debuff.lightning_rod.remains,if=maelstrom>variable.mael_cap-15|debuff.lightning_rod.remains<gcd|fight_remains<5
actions.single_target+=/lightning_bolt,if=buff.surge_of_power.up
actions.single_target+=/icefury,if=!(buff.fusion_of_elements_nature.up|buff.fusion_of_elements_fire.up)
actions.single_target+=/frost_shock,if=buff.icefury_dmg.up&(spell_targets.chain_lightning=1|buff.stormkeeper.up)&talent.surge_of_power.enabled
actions.single_target+=/chain_lightning,if=buff.power_of_the_maelstrom.up&spell_targets.chain_lightning>1&!buff.stormkeeper.up
actions.single_target+=/lightning_bolt,if=buff.power_of_the_maelstrom.up&!buff.stormkeeper.up
actions.single_target+=/lava_burst,target_if=dot.flame_shock.remains>2,if=talent.deeply_rooted_elements.enabled
actions.single_target+=/chain_lightning,if=spell_targets.chain_lightning>1
actions.single_target+=/lightning_bolt
actions.single_target+=/flame_shock,moving=1,target_if=refreshable
actions.single_target+=/flame_shock,moving=1,if=movement.distance>6
actions.single_target+=/frost_shock,moving=1
]]
	if self.use_cds then
		self:st_cds()
	end
	if FireElemental.known and FlameShock:Usable() and (
		(not self.use_cds and FlameShock:Down()) or
		(Player.enemies == 1 and SurgeOfPower:Down() and (FlameShock:Remains() < 2 or FlameShock:Ticking() == 0) and (not PrimordialWave.known or FlameShock:Remains() < PrimordialWave:Cooldown()) and (not LiquidMagmaTotem.known or FlameShock:Remains() < LiquidMagmaTotem:Cooldown())) or
		(Player.enemies > 1 and (DeeplyRootedElements.known or AscendanceFlame.known or PrimordialWave.known or SearingFlames.known or MagmaChamber.known) and (
			(FlameShock:Ticking() < Player.enemies and (not SurgeOfPower.known or AscendanceFlame:Ready() or (SurgeOfPower:Down() and Stormkeeper:Up()))) or
			(FlameShock:Remains() < 6 and (not SurgeOfPower.known or (SurgeOfPower:Up() and Stormkeeper:Down())))
		))
	) then
		return FlameShock
	end
	if Tempest:Usable() then
		return Tempest
	end
	if LightningBolt:Usable() and Stormkeeper:Up() and SurgeOfPower:Up() then
		return LightningBolt
	end
	if MasterOfTheElements.known and not SurgeOfPower.known and LavaBurst:Usable() and Stormkeeper:Up() and MasterOfTheElements:Down() then
		return LavaBurst
	end
	if LightningBolt:Usable() and (
		(not SurgeOfPower.known and Stormkeeper:Up() and (not MasterOfTheElements.known or MasterOfTheElements:Up())) or
		(EchoChamber.known and LightningBolt:Usable() and SurgeOfPower:Up() and AscendanceFlame:Down())
	) then
		return LightningBolt
	end
	if self.use_cds and AscendanceFlame:Usable() and AscendanceFlame:Down() and LavaBurst:ChargesFractional() < 1.0 then
		UseCooldown(AscendanceFlame)
	end
	if LavaBurst:Usable() and (
		(FireElemental.known and LavaSurge:Up()) or
		PrimordialWave.buff:Up()
	) then
		return LavaBurst
	end
	if FireElemental.known then
		if Earthquake:Usable() and MasterOfTheElements:Up() and (FusionOfElements.nature:Up() or Player.maelstrom.deficit < 15 or AscendanceFlame:Remains() > 9 or AscendanceFlame:Down()) and (
			(Player.enemies > 1 and not EchoesOfGreatSundering.known and not ElementalBlast.known) or
			(EchoesOfGreatSundering.known and EchoesOfGreatSundering:Up())
		) then
			return Earthquake
		end
		if ElementalBlast:Usable() and MasterOfTheElements:Up() and (FusionOfElements.nature:Up() or FusionOfElements.fire:Up() or Player.maelstrom.deficit < 15 or AscendanceFlame:Remains() > 6 or AscendanceFlame:Down()) then
			return ElementalBlast
		end
		if EarthShock:Usable() and MasterOfTheElements:Up() and (FusionOfElements.nature:Up() or Player.maelstrom.deficit < 15 or AscendanceFlame:Remains() > 9 or AscendanceFlame:Down()) then
			return EarthShock
		end
	end
	if StormElemental.known then
		if Earthquake:Usable() and (Player.maelstrom.deficit < 15 or Stormkeeper:Up() or (MasterOfTheElements:Up() and not Stormkeeper:Ready(10))) and (
			(Player.enemies > 1 and not EchoesOfGreatSundering.known and not ElementalBlast.known) or
			(EchoesOfGreatSundering.known and EchoesOfGreatSundering:Up())
		) then
			return Earthquake
		end
		if ElementalBlast:Usable() and (Player.maelstrom.deficit < 15 or Stormkeeper:Up() or (MasterOfTheElements:Up() and not Stormkeeper:Ready(10))) then
			return ElementalBlast
		end
		if EarthShock:Usable() and (Player.maelstrom.deficit < 15 or Stormkeeper:Up() or (MasterOfTheElements:Up() and not Stormkeeper:Ready(10))) then
			return EarthShock
		end
	end
	if Icefury:Usable() and not (FusionOfElements.nature:Up() or FusionOfElements.fire:Up()) and Icefury:Stack() >= 2 and (FusionOfElements.known or AscendanceFlame:Down()) then
		return Icefury
	end
	if LavaBurst:Usable() and (
		AscendanceFlame:Up() or
		(FireElemental.known and MasterOfTheElements.known and MasterOfTheElements:Down()) or
		(Stormkeeper:Up() and (LavaSurge:Up() or Player:TimeInCombat() < 10))
	) then
		return LavaBurst
	end
	if Earthquake:Usable() and (Player.maelstrom.deficit < 15 or LightningRod:Remains() < Player.gcd or Target.timeToDie < 5) and (
		(Player.enemies > 1 and not EchoesOfGreatSundering.known and not ElementalBlast.known) or
		(EchoesOfGreatSundering.known and EchoesOfGreatSundering:Up())
	) then
		return Earthquake
	end
	if ElementalBlast:Usable() and (Player.maelstrom.deficit < 15 or LightningRod:Remains() < Player.gcd or Target.timeToDie < 5) then
		return ElementalBlast
	end
	if EarthShock:Usable() and (Player.maelstrom.deficit < 15 or LightningRod:Remains() < Player.gcd or Target.timeToDie < 5) then
		return EarthShock
	end
	if SurgeOfPower.known and LightningBolt:Usable() and SurgeOfPower:Up() then
		return LightningBolt
	end
	if Icefury:Usable() and not (FusionOfElements.nature:Up() or FusionOfElements.fire:Up()) then
		return Icefury
	end
	if SurgeOfPower.known and FrostShock:Usable() and Icefury.damage:Up() and (Player.enemies == 1 or Stormkeeper:Up()) then
		return FrostShock
	end
	if ChainLightning:Usable() and Player.enemies > 1 and PowerOfTheMaelstrom:Up() and Stormkeeper:Down() then
		return ChainLightning
	end
	if LightningBolt:Usable() and PowerOfTheMaelstrom:Up() and Stormkeeper:Down() then
		return LightningBolt
	end
	if DeeplyRootedElements.known and LavaBurst:Usable() then
		return LavaBurst
	end
	if ChainLightning:Usable() and Player.enemies > 1 then
		return ChainLightning
	end
	if LightningBolt:Usable() then
		return LightningBolt
	end
	if Player.moving then
		if FlameShock:Usable() then
			return FlameShock
		end
		if FrostShock:Usable() then
			return FrostShock
		end
	end
end

APL[SPEC.ENHANCEMENT].Main = function(self)
	self.cds_active = (AscendanceAir.known and AscendanceAir:Up()) or (FeralSpirit.known and FeralSpirit:Up()) or (DoomWinds.known and DoomWinds:Up())
	self.use_cds = Opt.cooldown and (self.cds_active or Target.boss or Target.player or (not Opt.boss_only and Target.timeToDie > Opt.cd_ttd))
	if Player.health.pct < Opt.heal and MaelstromWeapon.current >= 5 and HealingSurge:Usable() then
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
actions.precombat+=/snapshot_stats
]]
		if Skyfury:Usable() and Skyfury:Remains() < 300 then
			UseCooldown(Skyfury)
		elseif WindfuryWeapon:Usable() and WindfuryWeapon:Remains() < 300 then
			UseCooldown(WindfuryWeapon)
		elseif FlametongueWeapon:Usable() and FlametongueWeapon:Remains() < 300 then
			UseCooldown(FlametongueWeapon)
		elseif Opt.shield and LightningShield:Usable() and LightningShield:Remains() < 300 then
			UseCooldown(LightningShield)
		elseif Opt.shield and ElementalOrbit.known and EarthShield:Usable() and (EarthShield:Remains() < 150 or EarthShield:Stack() <= 3) then
			UseCooldown(EarthShield)
		end
		if Opt.earth and self.use_cds and EarthElemental:Usable() and not PrimalElementalist.known then
			UseExtra(EarthElemental)
		end
	else
		if Skyfury:Usable() and Skyfury:Down() then
			UseExtra(Skyfury)
		elseif WindfuryWeapon:Usable() and WindfuryWeapon:Down() then
			UseExtra(WindfuryWeapon)
		elseif FlametongueWeapon:Usable() and FlametongueWeapon:Down() then
			UseExtra(FlametongueWeapon)
		elseif Opt.shield and LightningShield:Usable() and LightningShield:Down() then
			UseExtra(LightningShield)
		elseif Opt.shield and ElementalOrbit.known and EarthShield:Usable() and EarthShield:Down() then
			UseExtra(EarthShield)
		end
	end
--[[
actions=bloodlust,line_cd=600
actions+=/potion,if=(buff.ascendance.up|buff.feral_spirit.up|buff.doom_winds.up|(fight_remains%%300<=30)|(!talent.ascendance.enabled&!talent.feral_spirit.enabled&!talent.doom_winds.enabled))
actions+=/auto_attack
actions+=/call_action_list,name=cds
actions+=/run_action_list,name=single,if=active_enemies=1
actions+=/run_action_list,name=aoe,if=active_enemies>1&(rotation.standard|rotation.simple)
actions+=/run_action_list,name=funnel,if=active_enemies>1&rotation.funnel
]]
	if self.use_cds then
		self:cds()
	end
	if Player.enemies == 1 then
		return self:single()
	elseif Opt.funnel then
		return self:funnel()
	else
		return self:aoe()
	end
end

APL[SPEC.ENHANCEMENT].precombat_variables = function(self)
--[[
actions.precombat+=/variable,name=trinket1_is_weird,value=trinket.1.is.algethar_puzzle_box|trinket.1.is.manic_grieftorch|trinket.1.is.elementium_pocket_anvil|trinket.1.is.beacon_to_the_beyond
actions.precombat+=/variable,name=trinket2_is_weird,value=trinket.2.is.algethar_puzzle_box|trinket.2.is.manic_grieftorch|trinket.2.is.elementium_pocket_anvil|trinket.2.is.beacon_to_the_beyond
actions.precombat+=/variable,name=min_talented_cd_remains,value=((cooldown.feral_spirit.remains%(4*talent.witch_doctors_ancestry.enabled))+1000*!talent.feral_spirit.enabled)>?(cooldown.doom_winds.remains+1000*!talent.doom_winds.enabled)>?(cooldown.ascendance.remains+1000*!talent.ascendance.enabled)
actions.precombat+=/variable,name=target_nature_mod,value=(1+debuff.chaos_brand.up*debuff.chaos_brand.value)*(1+(debuff.hunters_mark.up*target.health.pct>=80)*debuff.hunters_mark.value)
actions.precombat+=/variable,name=expected_lb_funnel,value=action.lightning_bolt.damage*(1+debuff.lightning_rod.up*variable.target_nature_mod*(1+buff.primordial_wave.up*active_dot.flame_shock*buff.primordial_wave.value)*debuff.lightning_rod.value)
actions.precombat+=/variable,name=expected_cl_funnel,value=action.chain_lightning.damage*(1+debuff.lightning_rod.up*variable.target_nature_mod*(active_enemies>?(3+2*talent.crashing_storms.enabled))*debuff.lightning_rod.value)
]]
	self.minTalentedCdRemains = min(FeralSpirit.known and (FeralSpirit:Cooldown() / (WitchDoctorsAncestry.known and 4 or 1)) or 1000, DoomWinds.known and DoomWinds:Cooldown() or 1000, AscendanceAir.known and AscendanceAir:Cooldown() or 1000)
	self.targetNatureMod = (1 + (ChaosBrand:Up() and ChaosBrand.value or 0)) * (1 + (HuntersMark:Up() and Target.health.pct >= 80 and HuntersMark.value or 0))
	self.expectedLbFunnel = LightningBolt:Damage() * (1 + (LightningRod:Up() and (self.targetNatureMod * (1 + PrimordialWave.buff:Up() * FlameShock:Ticking() * PrimordialWave.buff.value) * LightningRod.value) or 0))
	self.expectedClFunnel = ChainLightning:Damage() * (1 + (LightningRod:Up() and (self.targetNatureMod * ChainLightning:Targets() * LightningRod.value) or 0))
end

APL[SPEC.ENHANCEMENT].cds = function(self)
--[[
actions.cds=/use_item,name=elementium_pocket_anvil,use_off_gcd=1
actions.cds+=/use_item,name=algethar_puzzle_box,use_off_gcd=1,if=(!buff.ascendance.up&!buff.feral_spirit.up&!buff.doom_winds.up)|(talent.ascendance.enabled&(cooldown.ascendance.remains<2*action.stormstrike.gcd))|(fight_remains%%180<=30)
actions.cds+=/use_item,slot=trinket1,if=!variable.trinket1_is_weird&trinket.1.has_use_buff&(buff.ascendance.up|buff.feral_spirit.up|buff.doom_winds.up|(fight_remains%%trinket.1.cooldown.duration<=trinket.1.buff.any.duration)|(variable.min_talented_cd_remains>=trinket.1.cooldown.duration)|(!talent.ascendance.enabled&!talent.feral_spirit.enabled&!talent.doom_winds.enabled))
actions.cds+=/use_item,slot=trinket2,if=!variable.trinket2_is_weird&trinket.2.has_use_buff&(buff.ascendance.up|buff.feral_spirit.up|buff.doom_winds.up|(fight_remains%%trinket.2.cooldown.duration<=trinket.2.buff.any.duration)|(variable.min_talented_cd_remains>=trinket.2.cooldown.duration)|(!talent.ascendance.enabled&!talent.feral_spirit.enabled&!talent.doom_winds.enabled))
actions.cds+=/use_item,name=beacon_to_the_beyond,use_off_gcd=1,if=(!buff.ascendance.up&!buff.feral_spirit.up&!buff.doom_winds.up)|(fight_remains%%150<=5)
actions.cds+=/use_item,name=manic_grieftorch,use_off_gcd=1,if=(!buff.ascendance.up&!buff.feral_spirit.up&!buff.doom_winds.up)|(fight_remains%%120<=5)
actions.cds+=/use_item,slot=trinket1,if=!variable.trinket1_is_weird&!trinket.1.has_use_buff
actions.cds+=/use_item,slot=trinket2,if=!variable.trinket2_is_weird&!trinket.2.has_use_buff
actions.cds+=/blood_fury,if=(buff.ascendance.up|buff.feral_spirit.up|buff.doom_winds.up|(fight_remains%%action.blood_fury.cooldown<=action.blood_fury.duration)|(variable.min_talented_cd_remains>=action.blood_fury.cooldown)|(!talent.ascendance.enabled&!talent.feral_spirit.enabled&!talent.doom_winds.enabled))
actions.cds+=/berserking,if=(buff.ascendance.up|buff.feral_spirit.up|buff.doom_winds.up|(fight_remains%%action.berserking.cooldown<=action.berserking.duration)|(variable.min_talented_cd_remains>=action.berserking.cooldown)|(!talent.ascendance.enabled&!talent.feral_spirit.enabled&!talent.doom_winds.enabled))
actions.cds+=/fireblood,if=(buff.ascendance.up|buff.feral_spirit.up|buff.doom_winds.up|(fight_remains%%action.fireblood.cooldown<=action.fireblood.duration)|(variable.min_talented_cd_remains>=action.fireblood.cooldown)|(!talent.ascendance.enabled&!talent.feral_spirit.enabled&!talent.doom_winds.enabled))
actions.cds+=/ancestral_call,if=(buff.ascendance.up|buff.feral_spirit.up|buff.doom_winds.up|(fight_remains%%action.ancestral_call.cooldown<=action.ancestral_call.duration)|(variable.min_talented_cd_remains>=action.ancestral_call.cooldown)|(!talent.ascendance.enabled&!talent.feral_spirit.enabled&!talent.doom_winds.enabled))
actions.cds+=/invoke_external_buff,name=power_infusion,if=(buff.ascendance.up|buff.feral_spirit.up|buff.doom_winds.up|(fight_remains%%120<=20)|(variable.min_talented_cd_remains>=120)|(!talent.ascendance.enabled&!talent.feral_spirit.enabled&!talent.doom_winds.enabled))
actions.cds+=/primordial_wave,if=set_bonus.tier31_2pc&(raid_event.adds.in>(action.primordial_wave.cooldown%(1+set_bonus.tier31_4pc))|raid_event.adds.in<6)
actions.cds+=/feral_spirit,if=talent.elemental_spirits.enabled|(talent.alpha_wolf.enabled&active_enemies>1)
actions.cds+=/surging_totem
actions.cds+=/ascendance,if=dot.flame_shock.ticking&((ti_lightning_bolt&active_enemies=1&raid_event.adds.in>=action.ascendance.cooldown%2)|(ti_chain_lightning&active_enemies>1))
]]
	if Opt.trinket and (self.cds_active or (not AscendanceAir.known and not FeralSpirit.known and not DoomWinds.known)) then
		if Trinket1:Usable() then
			return UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			return UseCooldown(Trinket2)
		end
	end
	if PrimordialWave:Usable() and Player.set_bonus.t31 >= 2 then
		return UseCooldown(PrimordialWave)
	end
	if FeralSpirit:Usable() and (ElementalSpirits.known or (AlphaWolf.known and Player.enemies > 1)) then
		return UseCooldown(FeralSpirit)
	end
	if SurgingTotem:Usable() then
		return UseCooldown(SurgingTotem)
	end
	if AscendanceAir:Usable() and AscendanceAir:Down() and FlameShock:Up() and (
		not ThorimsInvocation.known or
		(ThorimsInvocation:LightningBolt() and Player.enemies == 1) or
		(ThorimsInvocation:ChainLightning() and Player.enemies > 1)
	) then
		return UseCooldown(AscendanceAir)
	end
end


APL[SPEC.ENHANCEMENT].aoe = function(self)
--[[
actions.aoe=tempest,target_if=min:debuff.lightning_rod.remains,if=buff.maelstrom_weapon.stack=buff.maelstrom_weapon.max_stack|(buff.maelstrom_weapon.stack>=5&(tempest_mael_count>30|buff.awakening_storms.stack=2))
actions.aoe+=/windstrike,target_if=min:debuff.lightning_rod.remains,if=talent.thorims_invocation.enabled&buff.maelstrom_weapon.stack>1&ti_chain_lightning
actions.aoe+=/crash_lightning,if=talent.crashing_storms.enabled&((talent.unruly_winds.enabled&active_enemies>=10)|active_enemies>=15)
actions.aoe+=/lightning_bolt,target_if=min:debuff.lightning_rod.remains,if=(!talent.tempest.enabled|(tempest_mael_count<=10&buff.awakening_storms.stack<=1))&((active_dot.flame_shock=active_enemies|active_dot.flame_shock=6)&buff.primordial_wave.up&buff.maelstrom_weapon.stack=buff.maelstrom_weapon.max_stack&(!buff.splintered_elements.up|fight_remains<=12|raid_event.adds.remains<=gcd))
actions.aoe+=/lava_lash,if=talent.molten_assault.enabled&(talent.primordial_wave.enabled|talent.fire_nova.enabled)&dot.flame_shock.ticking&(active_dot.flame_shock<active_enemies)&active_dot.flame_shock<6
actions.aoe+=/primordial_wave,target_if=min:dot.flame_shock.remains,if=!buff.primordial_wave.up
actions.aoe+=/chain_lightning,target_if=min:debuff.lightning_rod.remains,if=buff.arc_discharge.up&buff.maelstrom_weapon.stack>=5
actions.aoe+=/elemental_blast,target_if=min:debuff.lightning_rod.remains,if=(!talent.elemental_spirits.enabled|(talent.elemental_spirits.enabled&(charges=max_charges|feral_spirit.active>=2)))&buff.maelstrom_weapon.stack=buff.maelstrom_weapon.max_stack&(!talent.crashing_storms.enabled|active_enemies<=3)
actions.aoe+=/chain_lightning,target_if=min:debuff.lightning_rod.remains,if=buff.maelstrom_weapon.stack=buff.maelstrom_weapon.max_stack
actions.aoe+=/feral_spirit
actions.aoe+=/doom_winds
actions.aoe+=/crash_lightning,if=buff.doom_winds.up|!buff.crash_lightning.up|(talent.alpha_wolf.enabled&feral_spirit.active&alpha_wolf_min_remains=0)
actions.aoe+=/sundering,if=buff.doom_winds.up|set_bonus.tier30_2pc|talent.earthsurge.enabled
actions.aoe+=/fire_nova,if=active_dot.flame_shock=6|(active_dot.flame_shock>=4&active_dot.flame_shock=active_enemies)
actions.aoe+=/lava_lash,target_if=min:debuff.lashing_flames.remains,if=talent.lashing_flames.enabled
actions.aoe+=/lava_lash,if=talent.molten_assault.enabled&dot.flame_shock.ticking
actions.aoe+=/ice_strike,if=talent.hailstorm.enabled&!buff.ice_strike.up
actions.aoe+=/frost_shock,if=talent.hailstorm.enabled&buff.hailstorm.up
actions.aoe+=/sundering
actions.aoe+=/flame_shock,if=talent.molten_assault.enabled&!ticking
actions.aoe+=/flame_shock,target_if=min:dot.flame_shock.remains,if=(talent.fire_nova.enabled|talent.primordial_wave.enabled)&(active_dot.flame_shock<active_enemies)&active_dot.flame_shock<6
actions.aoe+=/fire_nova,if=active_dot.flame_shock>=3
actions.aoe+=/stormstrike,if=buff.crash_lightning.up&(talent.deeply_rooted_elements.enabled|buff.converging_storms.stack=buff.converging_storms.max_stack)
actions.aoe+=/crash_lightning,if=talent.crashing_storms.enabled&buff.cl_crash_lightning.up&active_enemies>=4
actions.aoe+=/windstrike
actions.aoe+=/stormstrike
actions.aoe+=/ice_strike
actions.aoe+=/lava_lash
actions.aoe+=/crash_lightning
actions.aoe+=/fire_nova,if=active_dot.flame_shock>=2
actions.aoe+=/elemental_blast,target_if=min:debuff.lightning_rod.remains,if=(!talent.elemental_spirits.enabled|(talent.elemental_spirits.enabled&(charges=max_charges|feral_spirit.active>=2)))&buff.maelstrom_weapon.stack>=5&(!talent.crashing_storms.enabled|active_enemies<=3)
actions.aoe+=/chain_lightning,target_if=min:debuff.lightning_rod.remains,if=buff.maelstrom_weapon.stack>=5
actions.aoe+=/flame_shock,if=!ticking
actions.aoe+=/frost_shock,if=!talent.hailstorm.enabled
]]
	if Tempest:Usable() and (
		MaelstromWeapon.deficit == 0 or
		(MaelstromWeapon.current >= 5 and (Tempest:Maelstrom() > 30 or AwakeningStorms:Stack() >= 2 or Tempest.buff:Remains() < 4))
	) then
		return Tempest
	end
	if ThorimsInvocation.known and Windstrike:Usable() and MaelstromWeapon.current > 1 and ThorimsInvocation:ChainLightning() then
		return Windstrike
	end
	if CrashingStorms.known and CrashLightning:Usable() and Player.enemies >= (UnrulyWinds.known and 10 or 15) then
		return CrashLightning
	end
	if LightningBolt:Usable() and MaelstromWeapon.deficit == 0 and (not Tempest.known or (Tempest:Maelstrom() <= 10 and AwakeningStorms:Stack() <= 1)) and (FlameShock:Ticking() >= min(6, Player.enemies) and PrimordialWave.buff:Up() and (SplinteredElements:Down() or Target.timeToDie <= 12)) then
		return LightningBolt
	end
	if MoltenAssault.known and LavaLash:Usable() and (PrimordialWave.known or FireNova.known) and FlameShock:Up() and FlameShock:Ticking() < min(6, Player.enemies) then
		return LavaLash
	end
	if self.use_cds and PrimordialWave:Usable() and PrimordialWave.buff:Down() then
		UseCooldown(PrimordialWave)
	end
	if ArcDischarge.known and ChainLightning:Usable() and MaelstromWeapon.current >= 5 and ArcDischarge:Up() then
		return ChainLightning
	end
	if ElementalBlast:Usable() and MaelstromWeapon.deficit == 0 and (not CrashingStorms.known or Player.enemies <= 3) and (
		not ElementalSpirits.known or
		ElementalBlast:Charges() >= ElementalBlast:MaxCharges() or
		Pet.ElementalSpiritWolf:Count() >= 2
	) then
		return ElementalBlast
	end
	if ChainLightning:Usable() and MaelstromWeapon.deficit == 0 then
		return ChainLightning
	end
	if self.use_cds then
		if FeralSpirit:Usable() then
			UseCooldown(FeralSpirit)
		end
		if DoomWinds:Usable() then
			UseCooldown(DoomWinds)
		end
	end
	if CrashLightning:Usable() and (
		CrashLightning.buff:Down() or
		(DoomWinds.known and DoomWinds:Up()) or
		(AlphaWolf.known and Pet.SpiritWolf:Up() and AlphaWolf:MinRemains() == 0)
	) then
		return CrashLightning
	end
	if self.use_cds and Sundering:Usable() and (
		DoomWinds:Up() or
		Player.set_bonus.t30 >= 2 or
		Earthsurge.known
	) then
		UseCooldown(Sundering)
	end
	if FireNova:Usable() and FlameShock:Ticking() >= clamp(Player.enemies, 4, 6) then
		return FireNova
	end
	if LavaLash:Usable() and FlameShock:Up() and (
		(MoltenAssault.known and (FlameShock:Ticking() < min(6, Player.enemies) or FlameShock:LowestRemains() < 6)) or
		(LashingFlames.known and LashingFlames:Remains() < 2)
	) then
		return LavaLash
	end
	if Hailstorm.known then
		if IceStrike:Usable() and IceStrike.buff:Down() then
			return IceStrike
		end
		if FrostShock:Usable() and (Hailstorm:Stack() >= 8 or IceStrike.buff:Up()) then
			return FrostShock
		end
	end
	if self.use_cds and Sundering:Usable() then
		UseCooldown(Sundering)
	end
	if FlameShock:Usable() and (
		(MoltenAssault.known and FlameShock:Usable() and FlameShock:Down()) or
		((FireNova.known or PrimordialWave.known) and FlameShock:Refreshable() and FlameShock:Ticking() < min(Player.enemies, 6) and Target.timeToDie > (FlameShock:Remains() + 6))
	) then
		return FlameShock
	end
	if FireNova:Usable() and FlameShock:Ticking() >= 3 then
		return FireNova
	end
	if Hailstorm.known and FrostShock:Usable() and Hailstorm:Stack() >= clamp(Player.enemies - 1, 2, 5) then
		return FrostShock
	end
	if Stormstrike:Usable() and CrashLightning.buff:Up() and (
		DeeplyRootedElements.known or
		(ConvergingStorms and ConvergingStorms:Stack() >= ConvergingStorms:MaxStack())
	) then
		return Stormstrike
	end
	if CrashingStorms.known and CrashLightning:Usable() and ClCrashLightning:Up() and Player.enemies >= 4 then
		return CrashLightning
	end
	if Windstrike:Usable() then
		return Windstrike
	end
	if Stormstrike:Usable() then
		return Stormstrike
	end
	if IceStrike:Usable() then
		return IceStrike
	end
	if LavaLash:Usable() then
		return LavaLash
	end
	if CrashLightning:Usable() then
		return CrashLightning
	end
	if FireNova:Usable() and FlameShock:Ticking() >= 2 then
		return FireNova
	end
	if MaelstromWeapon.current >= 5 then
		if ElementalBlast:Usable() and (not CrashingStorms.known or Player.enemies <= 3) and (
			not ElementalSpirits.known or
			ElementalBlast:Charges() >= ElementalBlast:MaxCharges() or
			Pet.ElementalSpiritWolf:Count() >= 2
		) then
			return ElementalBlast
		end
		if ChainLightning:Usable() then
			return ChainLightning
		end
	end
	if FlameShock:Usable() and FlameShock:Down() then
		return FlameShock
	end
	if not Hailstorm.known and FrostShock:Usable() then
		return FrostShock
	end
end

APL[SPEC.ENHANCEMENT].funnel = function(self)
--[[
actions.funnel=ascendance
actions.funnel+=/windstrike,if=(talent.thorims_invocation.enabled&buff.maelstrom_weapon.stack>1)|buff.converging_storms.stack=buff.converging_storms.max_stack
actions.funnel+=/tempest,if=buff.maelstrom_weapon.stack=buff.maelstrom_weapon.max_stack|(buff.maelstrom_weapon.stack>=5&(tempest_mael_count>30|buff.awakening_storms.stack=2))
actions.funnel+=/lightning_bolt,if=(active_dot.flame_shock=active_enemies|active_dot.flame_shock=6)&buff.primordial_wave.up&buff.maelstrom_weapon.stack=buff.maelstrom_weapon.max_stack&(!buff.splintered_elements.up|fight_remains<=12|raid_event.adds.remains<=gcd)
actions.funnel+=/elemental_blast,if=buff.maelstrom_weapon.stack>=5&talent.elemental_spirits.enabled&feral_spirit.active>=4
actions.funnel+=/lightning_bolt,if=talent.supercharge.enabled&buff.maelstrom_weapon.stack=buff.maelstrom_weapon.max_stack&(variable.expected_lb_funnel>variable.expected_cl_funnel)
actions.funnel+=/chain_lightning,if=(talent.supercharge.enabled&buff.maelstrom_weapon.stack=buff.maelstrom_weapon.max_stack)|buff.arc_discharge.up&buff.maelstrom_weapon.stack>=5
actions.funnel+=/lava_lash,if=(talent.molten_assault.enabled&dot.flame_shock.ticking&(active_dot.flame_shock<active_enemies)&active_dot.flame_shock<6)|(talent.ashen_catalyst.enabled&buff.ashen_catalyst.stack=buff.ashen_catalyst.max_stack)
actions.funnel+=/primordial_wave,target_if=min:dot.flame_shock.remains,if=!buff.primordial_wave.up
actions.funnel+=/elemental_blast,if=(!talent.elemental_spirits.enabled|(talent.elemental_spirits.enabled&(charges=max_charges|buff.feral_spirit.up)))&buff.maelstrom_weapon.stack=buff.maelstrom_weapon.max_stack
actions.funnel+=/feral_spirit
actions.funnel+=/doom_winds
actions.funnel+=/stormstrike,if=buff.converging_storms.stack=buff.converging_storms.max_stack
actions.funnel+=/chain_lightning,if=buff.maelstrom_weapon.stack=buff.maelstrom_weapon.max_stack&buff.crackling_thunder.up
actions.funnel+=/lava_burst,if=(buff.molten_weapon.stack+buff.volcanic_strength.up>buff.crackling_surge.stack)&buff.maelstrom_weapon.stack=buff.maelstrom_weapon.max_stack
actions.funnel+=/lightning_bolt,if=buff.maelstrom_weapon.stack=buff.maelstrom_weapon.max_stack&(variable.expected_lb_funnel>variable.expected_cl_funnel)
actions.funnel+=/chain_lightning,if=buff.maelstrom_weapon.stack=buff.maelstrom_weapon.max_stack
actions.funnel+=/crash_lightning,if=buff.doom_winds.up|!buff.crash_lightning.up|(talent.alpha_wolf.enabled&feral_spirit.active&alpha_wolf_min_remains=0)|(talent.converging_storms.enabled&buff.converging_storms.stack<buff.converging_storms.max_stack)
actions.funnel+=/sundering,if=buff.doom_winds.up|set_bonus.tier30_2pc|talent.earthsurge.enabled
actions.funnel+=/fire_nova,if=active_dot.flame_shock=6|(active_dot.flame_shock>=4&active_dot.flame_shock=active_enemies)
actions.funnel+=/ice_strike,if=talent.hailstorm.enabled&!buff.ice_strike.up
actions.funnel+=/frost_shock,if=talent.hailstorm.enabled&buff.hailstorm.up
actions.funnel+=/sundering
actions.funnel+=/flame_shock,if=talent.molten_assault.enabled&!ticking
actions.funnel+=/flame_shock,target_if=min:dot.flame_shock.remains,if=(talent.fire_nova.enabled|talent.primordial_wave.enabled)&(active_dot.flame_shock<active_enemies)&active_dot.flame_shock<6
actions.funnel+=/fire_nova,if=active_dot.flame_shock>=3
actions.funnel+=/stormstrike,if=buff.crash_lightning.up&talent.deeply_rooted_elements.enabled
actions.funnel+=/crash_lightning,if=talent.crashing_storms.enabled&buff.cl_crash_lightning.up&active_enemies>=4
actions.funnel+=/windstrike
actions.funnel+=/stormstrike
actions.funnel+=/ice_strike
actions.funnel+=/lava_lash
actions.funnel+=/crash_lightning
actions.funnel+=/fire_nova,if=active_dot.flame_shock>=2
actions.funnel+=/elemental_blast,if=(!talent.elemental_spirits.enabled|(talent.elemental_spirits.enabled&(charges=max_charges|buff.feral_spirit.up)))&buff.maelstrom_weapon.stack>=5
actions.funnel+=/lava_burst,if=(buff.molten_weapon.stack+buff.volcanic_strength.up>buff.crackling_surge.stack)&buff.maelstrom_weapon.stack>=5
actions.funnel+=/lightning_bolt,if=buff.maelstrom_weapon.stack>=5&(variable.expected_lb_funnel>variable.expected_cl_funnel)
actions.funnel+=/chain_lightning,if=buff.maelstrom_weapon.stack>=5
actions.funnel+=/flame_shock,if=!ticking
actions.funnel+=/frost_shock,if=!talent.hailstorm.enabled
]]
	if self.use_cds and AscendanceAir:Usable() then
		return AscendanceAir
	end
	if Windstrike:Usable() and (
		(ThorimsInvocation.known and MaelstromWeapon.current > 1) or
		(ConvergingStorms.known and ConvergingStorms:Stack() >= ConvergingStorms:MaxStack())
	) then
		return Windstrike
	end
	if Tempest:Usable() and (
		MaelstromWeapon.deficit == 0 or
		(MaelstromWeapon.current >= 5 and (Tempest:Maelstrom() > 30 or AwakeningStorms:Stack() >= 2 or Tempest.buff:Remains() < 4))
	) then
		return Tempest
	end
	if LightningBolt:Usable() and MaelstromWeapon.deficit == 0 and FlameShock:Ticking() >= min(6, Player.enemies) and PrimordialWave.buff:Up() and (SplinteredElements:Down() or Target.timeToDie <= 12) then
		return LightningBolt
	end
	if ElementalSpirits.known and ElementalBlast:Usable() and MaelstromWeapon.current >= 5 and Pet.ElementalSpiritWolf:Count() >= 4 then
		return ElementalBlast
	end
	if Supercharge.known and LightningBolt:Usable() and MaelstromWeapon.deficit == 0 and (self.expectedLbFunnel > self.expectedClFunnel) then
		return LightningBolt
	end
	if ChainLightning:Usable() and (
		(Supercharge.known and MaelstromWeapon.deficit == 0) or
		(ArcDischarge.known and MaelstromWeapon.current >= 5 and ArcDischarge:Up())
	) then
		return ChainLightning
	end
	if LavaLash:Usable() and (
		(MoltenAssault.known and FlameShock:Up() and FlameShock:Ticking() < min(6, Player.enemies)) or
		(AshenCatalyst.known and AshenCatalyst:Stack() >= AshenCatalyst:MaxStack())
	) then
		return LavaLash
	end
	if self.use_cds and PrimordialWave:Usable() and PrimordialWave.buff:Down() then
		UseCooldown(PrimordialWave)
	end
	if ElementalBlast:Usable() and MaelstromWeapon.deficit == 0 and (
		not ElementalSpirits.known or
		ElementalBlast:Charges() >= ElementalBlast:MaxCharges() or
		Pet.ElementalSpiritWolf:Up()
	) then
		return ElementalBlast
	end
	if self.use_cds then
		if FeralSpirit:Usable() then
			UseCooldown(FeralSpirit)
		end
		if DoomWinds:Usable() then
			UseCooldown(DoomWinds)
		end
	end
	if ConvergingStorms.known and Stormstrike:Usable() and ConvergingStorms:Stack() >= ConvergingStorms:MaxStack() then
		return Stormstrike
	end
	if MaelstromWeapon.deficit == 0 then
		if ChainLightning:Usable() and CracklingThunder:Up() then
			return ChainLightning
		end
		if LavaBurst:Usable() and (MoltenWeapon:Stack() + (VolcanicStrength:Up() and 1 or 0)) > CracklingSurge:Stack() then
			return LavaBurst
		end
		if LightningBolt:Usable() and (self.expectedLbFunnel > self.expectedClFunnel) then
			return LightningBolt
		end
		if ChainLightning:Usable() then
			return ChainLightning
		end
	end
	if CrashLightning:Usable() and (
		CrashLightning.buff:Down() or
		(DoomWinds.known and DoomWinds:Up()) or
		(AlphaWolf.known and Pet.SpiritWolf:Up() and AlphaWolf:MinRemains() == 0) or
		(ConvergingStorms.known and ConvergingStorms:Stack() < ConvergingStorms:MaxStack())
	) then
		return CrashLightning
	end
	if self.use_cds and Sundering:Usable() and (
		Earthsurge.known or
		Player.set_bonus.t30 >= 2 or
		(DoomWinds.known and DoomWinds:Up())
	) then
		UseCooldown(Sundering)
	end
	if FireNova:Usable() and FlameShock:Ticking() >= clamp(Player.enemies, 4, 6) then
		return FireNova
	end
	if Hailstorm.known then
		if IceStrike:Usable() and IceStrike.buff:Down() then
			return IceStrike
		end
		if FrostShock:Usable() and (Hailstorm:Stack() >= 8 or IceStrike.buff:Up()) then
			return FrostShock
		end
	end
	if self.use_cds and Sundering:Usable() then
		UseCooldown(Sundering)
	end
	if FlameShock:Usable() and (
		(MoltenAssault.known and FlameShock:Usable() and FlameShock:Down()) or
		((FireNova.known or PrimordialWave.known) and FlameShock:Refreshable() and FlameShock:Ticking() < min(6, Player.enemies) and Target.timeToDie > (FlameShock:Remains() + 6))
	) then
		return FlameShock
	end
	if FireNova:Usable() and FlameShock:Ticking() >= 3 then
		return FireNova
	end
	if Hailstorm.known and FrostShock:Usable() and Hailstorm:Stack() >= clamp(Player.enemies - 1, 2, 5) then
		return FrostShock
	end
	if DeeplyRootedElements.known and Stormstrike:Usable() and CrashLightning.buff:Up() then
		return Stormstrike
	end
	if CrashingStorms.known and CrashLightning:Usable() and ClCrashLightning:Up() and Player.enemies >= 4 then
		return CrashLightning
	end
	if Windstrike:Usable() then
		return Windstrike
	end
	if Stormstrike:Usable() then
		return Stormstrike
	end
	if IceStrike:Usable() then
		return IceStrike
	end
	if LavaLash:Usable() then
		return LavaLash
	end
	if CrashLightning:Usable() then
		return CrashLightning
	end
	if FireNova:Usable() and FlameShock:Ticking() >= 2 then
		return FireNova
	end
	if MaelstromWeapon.current >= 5 then
		if ElementalBlast:Usable() and (
			not ElementalSpirits.known or
			ElementalBlast:Charges() >= ElementalBlast:MaxCharges() or
			Pet.ElementalSpiritWolf:Up()
		) then
			return ElementalBlast
		end
		if LavaBurst:Usable() and (MoltenWeapon:Stack() + (VolcanicStrength:Up() and 1 or 0)) > CracklingSurge:Stack() then
			return LavaBurst
		end
		if LightningBolt:Usable() and self.expectedLbFunnel > self.expectedClFunnel then
			return LightningBolt
		end
		if ChainLightning:Usable() then
			return ChainLightning
		end
	end
	if FlameShock:Usable() and FlameShock:Down() then
		return FlameShock
	end
	if not Hailstorm.known and FrostShock:Usable() then
		return FrostShock
	end
end

APL[SPEC.ENHANCEMENT].single = function(self)
--[[
actions.single=windstrike,if=talent.thorims_invocation.enabled&buff.maelstrom_weapon.stack>1&ti_lightning_bolt&!talent.elemental_spirits.enabled
actions.single+=/feral_spirit
actions.single+=/tempest,if=buff.maelstrom_weapon.stack=buff.maelstrom_weapon.max_stack|(buff.maelstrom_weapon.stack>=5&(tempest_mael_count>30|buff.awakening_storms.stack=2))
actions.single+=/doom_winds,if=raid_event.adds.in>=action.doom_winds.cooldown
actions.single+=/windstrike,if=talent.thorims_invocation.enabled&buff.maelstrom_weapon.stack>1&ti_lightning_bolt
actions.single+=/sundering,if=buff.ascendance.up&pet.surging_totem.active&talent.earthsurge.enabled
actions.single+=/primordial_wave,if=!dot.flame_shock.ticking&talent.lashing_flames.enabled&(raid_event.adds.in>(action.primordial_wave.cooldown%(1+set_bonus.tier31_4pc))|raid_event.adds.in<6)
actions.single+=/flame_shock,if=!ticking&talent.lashing_flames.enabled
actions.single+=/elemental_blast,if=buff.maelstrom_weapon.stack>=5&talent.elemental_spirits.enabled&feral_spirit.active>=4
actions.single+=/lightning_bolt,if=talent.supercharge.enabled&buff.maelstrom_weapon.stack=buff.maelstrom_weapon.max_stack
actions.single+=/sundering,if=set_bonus.tier30_2pc&raid_event.adds.in>=action.sundering.cooldown
actions.single+=/lightning_bolt,if=buff.maelstrom_weapon.stack>=5&buff.crackling_thunder.down&buff.ascendance.up&ti_chain_lightning&(buff.ascendance.remains>(cooldown.strike.remains+gcd))
actions.single+=/stormstrike,if=!talent.elemental_spirits.enabled&(buff.doom_winds.up|talent.deeply_rooted_elements.enabled|(talent.stormblast.enabled&buff.stormbringer.up))
actions.single+=/lava_lash,if=buff.hot_hand.up
actions.single+=/elemental_blast,if=buff.maelstrom_weapon.stack>=5&charges=max_charges
actions.single+=/tempest,if=buff.maelstrom_weapon.stack>=8
actions.single+=/lightning_bolt,if=buff.maelstrom_weapon.stack>=8&buff.primordial_wave.up&raid_event.adds.in>buff.primordial_wave.remains&(!buff.splintered_elements.up|fight_remains<=12)
actions.single+=/chain_lightning,if=buff.maelstrom_weapon.stack>=8&buff.crackling_thunder.up&talent.elemental_spirits.enabled
actions.single+=/elemental_blast,if=buff.maelstrom_weapon.stack>=8&(feral_spirit.active>=2|!talent.elemental_spirits.enabled)
actions.single+=/lava_burst,if=!talent.thorims_invocation.enabled&buff.maelstrom_weapon.stack>=5
actions.single+=/lightning_bolt,if=((buff.maelstrom_weapon.stack>=8)|(talent.static_accumulation.enabled&buff.maelstrom_weapon.stack>=5))&buff.primordial_wave.down
actions.single+=/crash_lightning,if=talent.alpha_wolf.enabled&feral_spirit.active&alpha_wolf_min_remains=0
actions.single+=/primordial_wave,if=raid_event.adds.in>(action.primordial_wave.cooldown%(1+set_bonus.tier31_4pc))|raid_event.adds.in<6
actions.single+=/stormstrike,if=talent.elemental_spirits.enabled&(buff.doom_winds.up|talent.deeply_rooted_elements.enabled|(talent.stormblast.enabled&buff.stormbringer.up))
actions.single+=/flame_shock,if=!ticking
actions.single+=/windstrike,if=(talent.totemic_rebound.enabled&(time-(action.stormstrike.last_used<?action.windstrike.last_used))>=3.5)|(talent.awakening_storms.enabled&(time-(action.stormstrike.last_used<?action.windstrike.last_used<?action.lightning_bolt.last_used<?action.tempest.last_used<?action.chain_lightning.last_used))>=3.5)
actions.single+=/stormstrike,if=(talent.totemic_rebound.enabled&(time-(action.stormstrike.last_used<?action.windstrike.last_used))>=3.5)|(talent.awakening_storms.enabled&(time-(action.stormstrike.last_used<?action.windstrike.last_used<?action.lightning_bolt.last_used<?action.tempest.last_used<?action.chain_lightning.last_used))>=3.5)
actions.single+=/lava_lash,if=talent.lively_totems.enabled&(time-action.lava_lash.last_used>=3.5)
actions.single+=/ice_strike,if=talent.elemental_assault.enabled&talent.swirling_maelstrom.enabled
actions.single+=/lava_lash,if=talent.lashing_flames.enabled
actions.single+=/ice_strike,if=!buff.ice_strike.up
actions.single+=/frost_shock,if=buff.hailstorm.up
actions.single+=/crash_lightning,if=talent.converging_storms.enabled
actions.single+=/lava_lash
actions.single+=/ice_strike
actions.single+=/windstrike
actions.single+=/stormstrike
actions.single+=/sundering,if=raid_event.adds.in>=action.sundering.cooldown
actions.single+=/tempest,if=buff.maelstrom_weapon.stack>=5
actions.single+=/lightning_bolt,if=talent.hailstorm.enabled&buff.maelstrom_weapon.stack>=5&buff.primordial_wave.down
actions.single+=/frost_shock
actions.single+=/crash_lightning
actions.single+=/fire_nova,if=active_dot.flame_shock
actions.single+=/earth_elemental
actions.single+=/flame_shock
actions.single+=/chain_lightning,if=buff.maelstrom_weapon.stack>=5&buff.crackling_thunder.up&talent.elemental_spirits.enabled
actions.single+=/lightning_bolt,if=buff.maelstrom_weapon.stack>=5&buff.primordial_wave.down
]]
	if ThorimsInvocation.known and not ElementalSpirits.known and Windstrike:Usable() and MaelstromWeapon.current > 1 and ThorimsInvocation:LightningBolt() then
		return Windstrike
	end
	if self.use_cds and FeralSpirit:Usable() then
		UseCooldown(FeralSpirit)
	end
	if Tempest:Usable() and (
		MaelstromWeapon.deficit == 0 or
		(MaelstromWeapon.current >= 5 and (Tempest:Maelstrom() > 30 or AwakeningStorms:Stack() >= 2 or Tempest.buff:Remains() < 4))
	) then
		return Tempest
	end
	if self.use_cds and DoomWinds:Usable() then
		UseCooldown(DoomWinds)
	end
	if ThorimsInvocation.known and Windstrike:Usable() and MaelstromWeapon.current > 1 and ThorimsInvocation:LightningBolt() then
		return Windstrike
	end
	if self.use_cds and Earthsurge.known and Sundering:Usable() and AscendanceAir:Up() and Pet.SurgingTotem:Up() then
		UseCooldown(Sundering)
	end
	if LashingFlames.known and FlameShock:Down() then
		if self.use_cds and PrimordialWave:Usable() then
			UseCooldown(PrimordialWave)
		end
		if FlameShock:Usable() then
			return FlameShock
		end
	end
	if ElementalSpirits.known and ElementalBlast:Usable() and MaelstromWeapon.current >= 5 and Pet.ElementalSpiritWolf:Count() >= 4 then
		return ElementalBlast
	end
	if Supercharge.known and LightningBolt:Usable() and MaelstromWeapon.deficit == 0 then
		return LightningBolt
	end
	if self.use_cds and Sundering:Usable() and Player.set_bonus.t30 >= 2 then
		UseCooldown(Sundering)
	end
	if LightningBolt:Usable() and MaelstromWeapon.current >= 5 and CracklingThunder:Down() and AscendanceAir:Up() and ThorimsInvocation:ChainLightning() and AscendanceAir:Remains() > (Strike:Cooldown() + Player.gcd) then
		return LightningBolt
	end
	if not ElementalSpirits.known and Stormstrike:Usable() and (
		DeeplyRootedElements.known or
		(DoomWinds.known and DoomWinds:Up()) or
		(Stormblast.known and Stormbringer:Up())
	) then
		return Stormstrike
	end
	if HotHand.known and LavaLash:Usable() and HotHand:Up() then
		return LavaLash
	end
	if MaelstromWeapon.current >= 5 then
		if ElementalBlast:Usable() and ElementalBlast:Charges() >= ElementalBlast:MaxCharges() then
			return ElementalBlast
		end
		if Tempest:Usable() and MaelstromWeapon.current >= 8 then
			return Tempest
		end
		if LightningBolt:Usable() and MaelstromWeapon.current >= 8 and PrimordialWave.buff:Up() and (SplinteredElements:Down() or Target.timeToDie <= 12) then
			return LightningBolt
		end
		if ElementalSpirits.known and ChainLightning:Usable() and MaelstromWeapon.current >= 8 and CracklingThunder:Up() then
			return ChainLightning
		end
		if ElementalBlast:Usable() and MaelstromWeapon.current >= 8 and (not ElementalSpirits.known or Pet.ElementalSpiritWolf:Count() >= 2) then
			return ElementalBlast
		end
		if not ThorimsInvocation.known and LavaBurst:Usable() then
			return LavaBurst
		end
		if LightningBolt:Usable() and (MaelstromWeapon.current >= 8 or StaticAccumulation.known) and PrimordialWave.buff:Down() then
			return LightningBolt
		end
	end
	if AlphaWolf.known and CrashLightning:Usable() and Pet.SpiritWolf:Up() and AlphaWolf:MinRemains() == 0 then
		return CrashLightning
	end
	if self.use_cds and PrimordialWave:Usable() then
		UseCooldown(PrimordialWave)
	end
	if ElementalSpirits.known and Stormstrike:Usable() and (
		DeeplyRootedElements.known or
		(DoomWinds.known and DoomWinds:Up()) or
		(Stormblast.known and Stormbringer:Up())
	) then
		return Stormstrike
	end
	if FlameShock:Usable() and FlameShock:Down() then
		return FlameShock
	end
	if Windstrike:Usable() and (
		(TotemicRebound.known and (Player.time - max(Stormstrike.last_used, Windstrike.last_used)) >= 3.5) or
		(AwakeningStorms.known and (Player.time - max(Stormstrike.last_used, Windstrike.last_used, LightningBolt.last_used, Tempest.last_used, ChainLightning.last_used)) >= 3.5)
	) then
		return Windstrike
	end
	if Stormstrike:Usable() and (
		(TotemicRebound.known and (Player.time - max(Stormstrike.last_used, Windstrike.last_used)) >= 3.5) or
		(AwakeningStorms.known and (Player.time - max(Stormstrike.last_used, Windstrike.last_used, LightningBolt.last_used, Tempest.last_used, ChainLightning.last_used)) >= 3.5)
	) then
		return Stormstrike
	end
	if LivelyTotems.known and LavaLash:Usable() and (Player.time - LavaLash.last_used) >= 3.5 then
		return LavaLash
	end
	if ElementalAssault.known and SwirlingMaelstrom.known and IceStrike:Usable() then
		return IceStrike
	end
	if LashingFlames.known and LavaLash:Usable() then
		return LavaLash
	end
	if IceStrike:Usable() and IceStrike.buff:Down() then
		return IceStrike
	end
	if FrostShock:Usable() and Hailstorm:Up() then
		return FrostShock
	end
	if ConvergingStorms.known and CrashLightning:Usable() then
		return CrashLightning
	end
	if LavaLash:Usable() then
		return LavaLash
	end
	if IceStrike:Usable() then
		return IceStrike
	end
	if Windstrike:Usable() then
		return Windstrike
	end
	if Stormstrike:Usable() then
		return Stormstrike
	end
	if self.use_cds and Sundering:Usable() then
		UseCooldown(Sundering)
	end
	if MaelstromWeapon.current >= 5 then
		if Tempest:Usable() then
			return Tempest
		end
		if Hailstorm.known and LightningBolt:Usable() and PrimordialWave.buff:Down() then
			return LightningBolt
		end
	end
	if FrostShock:Usable() then
		return FrostShock
	end
	if CrashLightning:Usable() then
		return CrashLightning
	end
	if FireNova:Usable() and FlameShock:Ticking() > 0 then
		return FireNova
	end
	if Opt.earth and self.use_cds and EarthElemental:Usable() then
		UseExtra(EarthElemental)
	end
	if FlameShock:Usable() then
		return FlameShock
	end
	if MaelstromWeapon.current >= 5 then
		if ElementalSpirits.known and ChainLightning:Usable() and CracklingThunder:Up() then
			return ChainLightning
		end
		if LightningBolt:Usable() and PrimordialWave.buff:Down() then
			return LightningBolt
		end
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
		text_tl = MaelstromWeapon.current
	end
	if Player.major_cd_remains > 0 then
		text_center = format('%.1fs', Player.major_cd_remains)
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
	TrackedAuras:Remove(dstGUID)
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

function Events:UNIT_SPELLCAST_SENT(unitId, destName, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.consume_mw then
		MaelstromWeapon.consume_castGUID = castGUID
		MaelstromWeapon.consume_amount = MaelstromWeapon:Stack()
	end
end

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
	if castGUID == MaelstromWeapon.consume_castGUID then
		Tempest.maelstrom_spent = Tempest.maelstrom_spent + MaelstromWeapon.consume_amount
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
	if startsWith(msg[1], 'fu') then
		if msg[2] then
			Opt.funnel = msg[2] == 'on'
		end
		return Status('Use funnel APL on multitarget for focused single target cleave (enhancement only)', Opt.funnel)
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
		'funnel |cFF00C000on|r/|cFFC00000off|r - use funnel APL on multitarget for focused single target cleave (enhancement)',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_Farseer1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
