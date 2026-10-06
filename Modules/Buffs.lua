-- Buffs: Klasse -> Kampfrausch / Battle Rez, auch je Rolle (rein, ohne WoW-API -> busted-testbar)
local _, ns = ...

local Buffs = {}
if type(ns) == "table" then
	ns.Buffs = Buffs
end

-- Laut Konzept: Schamane, Magier, Jäger, Rufer -> Kampfrausch;
-- Druide, Todesritter, Hexenmeister, Paladin -> Battle Rez
Buffs.BLOODLUST = { SHAMAN = true, MAGE = true, HUNTER = true, EVOKER = true }
Buffs.BATTLEREZ = { DRUID = true, DEATHKNIGHT = true, WARLOCK = true, PALADIN = true }

-- Welche Klassen welche Rolle spielen können
local ROLE_CLASSES = {
	TANK = { DEATHKNIGHT = true, DEMONHUNTER = true, DRUID = true, MONK = true, PALADIN = true, WARRIOR = true },
	HEALER = { DRUID = true, EVOKER = true, MONK = true, PALADIN = true, PRIEST = true, SHAMAN = true },
	DAMAGER = {
		DEATHKNIGHT = true, DEMONHUNTER = true, DRUID = true, EVOKER = true, HUNTER = true, MAGE = true, MONK = true,
		PALADIN = true, PRIEST = true, ROGUE = true, SHAMAN = true, WARLOCK = true, WARRIOR = true,
	},
}

-- buff: "BLOODLUST" oder "BATTLEREZ"
function Buffs.Provides(class, buff)
	return Buffs[buff][class] == true
end

function Buffs.GroupHas(classes, buff)
	for _, class in ipairs(classes) do
		if Buffs.Provides(class, buff) then
			return true
		end
	end
	return false
end

-- Kann irgendeine Klasse in dieser Rolle den Buff mitbringen?
function Buffs.RoleCanProvide(role, buff)
	local classes = ROLE_CLASSES[role]
	if not classes then
		return false
	end
	for class in pairs(Buffs[buff]) do
		if classes[class] then
			return true
		end
	end
	return false
end

return Buffs
