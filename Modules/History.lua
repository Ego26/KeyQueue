-- History: Key-History - jeder M+-Lauf mit Ergebnis, Gruppe und Leavern
-- Erfasst beim Start die Gruppe, markiert Mitspieler, die vor dem Ende gehen, und speichert am Ende
-- Zeit, Ergebnis (+1/+2/+3, Zeit überschritten, abgebrochen), Tode und Score vorher/nachher.
local _, ns = ...

local KeyQueue = ns.addon
local L = ns.L
local Util = ns.Util

local History = KeyQueue:NewModule("History", "AceEvent-3.0", "AceTimer-3.0")
ns.History = History

local MAX_RUNS = 500
local STALE_AFTER = 3 * 60 * 60   -- laufender Key, der so alt ist, gilt als abgebrochen
local VIA_QUEUE_WINDOW = 3 * 60 * 60 -- Gruppe kam über KeyQueue, wenn so kurz vorher beigetreten/gelistet

-- status: running, timed, depleted, abandoned

local function ShortName(key)
	return key and key:match("^[^%-]+") or key
end

-- Mitspieler eines Keys über GUID oder Namen finden (Name mit/ohne Realm zählt als gleich)
function History:FindMember(run, guid, key)
	for _, member in ipairs(run.members) do
		if (guid and member.guid == guid) or member.key == key or ShortName(member.key) == ShortName(key) then
			return member
		end
	end
end

-- Doppelte Einträge zusammenführen (ältere Daten: derselbe Spieler einmal mit, einmal ohne Realm)
function History:MergeDuplicates(run)
	local merged, byShort = {}, {}
	for _, member in ipairs(run.members) do
		local short = ShortName(member.key)
		local existing = short and byShort[short]
		if existing then
			existing.class = existing.class or member.class
			existing.role = existing.role or member.role
			existing.specID = existing.specID or member.specID
			existing.guid = existing.guid or member.guid
			existing.left = existing.left or member.left
		else
			table.insert(merged, member)
			if short then
				byShort[short] = member
			end
		end
	end
	run.members = merged
end

function History:OnEnable()
	self.runs = KeyQueue.db.global.history
	for _, run in ipairs(self.runs) do
		self:MergeDuplicates(run)
	end
	self:RegisterEvent("CHALLENGE_MODE_START", "OnStart")
	self:RegisterEvent("CHALLENGE_MODE_COMPLETED", "OnCompleted")
	self:RegisterEvent("CHALLENGE_MODE_RESET", "OnReset")
	self:RegisterEvent("CHALLENGE_MODE_DEATH_COUNT_UPDATED", "OnDeaths")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRoster")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
	if C_DamageMeter then
		self:RegisterEvent("DAMAGE_METER_RESET", "OnMeterReset")
	end
	self:CloseStaleRuns()
	-- Klasse jedes eingeloggten Charakters merken: auch ältere Runs bekommen so die Klassenfarbe
	local key = self:MyKey()
	if key then
		KeyQueue.db.global.characters[key] = select(2, UnitClass("player"))
	end
end

function History:CharacterClass(run)
	return run.characterClass or KeyQueue.db.global.characters[run.character or ""]
end

function History:Update()
	self:SendMessage("KEYQUEUE_HISTORY_UPDATE")
end

function History:MyKey()
	return Util.NameKey(GetUnitName("player", true))
end

-- Laufender Key dieses Charakters
function History:GetCurrent()
	local me = self:MyKey()
	for index = #self.runs, 1, -1 do
		local run = self.runs[index]
		if run.status == "running" and run.character == me then
			return run
		end
	end
end

function History:CloseStaleRuns()
	local now = time()
	for _, run in ipairs(self.runs) do
		if run.status == "running" and now - (run.startedAt or now) > STALE_AFTER then
			run.status = "abandoned"
		end
	end
end

---------------------------------------------------------------------------
-- Aufzeichnen
---------------------------------------------------------------------------

function History:SnapshotMembers()
	local members = {}
	for index = 1, GetNumSubgroupMembers() do
		local unit = "party" .. index
		local name = Util.Readable(GetUnitName(unit, true))
		if name then
			local specID = GetInspectSpecialization and Util.Readable(GetInspectSpecialization(unit)) or 0
			local role = Util.Readable(UnitGroupRolesAssigned(unit))
			table.insert(members, {
				name = name,
				key = Util.NameKey(name),
				guid = Util.Readable(UnitGUID(unit)),
				class = Util.Readable(UnitClassBase(unit)),
				role = (role == "TANK" or role == "HEALER" or role == "DAMAGER") and role or nil,
				specID = specID and specID > 0 and specID or nil,
			})
		end
	end
	return members
end

-- Kam die Gruppe über KeyQueue zustande? (als Spieler beigetreten oder als Leader eingeladen)
function History:WasViaKeyQueue()
	local now = time()
	if ns.Search.joinedAt and now - ns.Search.joinedAt < VIA_QUEUE_WINDOW then
		return true
	end
	local session = ns.AutoInvite.session
	return session.listedAt ~= nil and now - session.listedAt < VIA_QUEUE_WINDOW and next(session.joined) ~= nil
end

function History:NewRun(mapID, level)
	local name, _, timeLimit, texture
	if mapID then
		name, _, timeLimit, texture = C_ChallengeMode.GetMapUIInfo(mapID)
	end
	local run = {
		id = time(),
		character = self:MyKey(),
		characterClass = select(2, UnitClass("player")),
		characterRole = Util.GetMyRole(),
		characterSpec = select(2, Util.GetMySpecIcon()), -- für das scharfe Spec-Symbol in der History
		mapID = mapID,
		name = name or "?",
		texture = texture,
		timeLimit = timeLimit,
		level = level or 0,
		startedAt = time(),
		status = "running",
		deaths = 0,
		scoreBefore = Util.GetMyScore(),
		viaKeyQueue = self:WasViaKeyQueue(),
		members = self:SnapshotMembers(),
	}
	-- Affixe des Keys (Zahlen, nach dem Spielen nicht mehr abfragbar)
	local _, affixIDs = C_ChallengeMode.GetActiveKeystoneInfo()
	if type(affixIDs) == "table" then
		run.affixes = {}
		for _, affixID in ipairs(affixIDs) do
			local id = Util.Readable(affixID)
			if id then
				table.insert(run.affixes, id)
			end
		end
	end
	table.insert(self.runs, run)
	while #self.runs > MAX_RUNS do
		table.remove(self.runs, 1)
	end
	return run
end

function History:OnStart(_, eventMapID)
	local mapID = C_ChallengeMode.GetActiveChallengeMapID() or eventMapID
	local level = C_ChallengeMode.GetActiveKeystoneInfo()
	local current = self:GetCurrent()
	-- Doppelte Starts (z. B. nach /reload) nicht als neuen Key zählen
	if current and current.mapID == mapID and time() - current.startedAt < STALE_AFTER then
		return
	end
	if current then
		current.status = "abandoned"
	end
	local run = self:NewRun(mapID, level)
	self:CaptureBaseline(run)
	self:Update()
end

function History:ReadDeaths(run)
	local deaths, timeLost = C_ChallengeMode.GetDeathCount()
	run.deaths = Util.Readable(deaths) or run.deaths
	run.timeLost = Util.Readable(timeLost) or run.timeLost
end

function History:OnDeaths()
	local run = self:GetCurrent()
	if run then
		self:ReadDeaths(run)
	end
end

-- Wer während des Keys die Gruppe verlässt, ist ein Leaver (Disconnects bleiben in der Gruppe)
function History:OnRoster()
	local run = self:GetCurrent()
	-- Habe ich selbst die Gruppe verlassen, sind die anderen keine Leaver
	if not run or not IsInGroup() then
		return
	end
	local roster = Util.GetRosterKeys()
	local changed = false
	for _, member in ipairs(run.members) do
		local present = member.key and roster[member.key] or false
		if not present and not member.left then
			member.left = true
			changed = true
		elseif present and member.left then
			member.left = nil -- wieder da
			changed = true
		end
	end
	-- Ersatz, der während des Keys dazukommt, ebenfalls erfassen
	for _, member in ipairs(self:SnapshotMembers()) do
		local known = false
		for _, existing in ipairs(run.members) do
			if existing.key == member.key then
				known = true
			end
		end
		if not known then
			member.joinedLate = true
			table.insert(run.members, member)
			changed = true
		end
	end
	if changed then
		self:Update()
	end
end

function History:OnCompleted()
	Util.InvalidateMyRuns() -- eigene Runs/Saison neu abfragen (sonst zwischengespeichert)
	local info = C_ChallengeMode.GetChallengeCompletionInfo and C_ChallengeMode.GetChallengeCompletionInfo()
	if not info then
		return
	end
	local run = self:GetCurrent() or self:NewRun(Util.Readable(info.mapChallengeModeID), Util.Readable(info.level))

	local duration = Util.Readable(info.time) or 0
	run.duration = duration > 100000 and duration / 1000 or duration -- Millisekunden
	run.level = Util.Readable(info.level) or run.level
	run.onTime = Util.Readable(info.onTime) and true or false
	run.upgrade = Util.Readable(info.keystoneUpgradeLevels) or 0
	run.status = run.onTime and "timed" or "depleted"
	run.scoreBefore = Util.Readable(info.oldOverallDungeonScore) or run.scoreBefore
	run.scoreAfter = Util.Readable(info.newOverallDungeonScore) or Util.GetMyScore()
	run.mapRecord = Util.Readable(info.isMapRecord) and true or nil
	run.affixRecord = Util.Readable(info.isAffixRecord) and true or nil
	self:ReadDeaths(run)
	run.endedAt = time()

	-- Namen aus der Abschlussliste ergänzen, falls beim Start nichts lesbar war. Blizzard schreibt
	-- Namen dort mal mit, mal ohne Realm - deshalb über GUID bzw. Kurznamen zuordnen.
	local me = self:MyKey()
	for _, member in ipairs(info.members or {}) do
		local name = Util.Readable(member.name)
		local key = Util.NameKey(name)
		if key and key ~= me and ShortName(key) ~= ShortName(me) then
			local existing = self:FindMember(run, Util.Readable(member.memberGUID), key)
			if existing then
				existing.guid = existing.guid or Util.Readable(member.memberGUID)
			else
				table.insert(run.members, { name = name, key = key, guid = Util.Readable(member.memberGUID) })
			end
		end
	end
	self:MergeDuplicates(run)
	self:StartStatsCapture(run)
	self:Update()
	self:SendMessage("KEYQUEUE_RUN_COMPLETED", run.id) -- z. B. Bewertungsfenster "Wie war's?"
end

function History:GetRun(runId)
	for _, run in ipairs(self.runs) do
		if run.id == runId then
			return run
		end
	end
end

function History:OnReset()
	local run = self:GetCurrent()
	if run then
		run.status = "abandoned"
		run.endedAt = time()
		self:StartStatsCapture(run)
		self:Update()
	end
end

-- Dungeon verlassen, ohne dass der Key fertig ist: abgebrochen
function History:OnEnteringWorld()
	self:ScheduleTimer("CheckStillActive", 5)
end

function History:CheckStillActive()
	local run = self:GetCurrent()
	if run and not C_ChallengeMode.IsChallengeModeActive() and not IsInInstance() then
		run.status = "abandoned"
		run.endedAt = time()
		self:StartStatsCapture(run)
		self:Update()
	end
end

---------------------------------------------------------------------------
-- Run-Statistik aus Blizzards Damage-Meter (ab 12.0): im Kampf geheim, danach lesbar.
-- Gesamtwerte ("Overall") beim Start merken und am Ende abziehen = Werte nur dieses Keys.
---------------------------------------------------------------------------

History.STAT_FIELDS = {
	damage = "DamageDone", healing = "HealingDone", absorbs = "Absorbs", interrupts = "Interrupts",
	dispels = "Dispels", taken = "DamageTaken", avoidable = "AvoidableDamageTaken", deaths = "Deaths",
}
local CAPTURE_TRIES, CAPTURE_INTERVAL = 24, 5 -- bis zu 2 Minuten warten, bis der Kampf vorbei ist

local function MeterReady()
	if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType and Enum and Enum.DamageMeterType
		and Enum.DamageMeterSessionType) then
		return false
	end
	if C_DamageMeter.IsDamageMeterAvailable and not C_DamageMeter.IsDamageMeterAvailable() then
		return false
	end
	return not InCombatLockdown()
end

-- { duration = s, players = { [guid] = { name, class, damage, healing, ... } } } oder nil (geheim/aus)
function History:ReadMeter()
	if not MeterReady() then
		return nil
	end
	local overall = Enum.DamageMeterSessionType.Overall
	local result = { players = {} }
	for field, typeName in pairs(self.STAT_FIELDS) do
		local meterType = Enum.DamageMeterType[typeName]
		if meterType then
			local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, overall, meterType)
			if not ok or type(session) ~= "table" then
				return nil
			end
			for _, source in ipairs(session.combatSources or {}) do
				local guid = Util.Readable(source.sourceGUID)
				local amount = Util.Readable(source.totalAmount)
				if guid and amount == nil then
					return nil -- noch geheim
				end
				if guid then
					local player = result.players[guid]
					if not player then
						player = { name = Util.Readable(source.name), class = Util.Readable(source.classFilename) }
						result.players[guid] = player
					end
					if field == "deaths" then
						-- Tode: jeder Tod ist ein eigener Eintrag (totalAmount ist dort 0) - mitzählen
						player.deaths = (player.deaths or 0) + math.max(1, amount or 0)
					else
						player[field] = amount
						-- Blizzards eigener Wert pro Sekunde (genau die Zahl aus dem Damage-Meter)
						if field == "damage" or field == "healing" or field == "absorbs" then
							player[field .. "PS"] = Util.Readable(source.amountPerSecond)
						end
					end
				end
			end
		end
	end
	local ok, duration = pcall(C_DamageMeter.GetSessionDurationSeconds, overall)
	result.duration = ok and Util.Readable(duration) or nil
	return result
end

-- Blizzards Meter wurde zurückgesetzt (z. B. automatisch zum Key-Start): alte Ausgangswerte gelten
-- nicht mehr - ab jetzt zählt alles, was der Meter zeigt
function History:OnMeterReset()
	local run = self:GetCurrent()
	if run and run.status == "running" then
		run.meterBase = { players = {}, duration = 0 }
	end
end

-- DPS bzw. HPS (Heilung + Absorb) eines Spielers: Blizzards eigener Wert, wenn vorhanden, sonst
-- Summe / Kampfzeit (bei älteren Keys oder wenn vom Gesamtwert abgezogen werden musste)
function History.OutputPerSecond(values, healer, seconds)
	if healer and values.healingPS then
		return values.healingPS + (values.absorbsPS or 0)
	elseif not healer and values.damagePS then
		return values.damagePS
	end
	local total = healer and (values.healing or 0) + (values.absorbs or 0) or (values.damage or 0)
	return total / math.max(1, seconds or 1)
end

-- Ausgangswerte beim Start (vor dem ersten Pull ist niemand im Kampf)
function History:CaptureBaseline(run)
	local meter = self:ReadMeter()
	if meter then
		run.meterBase = meter
	end
end

function History:StartStatsCapture(run)
	if run.stats or not C_DamageMeter then
		return
	end
	self.captureRun, self.captureTries = run, 0
	if not self.captureTimer then
		self.captureTimer = self:ScheduleRepeatingTimer("TryCaptureStats", CAPTURE_INTERVAL)
	end
	self:TryCaptureStats()
end

function History:StopCapture()
	if self.captureTimer then
		self:CancelTimer(self.captureTimer)
		self.captureTimer = nil
	end
	self.captureRun = nil
end

function History:TryCaptureStats()
	local run = self.captureRun
	if not run or run.stats then
		return self:StopCapture()
	end
	self.captureTries = self.captureTries + 1
	local meter = self:ReadMeter()
	if meter then
		self:StoreStats(run, meter)
		self:StopCapture()
		self:Update()
	elseif self.captureTries >= CAPTURE_TRIES then
		self:StopCapture()
	end
end

function History:StoreStats(run, meter)
	local base = run.meterBase
	-- Meter zwischendurch zurückgesetzt (Spieler oder Blizzard): Werte gelten dann ab dem Reset.
	-- Erkennbar an kürzerer Dauer oder daran, dass ein Spieler am Ende weniger hat als am Start.
	local reset = not base or (meter.duration and base.duration and meter.duration < base.duration)
	if base and not reset then
		for guid, values in pairs(meter.players) do
			local before = base.players[guid]
			if before and ((values.damage or 0) < (before.damage or 0) or (values.healing or 0) < (before.healing or 0)) then
				reset = true
				break
			end
		end
	end
	if reset then
		base = { players = {}, duration = 0 }
	end
	-- ohne Abzug (Meter zeigt nur diesen Key): Blizzards Werte pro Sekunde direkt übernehmen
	local exact = next(base.players) == nil
	local myGuid = Util.Readable(UnitGUID("player"))
	local stats = { players = {} }
	if meter.duration then
		stats.combatTime = math.max(0, meter.duration - (base.duration or 0))
	end
	for guid, values in pairs(meter.players) do
		local key
		if guid == myGuid then
			key = run.character
		else
			-- über GUID, sonst über den (nach dem Kampf lesbaren) Namen
			local short = values.name and ShortName(values.name)
			for _, member in ipairs(run.members) do
				if member.guid == guid or (not member.guid and short and ShortName(member.key) == short) then
					key = member.key
					member.guid = member.guid or guid
				end
			end
		end
		if key then
			local before = base.players[guid] or {}
			local entry = { class = values.class }
			for field in pairs(self.STAT_FIELDS) do
				entry[field] = math.max(0, (values[field] or 0) - (before[field] or 0))
			end
			if exact then
				entry.damagePS, entry.healingPS, entry.absorbsPS = values.damagePS, values.healingPS, values.absorbsPS
			end
			stats.players[key] = entry
		end
	end
	if next(stats.players) then
		run.stats = stats
	end
	run.meterBase = nil
end

---------------------------------------------------------------------------
-- Auswertung
---------------------------------------------------------------------------

-- Wie oft bin ich mit diesem Spieler gelaufen, wie oft davon in time?
function History:GetPlayerStats(key)
	local runs, timed, left = 0, 0, 0
	if not key then
		return runs, timed, left
	end
	for _, run in ipairs(self.runs) do
		for _, member in ipairs(run.members) do
			if member.key == key then
				runs = runs + 1
				if run.status == "timed" then
					timed = timed + 1
				end
				if member.left then
					left = left + 1
				end
				break
			end
		end
	end
	return runs, timed, left
end

-- "4x zusammen, 3x in time" für Bewerber-Feed und Trefferliste
function History:StatsText(name)
	local runs, timed, left = self:GetPlayerStats(Util.NameKey(name))
	if runs == 0 then
		return nil
	end
	local text = L["HISTORY_TOGETHER"]:format(runs, timed)
	if left > 0 then
		text = text .. "  " .. L["HISTORY_LEFT_COUNT"]:format(left)
	end
	return text
end

-- Liste für die Anzeige, neueste zuerst; optional nur dieser Charakter
function History:GetRuns(onlyMe)
	local me = self:MyKey()
	local list = {}
	for index = #self.runs, 1, -1 do
		local run = self.runs[index]
		if not onlyMe or run.character == me then
			table.insert(list, run)
		end
	end
	return list
end

function History:GetSummary(runs)
	local finished, timed, levels, leavers = 0, 0, 0, 0
	for _, run in ipairs(runs) do
		if run.status ~= "running" then
			finished = finished + 1
			levels = levels + (run.level or 0)
			if run.status == "timed" then
				timed = timed + 1
			end
		end
		for _, member in ipairs(run.members) do
			if member.left then
				leavers = leavers + 1
			end
		end
	end
	return {
		count = finished,
		timedPercent = finished > 0 and math.floor(timed / finished * 100 + 0.5) or 0,
		averageLevel = finished > 0 and levels / finished or 0,
		leavers = leavers,
	}
end

---------------------------------------------------------------------------
-- Spieler: Favoriten, Sperren, Notizen, Profil
---------------------------------------------------------------------------

function History:IsFavorite(key)
	return key ~= nil and KeyQueue.db.global.favorites[key] == true
end

function History:IsBlocked(key)
	return key ~= nil and KeyQueue.db.global.blacklist[key] == true
end

function History:PlayersChanged()
	self:SendMessage("KEYQUEUE_PLAYERS_UPDATE")
	self:Update()
	ns.AutoInvite:Retry() -- Favoriten/Sperren wirken sofort aufs Einladen
end

function History:SetFavorite(key, value)
	if key then
		KeyQueue.db.global.favorites[key] = value and true or nil
		if value then
			KeyQueue.db.global.blacklist[key] = nil
		end
		self:PlayersChanged()
	end
end

function History:SetBlocked(key, value)
	if key then
		KeyQueue.db.global.blacklist[key] = value and true or nil
		if value then
			KeyQueue.db.global.favorites[key] = nil
		end
		self:PlayersChanged()
	end
end

function History:GetNote(key)
	return key and KeyQueue.db.global.notes[key] or ""
end

function History:SetNote(key, text)
	if key then
		KeyQueue.db.global.notes[key] = (text and text ~= "") and text or nil
	end
end

--[[
Profil eines Spielers über alle gemeinsamen Keys (alle eigenen Charaktere):
{ key, class, role, count, timed, depleted, abandoned, left, best, lastSeen, runs = { neueste zuerst },
  avg = { interrupts, dispels, deaths, avoidable, output, outputRole } (nur Keys mit Damage-Meter-Werten) }
Für einen eigenen Charakter zählen seine eigenen Keys.
]]
function History:GetProfile(key)
	local profile = { key = key, count = 0, timed = 0, depleted = 0, abandoned = 0, left = 0, best = 0, runs = {} }
	local sums, statRuns = { interrupts = 0, dispels = 0, deaths = 0, avoidable = 0, output = 0 }, 0
	for index = #self.runs, 1, -1 do
		local run = self.runs[index]
		local found
		if run.character == key then
			found = { class = self:CharacterClass(run), role = run.characterRole }
		else
			for _, member in ipairs(run.members) do
				if member.key == key then
					found = member
					break
				end
			end
		end
		if found then
			profile.count = profile.count + 1
			profile.class = profile.class or found.class
			profile.role = profile.role or found.role
			profile.lastSeen = profile.lastSeen or run.startedAt
			table.insert(profile.runs, run)
			if run.status == "timed" then
				profile.timed = profile.timed + 1
				profile.best = math.max(profile.best, run.level or 0)
			elseif run.status == "depleted" then
				profile.depleted = profile.depleted + 1
			elseif run.status == "abandoned" then
				profile.abandoned = profile.abandoned + 1
			end
			if found.left then
				profile.left = profile.left + 1
			end
			local values = run.stats and run.stats.players[key]
			if values then
				statRuns = statRuns + 1
				local seconds = (run.stats.combatTime and run.stats.combatTime > 0) and run.stats.combatTime or run.duration or 1
				local healer = found.role == "HEALER"
				sums.output = sums.output + History.OutputPerSecond(values, healer, seconds)
				sums.interrupts = sums.interrupts + (values.interrupts or 0)
				sums.dispels = sums.dispels + (values.dispels or 0)
				sums.deaths = sums.deaths + (values.deaths or 0)
				sums.avoidable = sums.avoidable + (values.avoidable or 0)
			end
		end
	end
	if statRuns > 0 then
		profile.avg = { runs = statRuns, outputRole = profile.role == "HEALER" and "HPS" or "DPS" }
		for field, value in pairs(sums) do
			profile.avg[field] = value / statRuns
		end
	end
	return profile
end

-- Alle Leaver eines Keys auf die Sperrliste
function History:BlockLeavers(run)
	local blacklist = KeyQueue.db.global.blacklist
	for _, member in ipairs(run.members) do
		if member.left and member.key then
			blacklist[member.key] = true
			KeyQueue.db.global.favorites[member.key] = nil
		end
	end
	self:Update()
end

function History:HasUnblockedLeaver(run)
	local blacklist = KeyQueue.db.global.blacklist
	for _, member in ipairs(run.members) do
		if member.left and member.key and not blacklist[member.key] then
			return true
		end
	end
	return false
end
