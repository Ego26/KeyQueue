-- Util: kleine WoW-Helfer, die Listing, AutoInvite, Search und UI gemeinsam nutzen
local ADDON_NAME, ns = ...

local Util = {}
ns.Util = Util

local ROLE_ATLAS = {
	TANK = "roleicon-tiny-tank",
	HEALER = "roleicon-tiny-healer",
	DAMAGER = "roleicon-tiny-dps",
}

-- Midnight: geschützte Werte ("Secret Values") darf Addon-Code nicht vergleichen
function Util.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) == true
end

-- Gibt den Wert zurück, wenn er lesbar ist, sonst nil
function Util.Readable(value)
	if Util.IsSecret(value) then
		return nil
	end
	return value
end

function Util.NameKey(name)
	if Util.IsSecret(name) then
		return nil
	end
	return ns.Matcher.NameKey(name, GetNormalizedRealmName())
end

-- Wandelt z. B. ERR_DECLINE_GROUP_S in ein Lua-Pattern um
function Util.FormatToPattern(format)
	local pattern = format:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	pattern = pattern:gsub("%%s", "(.+)")
	pattern = pattern:gsub("%%d", "(%%d+)")
	return pattern
end

function Util.GetMyRole()
	local getSpec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization or GetSpecialization
	local getRole = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationRole or GetSpecializationRole
	local spec = getSpec and getSpec()
	local role = spec and getRole and getRole(spec)
	if role == "TANK" or role == "HEALER" then
		return role
	end
	return "DAMAGER"
end

-- Rollen, die die Klasse spielen kann (wie Blizzards Gruppensuche): { TANK = bool, HEALER = bool, DAMAGER = bool }
function Util.GetAvailableRoles()
	local ok, tank, healer, damage = pcall(function()
		return C_LFGList.GetAvailableRoles()
	end)
	if not ok or (tank == nil and healer == nil and damage == nil) then
		return { TANK = true, HEALER = true, DAMAGER = true } -- unbekannt: nichts sperren
	end
	return { TANK = tank and true or false, HEALER = healer and true or false, DAMAGER = damage and true or false }
end

-- Anmeldungen nach RIO sortieren (höchster zuerst). Eine Anmeldung = { members = { ... } } oder ein
-- einzelner Spieler; bei Gruppen zählt der höchste Wert. RIO von Raider.IO, sonst Blizzard-Wertung.
local function EntryRio(entry)
	local best = 0
	for _, member in ipairs(entry.members or { entry }) do
		local score = Util.GetRaiderIOScore(member.name) or tonumber(Util.Readable(member.score)) or 0
		best = math.max(best, score)
	end
	return best
end

function Util.SortByRio(list)
	local scores = {}
	for index, entry in ipairs(list) do
		scores[entry] = EntryRio(entry) + 1 / (index + 1) -- gleicher Wert: alte Reihenfolge bleibt
	end
	table.sort(list, function(a, b)
		return scores[a] > scores[b]
	end)
	return list
end

-- Liste von Spielern ({ role = "TANK"/"HEALER"/"DAMAGER" }) stabil nach Tank, Heiler, DPS sortieren
local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }
function Util.SortByRole(list)
	for index, entry in ipairs(list) do
		entry.sortIndex = index
	end
	table.sort(list, function(a, b)
		local ra, rb = ROLE_ORDER[a.role] or 3, ROLE_ORDER[b.role] or 3
		if ra ~= rb then
			return ra < rb
		end
		return a.sortIndex < b.sortIndex
	end)
	for _, entry in ipairs(list) do
		entry.sortIndex = nil
	end
	return list
end

-- Spec-Symbole in 128 x 128 (Media/Specs/<specID>.tga, erzeugt von scripts/spec-icons.cjs).
-- Das Spiel liefert nur 64 x 64; fehlt eine Spec hier (z. B. neu im Patch), bleibt Blizzards Symbol.
local HD_SPECS = {
	[62] = true, [63] = true, [64] = true, [65] = true, [66] = true, [70] = true, [71] = true, [72] = true,
	[73] = true, [102] = true, [103] = true, [104] = true, [105] = true, [250] = true, [251] = true,
	[252] = true, [253] = true, [254] = true, [255] = true, [256] = true, [257] = true, [258] = true,
	[259] = true, [260] = true, [261] = true, [262] = true, [263] = true, [264] = true, [265] = true,
	[266] = true, [267] = true, [268] = true, [269] = true, [270] = true, [577] = true, [581] = true,
	[1467] = true, [1468] = true, [1473] = true,
}
local SPEC_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Specs\\"
-- Jedes Sheet (256 x 128) enthält das Symbol in jeder Pixelgröße 14-40: [Pixel] = { x, y }
local SPEC_SHEET = {
	[40] = { 0, 0 }, [39] = { 41, 0 }, [38] = { 81, 0 }, [37] = { 120, 0 }, [36] = { 158, 0 }, [35] = { 195, 0 },
	[34] = { 0, 41 }, [33] = { 35, 41 }, [32] = { 69, 41 }, [31] = { 102, 41 }, [30] = { 134, 41 },
	[29] = { 165, 41 }, [28] = { 195, 41 }, [27] = { 224, 41 }, [26] = { 0, 76 }, [25] = { 27, 76 },
	[24] = { 53, 76 }, [23] = { 78, 76 }, [22] = { 102, 76 }, [21] = { 125, 76 }, [20] = { 147, 76 },
	[19] = { 168, 76 }, [18] = { 188, 76 }, [17] = { 207, 76 }, [16] = { 225, 76 }, [15] = { 0, 103 },
	[14] = { 16, 103 },
}
local SHEET_W, SHEET_H, SHEET_MIN, SHEET_MAX = 256, 128, 14, 40

-- Wie viele echte Bildschirmpixel sind "units" UI-Einheiten für diese Region?
local function PixelCount(region, units)
	local _, physicalHeight = GetPhysicalScreenSize()
	return math.floor(units * region:GetEffectiveScale() * (physicalHeight or 768) / 768 + 0.5)
end

-- Spec-Symbol auf eine Textur legen. Mit Sheet: genau die Pixelgröße, die auf dem Bildschirm
-- gebraucht wird, 1:1 gezeichnet (gestochen scharf). Sonst Blizzards Symbol (fallback).
-- units = Kantenlänge der Textur in UI-Einheiten (sie muss auf ganze Pixel ausgerichtet sein)
function Util.SetSpecTexture(texture, specID, fallback, units)
	if specID and HD_SPECS[specID] then
		local pixels = math.max(SHEET_MIN, math.min(SHEET_MAX, PixelCount(texture, units)))
		local cell = SPEC_SHEET[pixels]
		texture:SetTexture(SPEC_PATH .. specID, nil, nil, "NEAREST")
		texture:SetTexCoord(cell[1] / SHEET_W, (cell[1] + pixels) / SHEET_W, cell[2] / SHEET_H, (cell[2] + pixels) / SHEET_H)
		return true
	end
	texture:SetTexture(fallback, nil, nil, "LINEAR")
	texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	return false
end

function Util.GetMySpecIcon()
	local getSpec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization or GetSpecialization
	local getInfo = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo or GetSpecializationInfo
	local spec = getSpec and getSpec()
	if spec and getInfo then
		local info = { getInfo(spec) }
		return info[4], info[1] -- Symbol, specID
	end
end

-- "[Rolle] [Spec-Symbol] Arkan Magier" in Klassenfarbe
-- size = Kantenlänge der Symbole (Standard 16); in Textzeilen so groß wie die Schrift, sonst wird
-- die Zeile höher und rückt optisch an die Zeile darüber
function Util.GetMySpecText(size)
	size = size or 16
	local getSpec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization or GetSpecialization
	local getInfo = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo or GetSpecializationInfo
	local spec = getSpec and getSpec()
	local specName, icon
	if spec and getInfo then
		local info = { getInfo(spec) }
		specName, icon = info[2], info[4]
	end
	local className, classFile = UnitClass("player")
	local text = Util.ClassName(specName and (specName .. " " .. className) or className or "", classFile)
	if icon then
		text = "|T" .. icon .. ":" .. size .. ":" .. size .. ":0:0:64:64:5:59:5:59|t " .. text
	end
	return Util.RoleIcon(Util.GetMyRole(), size) .. " " .. text
end

-- "[Spec] Elementar Schamane  \194\183  Score 3505  \194\183  iLvl 322" (Hero-Karten)
function Util.MeText()
	return ns.L["SEARCH_ME"]:format(Util.GetMySpecText(13), Util.ScoreText(Util.GetMyRio()), Util.GetMyItemLevel())
end

-- Spec-ID aus Klasse + (lokalisiertem) Spec-Namen, wie ihn die Suchergebnisse liefern
local specIDs
function Util.SpecID(classFile, specName)
	if not (classFile and specName) then
		return nil
	end
	if not specIDs then
		specIDs = {}
		local getNum = C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID
			or GetNumSpecializationsForClassID
		local getInfo = GetSpecializationInfoForClassID
			or (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoForClassID)
		if getNum and getInfo then
			for classID = 1, GetNumClasses() do
				local _, file = GetClassInfo(classID)
				for index = 1, (getNum(classID) or 0) do
					local id, name = getInfo(classID, index)
					if file and id and name then
						specIDs[file .. ":" .. name] = id
					end
				end
			end
		end
	end
	return specIDs[classFile .. ":" .. specName]
end

-- Text in Blizzards Gruppenfinder-Suchfeld (z. B. "16-19" für Keystufen). Addons dürfen ihn nicht
-- setzen, die Server-Suche (auch die von KeyQueue) nutzt ihn aber - nur lesen.
function Util.GetBlizzardSearchText()
	local panel = LFGListFrame and LFGListFrame.SearchPanel
	local box = panel and panel.SearchBox
	if not box then
		return ""
	end
	local ok, text = pcall(box.GetText, box)
	return ok and strtrim(Util.Readable(text) or "") or ""
end

-- Ist das Suchergebnis eine M+-Gruppe (Mythischer Schlüsselstein)? KeyQueue kümmert sich nur um M+.
function Util.IsMythicPlusResult(resultID)
	local ok, isMythicPlus = pcall(function()
		local info = C_LFGList.GetSearchResultInfo(resultID)
		local activityID = info and Util.Readable(info.activityIDs and info.activityIDs[1] or info.activityID)
		local activity = activityID and C_LFGList.GetActivityInfoTable(activityID)
		return activity and Util.Readable(activity.isMythicPlusActivity) and true or false
	end)
	return ok and isMythicPlus or false
end

function Util.RoleFlags(role)
	return role == "TANK", role == "HEALER", role == "DAMAGER"
end

-- Rollen der eigenen Party (ich zuerst); unbekannte Rollen zählen als DPS
function Util.GetPartyRoles()
	local roles = { Util.GetMyRole() }
	if IsInGroup() and not IsInRaid() then
		for i = 1, GetNumSubgroupMembers() do
			local role = Util.Readable(UnitGroupRolesAssigned("party" .. i))
			table.insert(roles, (role == "TANK" or role == "HEALER") and role or "DAMAGER")
		end
	end
	return roles
end

function Util.GetGroupClasses()
	local classes = {}
	local units = { "player", "party1", "party2", "party3", "party4" }
	for _, unit in ipairs(units) do
		if UnitExists(unit) then
			local class = Util.Readable(UnitClassBase(unit))
			if class then
				table.insert(classes, class)
			end
		end
	end
	return classes
end

-- Namensschlüssel aller Gruppenmitglieder (ohne mich)
function Util.GetRosterKeys()
	local keys = {}
	for i = 1, GetNumSubgroupMembers() do
		local key = Util.NameKey(GetUnitName("party" .. i, true))
		if key then
			keys[key] = true
		end
	end
	return keys
end

function Util.GetMyScore()
	local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
	return Util.Readable(summary and summary.currentSeasonScore) or 0
end

-- Mein bester Run pro Dungeon dieser Saison: [challengeModeID] = { level, timed }
-- Eigene M+-Daten ändern sich nur nach einem Key: zwischenspeichern statt bei jedem Neuzeichnen neu
-- abfragen (jede Abfrage bei Blizzard legt neue Tabellen an - beim Überfahren der Liste viele MB pro
-- Minute). Ungültig nach einem Key (Util.InvalidateMyRuns), spätestens nach MY_RUNS_TTL Sekunden.
-- Die gelieferten Tabellen nur lesen, nicht verändern.
local MY_RUNS_TTL = 60
local myBestRuns, myBestRunsAt, mySeason, mySeasonAt
function Util.InvalidateMyRuns()
	myBestRuns, mySeason = nil, nil
end

function Util.GetMyBestRuns()
	local now = GetTime()
	if myBestRuns and now - myBestRunsAt < MY_RUNS_TTL then
		return myBestRuns
	end
	local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
	local best = {}
	for _, run in ipairs(summary and summary.runs or {}) do
		local id, level = Util.Readable(run.challengeModeID), Util.Readable(run.bestRunLevel)
		if id and level then
			best[id] = { level = level, timed = Util.Readable(run.finishedSuccess) and true or false }
		end
	end
	myBestRuns, myBestRunsAt = best, now
	return best
end

-- Eigene M+-Saison: getimte Runs nach Stufen, diese Woche, bester Run
-- { brackets = { {label, count}, ... }, weekCount, weekBest, total, timed, best = { level, mapID, timed } }
local BRACKETS = { { 15, 99, "15+" }, { 12, 14, "12-14" }, { 10, 11, "10-11" }, { 2, 9, "2-9" } }
function Util.GetMySeason()
	local now = GetTime()
	if mySeason and now - mySeasonAt < MY_RUNS_TTL then
		return mySeason
	end
	local season = { brackets = {}, weekCount = 0, weekBest = 0, total = 0, timed = 0 }
	local runs = C_MythicPlus.GetRunHistory and C_MythicPlus.GetRunHistory(true, true, true) or {}
	local counts = {}
	for _, run in ipairs(runs) do
		local level = Util.Readable(run.level) or 0
		local timed = Util.Readable(run.completed) and true or false
		season.total = season.total + 1
		if timed then
			season.timed = season.timed + 1
			for index, bracket in ipairs(BRACKETS) do
				if level >= bracket[1] and level <= bracket[2] then
					counts[index] = (counts[index] or 0) + 1
				end
			end
		end
		if Util.Readable(run.thisWeek) then
			season.weekCount = season.weekCount + 1
			season.weekBest = math.max(season.weekBest, level)
		end
	end
	for index, bracket in ipairs(BRACKETS) do
		table.insert(season.brackets, { label = bracket[3], count = counts[index] or 0 })
	end
	for mapID, best in pairs(Util.GetMyBestRuns()) do
		local current = season.best
		if not current or best.level > current.level or (best.level == current.level and best.timed and not current.timed) then
			season.best = { level = best.level, timed = best.timed, mapID = mapID }
		end
	end
	mySeason, mySeasonAt = season, now
	return season
end

-- Raider.IO (optional, keine Abhängigkeit): M+-Score eines anderen Spielers aus der Datenbank des
-- Raider.IO-Addons, falls es installiert ist. Blizzard selbst liefert in der Suche nur den Leader-Score.
-- Öffentliche Schnittstelle von Raider.IO: RaiderIO.GetProfile("Name-Realm") bzw. ("Name") für den
-- eigenen Realm. Liefert .mythicKeystoneProfile (currentScore, mainCurrentScore, sortedMilestones,
-- sortedDungeons, maxDungeonLevel/maxDungeon) - nil, wenn Raider.IO fehlt oder den Spieler nicht kennt.
-- Raider.IO-Profil (M+ und Raid) eines Spielers, nil ohne Raider.IO oder ohne Daten
local function HasKeystoneData(mplus)
	return type(mplus) == "table" and (mplus.hasRenderableData or (mplus.currentScore or 0) > 0) and true or false
end

local function RaiderIOLookup(name)
	local rio = _G.RaiderIO
	if type(rio) ~= "table" or type(name) ~= "string" or name == "" or Util.IsSecret(name) then
		return nil
	end
	-- erst "Name-Realm", dann Name und Realm getrennt (Realm auch mit Leerzeichen: "TwistingNether")
	local short, realm = name:match("^([^%-]+)%-(.+)$")
	local attempts = { { name } }
	if short then
		table.insert(attempts, { short, realm })
		local spaced = realm:gsub("(%l)(%u)", "%1 %2")
		if spaced ~= realm then
			table.insert(attempts, { short, spaced })
		end
	end
	for _, args in ipairs(attempts) do
		local ok, profile = pcall(function()
			return rio.GetProfile(args[1], args[2])
		end)
		if ok and type(profile) == "table"
			and (HasKeystoneData(profile.mythicKeystoneProfile) or type(profile.raidProfile) == "table") then
			return profile
		end
	end
end

-- M+-Teil des Raider.IO-Profils (Wertung, Runs, Meilensteine), nil ohne Daten
function Util.GetRaiderIOProfile(name)
	local profile = RaiderIOLookup(name)
	local mplus = profile and profile.mythicKeystoneProfile
	return HasKeystoneData(mplus) and mplus or nil
end

-- Raid-Fortschritt aus Raider.IO wie in dessen Tooltip: { name = "VA", text = "HC 8/8  M 2/9" } mit
-- Schwierigkeit in Raider.IOs Farben (N grün, HC blau, M lila). all = auch ältere Raids und Main-Fortschritt.
local RAID_DIFFICULTY = { [1] = { "N", "1eff00" }, [2] = { "HC", "0070dd" }, [3] = { "M", "a335ee" } }
function Util.GetRaiderIORaids(name, all)
	local profile = RaiderIOLookup(name)
	local raid = profile and profile.raidProfile
	local list = {}
	local ok = pcall(function()
		for _, progress in ipairs(type(raid) == "table" and raid.raidProgress or {}) do
			if all or (progress.current and not progress.isMainProgress) then
				local parts = {}
				for _, group in ipairs(progress.progress or {}) do
					local difficulty = RAID_DIFFICULTY[group.difficulty]
					if difficulty and not group.obsolete and (group.kills or 0) > 0 then
						table.insert(parts, ("|cff%s%s|r %d/%d"):format(difficulty[2], difficulty[1], group.kills,
							progress.raid and progress.raid.bossCount or 0))
					end
				end
				if #parts > 0 then
					local raidName = progress.raid and progress.raid.shortName or "?"
					if progress.isMainProgress then
						raidName = ns.L["PROFILE_RAID_MAIN"]:format(raidName)
					end
					table.insert(list, { name = raidName, text = table.concat(parts, "  ") })
				end
			end
		end
	end)
	return ok and list or {}
end

-- Text in der Farbe einer Wertung (wie Raider.IO die Dungeon-Namen einfärbt)
function Util.ScoreColored(text, score)
	local r, g, b = Util.ScoreColor(score or 0)
	if not r then
		return text
	end
	return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), text)
end

-- Profil-Link auf raider.io: https://raider.io/characters/eu/twisting-nether/Name
-- Realm-Slug aus dem (ggf. normalisierten) Realm-Namen: "TwistingNether" -> "twisting-nether", "Zul'jin" -> "zuljin".
-- Realms mit nicht-lateinischem Namen (z. B. russische) heißen auf raider.io anders - dann die Suche.
local REGIONS = { [1] = "us", [2] = "kr", [3] = "eu", [4] = "tw", [5] = "cn" }
function Util.RaiderIOUrl(nameKey)
	local name, realm = (nameKey or ""):match("^([^%-]+)%-(.+)$")
	name = name or nameKey or ""
	realm = realm or GetRealmName() or ""
	if realm:find("[\128-\255]") then
		return "https://raider.io/search?term=" .. name
	end
	local slug = realm:gsub("(%l)(%u)", "%1-%2")
	slug = slug:gsub("'", ""):gsub("%s+", "-"):lower()
	local region = REGIONS[GetCurrentRegion and GetCurrentRegion() or 3] or "eu"
	return ("https://raider.io/characters/%s/%s/%s"):format(region, slug, name)
end

-- Maßgebliche Wertung eines Spielers: Raider.IO (RIO), wenn bekannt, sonst Blizzards M+-Wertung.
-- KeyQueue zeigt und filtert überall danach.
function Util.PlayerScore(name, blizzardScore)
	return Util.GetRaiderIOScore(name) or blizzardScore or 0
end

-- eigene Wertung für die Anzeige (Anforderungen von Gruppen prüft Blizzard weiter mit GetMyScore)
function Util.GetMyRio()
	return Util.GetRaiderIOScore("player") or Util.GetMyScore()
end

function Util.GetRaiderIOScore(name)
	local mplus = Util.GetRaiderIOProfile(name)
	local score = mplus and mplus.currentScore
	if type(score) == "number" and score > 0 then
		return score
	end
end

-- Instanz-Karte (Gruppenfinder-Aktivität) -> Challenge-Mode-ID (M+-Dungeon)
local challengeByMap
function Util.ChallengeMapID(instanceMapID)
	if not challengeByMap then
		challengeByMap = {}
		for _, id in ipairs(C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable() or {}) do
			local _, _, _, _, _, mapID = C_ChallengeMode.GetMapUIInfo(id)
			if mapID then
				challengeByMap[mapID] = id
			end
		end
	end
	return instanceMapID and challengeByMap[instanceMapID]
end

-- Keystufen-Bereich aus Blizzards Suchfeld: "17-18" -> 17, 18; "+18" -> 17, 19; "18" -> 18, 18
function Util.ParseLevelRange(text)
	text = text or ""
	local low, high = text:match("(%d+)%s*%-%s*(%d+)")
	if low then
		low, high = tonumber(low), tonumber(high)
		return math.min(low, high), math.max(low, high)
	end
	-- "+18" sucht bei Blizzard 17 bis 19, "18" genau 18
	local plus = text:match("^%s*%+(%d+)%s*$")
	if plus then
		return tonumber(plus) - 1, tonumber(plus) + 1
	end
	local single = text:match("^%s*(%d+)%s*$")
	if single then
		return tonumber(single), tonumber(single)
	end
end

function Util.GetMyItemLevel()
	local _, equipped = GetAverageItemLevel()
	return math.floor(equipped or 0)
end

-- Eigener Schlüssel: Aktivität fürs Listing, Stufe, Dungeon-Name und -Bild
function Util.GetKeystone()
	local activityID, groupID, level = C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel(false)
	if not activityID or activityID == 0 then
		return nil
	end
	local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
	local name, texture
	if mapID and mapID > 0 then
		name, _, _, texture = C_ChallengeMode.GetMapUIInfo(mapID)
	end
	if not name then
		local activity = C_LFGList.GetActivityInfoTable(activityID)
		name = activity and activity.fullName
	end
	return {
		activityID = activityID,
		groupID = groupID,
		level = level or C_MythicPlus.GetOwnedKeystoneLevel(),
		mapID = mapID,
		name = name or "?",
		texture = texture,
	}
end

function Util.ClassName(name, class)
	local color = class and C_ClassColor and C_ClassColor.GetClassColor(class)
	if color then
		return color:WrapTextInColorCode(name)
	end
	return name
end

-- Score in der Raider.IO-üblichen Farbskala (Blizzard liefert dieselbe Skala)
-- Score in Farbe: mit Raider.IO in dessen offiziellen Farben (RaiderIO.GetScoreColor), sonst Blizzards
-- Farbe eines Scores als r, g, b (nil = keine Farbe bekannt)
function Util.ScoreColor(score)
	score = score or 0
	local rio = _G.RaiderIO
	if type(rio) == "table" and score > 0 then
		local ok, r, g, b = pcall(function()
			return rio.GetScoreColor(score)
		end)
		if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
			return r, g, b
		end
	end
	local color = C_ChallengeMode.GetDungeonScoreRarityColor and C_ChallengeMode.GetDungeonScoreRarityColor(score)
	if color and color.r then
		return color.r, color.g, color.b
	end
end

function Util.ScoreText(score)
	local text = tostring(math.floor(score or 0))
	local r, g, b = Util.ScoreColor(score)
	if r then
		return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
			math.floor(b * 255 + 0.5), text)
	end
	return text
end

function Util.RoleIcon(role, size)
	local atlas = ROLE_ATLAS[role]
	if not atlas then
		return ""
	end
	return CreateAtlasMarkup(atlas, size or 14, size or 14)
end

-- Raider.IO-Wertung mit den Rollen davor wie in Raider.IOs Tooltip. data = mplus.mplusCurrent,
-- mplusMainCurrent oder mplusWarbandCurrent: { roles = { { "dps", "full" }, { "healer", "partial" } } }
-- in Raider.IOs Reihenfolge (Anteil an der Wertung); "partial" (nur ein Teil der Wertung) gedimmt
local RIO_ROLES = { tank = "TANK", healer = "HEALER", dps = "DAMAGER" }
function Util.RioScoreText(score, data)
	local text = Util.ScoreText(score)
	local roles = type(data) == "table" and data.roles
	if type(roles) ~= "table" then
		return text
	end
	local icons = {}
	for _, entry in ipairs(roles) do
		local atlas = type(entry) == "table" and ROLE_ATLAS[RIO_ROLES[entry[1]]]
		if atlas then
			if entry[2] == "partial" then
				table.insert(icons, CreateAtlasMarkup(atlas, 14, 14, 0, 0, 110, 110, 110))
			else
				table.insert(icons, CreateAtlasMarkup(atlas, 14, 14))
			end
		end
	end
	if #icons == 0 then
		return text
	end
	return table.concat(icons) .. " " .. text
end

-- Herkunft eines Spielers über die Sprache seines Realms (Blizzard verrät sie nicht): Realm-Liste aus
-- Modules/Realms.lua (scripts/realms.cjs). Liefert "DE", "GB", "FR", ... bzw. in Amerika "US", "AU"
-- (Ozeanien), "BR", "MX" - nil ohne Daten (Asien, unbekannter Realm, geschützter Name).
local realmIndex
local function RealmKey(realm)
	-- wie scripts/realms.cjs: ohne Leerzeichen, Bindestriche, Apostrophe, Klammern, Punkte, A-Z klein
	return (realm:gsub("[%s%-'%(%)%.]", ""):gsub("%u", string.lower))
end
function Util.RealmFlag(name)
	if type(name) ~= "string" or Util.IsSecret(name) then
		return nil
	end
	if not realmIndex then
		realmIndex = {}
		local data = ns.RealmData and ns.RealmData[GetCurrentRegion and GetCurrentRegion() or 0]
		for flag, list in pairs(data or {}) do
			for key in list:gmatch("[^,]+") do
				realmIndex[key] = flag
			end
		end
	end
	-- ohne Realm im Namen: eigener Realm
	local realm = name:match("%-(.+)$") or GetNormalizedRealmName() or GetRealmName()
	return realm and realmIndex[RealmKey(realm)] or nil
end

-- Flagge als Textsymbol (3:2), height in Pixeln
function Util.FlagMarkup(flag, height)
	if not flag then
		return ""
	end
	height = height or 12
	return ("|T%s%s:%d:%d:0:0:64:64:2:62:12:52|t"):format(ns.Theme.media.flags, flag, height,
		math.floor(height * 1.5 + 0.5))
end

-- 1234567 -> "1.2M"
function Util.ShortNumber(value)
	value = value or 0
	if value >= 1e9 then
		return ("%.2fB"):format(value / 1e9)
	elseif value >= 1e6 then
		return ("%.1fM"):format(value / 1e6)
	elseif value >= 1e4 then
		return ("%.0fK"):format(value / 1e3)
	end
	return tostring(math.floor(value + 0.5))
end

-- Stern vor Favoriten
function Util.FavoriteIcon(size)
	size = size or 12
	return ("|A:auctionhouse-icon-favorite:%d:%d|a"):format(size, size)
end

-- Freund (auch Battle.net) bzw. Gildenmitglied als Wort: "Freund" in Akzentfarbe, "Gilde" grün
function Util.RelationText(relationship)
	if relationship == "guild" then
		return ns.Theme.Colorize(ns.L["REL_GUILD"], "ok")
	elseif relationship == "friend" then
		return ns.Theme.Colorize(ns.L["REL_FRIEND"], "violetText")
	end
end

-- Rollen-Symbol auf Klassenfarbe wie in Blizzards Gruppenfinder (und PGF): Blizzards Atlas, sonst das
-- eigene Symbol (fallback). Überall gleich: Suche, History.
local ROLE_GLYPH_ATLAS = {
	TANK = "groupfinder-icon-role-micro-tank",
	HEALER = "groupfinder-icon-role-micro-heal",
	DAMAGER = "groupfinder-icon-role-micro-dps",
}
-- gibt es den Atlas? (einmal fragen: GetAtlasInfo legt bei jedem Aufruf eine neue Tabelle an)
local atlasExists = {}
local function HasAtlas(atlas)
	if atlasExists[atlas] == nil then
		atlasExists[atlas] = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)) and true or false
	end
	return atlasExists[atlas]
end

function Util.SetRoleGlyph(texture, role, fallback)
	local atlas = ROLE_GLYPH_ATLAS[role or "DAMAGER"]
	if atlas and HasAtlas(atlas) then
		texture:SetAtlas(atlas)
	elseif fallback then
		texture:SetTexture(fallback, nil, nil, "TRILINEAR")
	end
end

function Util.FormatTime(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

-- Sound und Taskleisten-Blinken für "Gruppe gefunden"-Momente
function Util.Alert(sound)
	if ns.addon.db.profile.general.sound then
		PlaySound(sound or SOUNDKIT.READY_CHECK, "Master")
	end
	FlashClientIcon()
end
