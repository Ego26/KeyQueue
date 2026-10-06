-- Search: Gruppen suchen, filtern, bewerben - die Ein-Knopf-Queue der Spieler-Seite
-- Phase 0: Search, ApplyToGroup und CancelApplication brauchen je einen Klick, Ergebnisse lesen
-- geht frei. Keystufe und Gruppenname sind für Addons nicht lesbar (Name wird nur angezeigt).
local _, ns = ...

local KeyQueue = ns.addon
local L = ns.L
local Matcher, Util = ns.Matcher, ns.Util

local Search = KeyQueue:NewModule("Search", "AceEvent-3.0", "AceTimer-3.0")
ns.Search = Search

local CATEGORY_DUNGEONS = 2
local MAX_APPLICATIONS = MAX_LFG_LIST_APPLICATIONS or 5
local STALE_AFTER = 10 -- Sekunden, danach sucht der Queue-Knopf (bzw. die nächste Eingabe) neu
local REFRESH_AFTER = 15 -- Sekunden, danach lädt eine Eingabe die Liste automatisch neu
local MIN_SEARCH_GAP = 1 -- Sekunden zwischen zwei automatischen Suchen
local ACTIVE_APPLICATION = { applied = true, invited = true }

-- state: idle, searching, queued, found, joined
function Search:OnInitialize()
	self.state = "idle"
	self.groups = {}
	self.declined = {} -- Leader, die mich in dieser Sitzung abgelehnt haben
end

function Search:OnEnable()
	self:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED", "OnResults")
	self:RegisterEvent("INSPECT_READY", "OnInspectReady") -- auch Inspektionen anderer Addons mitnutzen
	self:RegisterEvent("LFG_LIST_SEARCH_FAILED", "OnSearchFailed")
	self:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED", "OnResultUpdated")
	self:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED", "OnApplicationStatus")
	self:RegisterEvent("PARTY_INVITE_REQUEST", "OnPartyInvite")
	self:RegisterMessage("KEYQUEUE_PLAYERS_UPDATE", "Refilter") -- Favoriten/Sperren geändert
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRosterUpdate")
	self:RestoreQueue()
end

-- Queue übersteht /reload: Startzeit liegt in db.char (Blizzards Bewerbungen laufen ohnehin weiter).
-- Nach mehr als einer Stunde oder in einer fremden Gruppe wird nichts wiederhergestellt.
function Search:RestoreQueue()
	local saved = KeyQueue.db.char.searchQueue
	if saved and saved.since and time() - saved.since < 3600
		and not (IsInGroup() and not UnitIsGroupLeader("player")) then
		self.queueStart = GetTime() - (time() - saved.since)
		self.state = "queued"
	else
		KeyQueue.db.char.searchQueue = nil
	end
end

-- Laufende Queue merken bzw. vergessen (bei jedem Statuswechsel)
function Search:SaveQueue()
	if self.queueStart then
		KeyQueue.db.char.searchQueue = { since = math.floor(time() - (GetTime() - self.queueStart)) }
	else
		KeyQueue.db.char.searchQueue = nil
	end
end

-- Um welchen Key geht es in meiner Gruppe? Rückgabe: Titel (Gruppenname, nur anzeigen - geschützter
-- |K-String), Dungeon. Quellen: die über KeyQueue gefundene Gruppe, sonst das aktive Listing der Gruppe.
-- Der Gruppenname ist ein Verweis aufs Listing: ist die Gruppe nicht mehr gelistet (z. B. voll),
-- zeigt WoW nur "Unbekannt" - dann keinen Titel, nur Dungeon und Leader.
-- Rückgabe: Titel oder nil, Dungeon, Name des Leaders (ohne Realm)
local function GroupLeaderName()
	for index = 1, GetNumSubgroupMembers() do
		local unit = "party" .. index
		if UnitIsGroupLeader(unit) then
			return Util.Readable(UnitName(unit))
		end
	end
	if UnitIsGroupLeader("player") then
		return Util.Readable(UnitName("player"))
	end
end

function Search:GetGroupKey()
	local leader = GroupLeaderName()
	local joined = self.joinedGroup
	if joined then
		local title
		local ok, info = pcall(C_LFGList.GetSearchResultInfo, joined.id)
		if ok and info and not Util.Readable(info.isDelisted) then
			title = joined.title
		end
		return title, joined.dungeon, leader
	end
	if C_LFGList.HasActiveEntryInfo() then
		local info = C_LFGList.GetActiveEntryInfo()
		local activityID = info and info.activityIDs and info.activityIDs[1]
		local activity = activityID and C_LFGList.GetActivityInfoTable(activityID)
		local dungeon = activity and Util.Readable(activity.fullName)
		return info and info.name, dungeon, leader
	end
	local saved = KeyQueue.db.char.joinedKey
	if saved and IsInGroup() then
		return nil, saved.dungeon, leader
	end
end

function Search:Update()
	self:SendMessage("KEYQUEUE_SEARCH_UPDATE")
end

-- Blizzard meldet nach einer Suche jede Gruppe einzeln (oft hunderte Meldungen hintereinander):
-- höchstens alle 0,2 s neu zeichnen statt bei jeder Meldung - sonst baut die Oberfläche pro Sekunde
-- dutzende Male alles neu und legt dabei Megabytes an Zwischendaten an
function Search:UpdateSoon()
	if self.updateTimer then
		return
	end
	self.updateTimer = self:ScheduleTimer(function()
		self.updateTimer = nil
		self:Update()
	end, 0.2)
end

function Search:IsQueued()
	return self.queueStart ~= nil
end

function Search:GetElapsed()
	return self.queueStart and (GetTime() - self.queueStart) or 0
end

function Search:SetState(state)
	self.state = state
	self:SaveQueue()
	if UnitIsGroupLeader("player") then
		ns.Comm:SendQueueState(state, self:GetElapsed())
	end
	self:Update()
end

-- Party-Mitglieder (nicht Leader) können nicht selbst suchen
-- Gruppen anschauen darf jeder, auch Party-Mitglieder (Bewerben nur der Leader, siehe CanQueue)
function Search:CanBrowse()
	return true
end

function Search:CanQueue()
	return not IsInGroup() or UnitIsGroupLeader("player")
end

---------------------------------------------------------------------------
-- Dungeons der Saison
---------------------------------------------------------------------------

function Search:GetDungeons()
	if self.dungeons and #self.dungeons > 0 then
		return self.dungeons
	end
	local list, seen = {}, {}
	for _, activityID in ipairs(C_LFGList.GetAvailableActivities(CATEGORY_DUNGEONS) or {}) do
		local info = C_LFGList.GetActivityInfoTable(activityID)
		local groupID = info and info.groupFinderActivityGroupID
		if info and info.isMythicPlusActivity and groupID and not seen[groupID] then
			seen[groupID] = true
			local name = C_LFGList.GetActivityGroupInfo(groupID)
			table.insert(list, { groupID = groupID, activityID = activityID, name = name or info.shortName or info.fullName })
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	self.dungeons = list
	return list
end

function Search:GetDungeonName(groupID)
	for _, dungeon in ipairs(self:GetDungeons()) do
		if dungeon.groupID == groupID then
			return dungeon.name
		end
	end
end

---------------------------------------------------------------------------
-- Suchen (Klick)
---------------------------------------------------------------------------

-- Experten-Ausdruck nur bei Änderung neu übersetzen; ungültig = kein Ausdrucksfilter
function Search:GetExpression()
	local text = KeyQueue.db.profile.search.expression or ""
	if text ~= self.expressionText then
		self.expressionText = text
		self.expression, self.expressionError, self.expressionDetail = Matcher.CompileExpression(text)
	end
	return self.expression
end

-- Matchmaking-Queue (Panel, ohne eigenen Key): KeyQueue-Gruppen und - am Anfang, solange wenige KeyQueue
-- haben - normale Gruppen. Keystufe wie bei Blizzard über den Suchtext (ohne: nur Keys, die etwas bringen),
-- Leader im Wertungsfenster (wächst mit der Wartezeit), Mindestwertung für den Leader
function Search:GetMatchCriteria()
	local queue = KeyQueue.db.profile.queue
	local low, high = Util.ParseLevelRange(Util.GetBlizzardSearchText())
	return {
		matchmaking = true,
		includeNormal = queue.includeNormal ~= false,
		levelLow = low,
		levelHigh = high,
		bestRuns = Util.GetMyBestRuns(),
		minLeaderScore = queue.minScore,
		ratingCenter = Util.GetMyScore(),
		ratingWindow = ns.Matchmaker.Window({ queuedAt = self.matchStartServer }, GetServerTime()),
		hideDeclined = true,
		noLeaver = true,
	}
end

function Search:GetCriteria()
	if self.matchmaking then
		return self:GetMatchCriteria()
	end
	local options = KeyQueue.db.profile.search
	return {
		activityGroups = options.activityGroups,
		minLeaderScore = options.minLeaderScore,
		maxLeaderScore = options.maxLeaderScore,
		onlyKeyQueue = options.onlyKeyQueue,
		bloodlust = options.bloodlust,
		battleRez = options.battleRez,
		hasTank = options.hasTank,
		hasHealer = options.hasHealer,
		notMyClass = options.notMyClass,
		noLeaver = options.noLeaver,
		hideDeclined = options.hideDeclined,
		leaderTimed = options.leaderTimed,
		playstyles = options.playstyles,
		membersMin = options.membersMin, membersMax = options.membersMax,
		tanksMin = options.tanksMin, tanksMax = options.tanksMax,
		healersMin = options.healersMin, healersMax = options.healersMax,
		dpsMin = options.dpsMin, dpsMax = options.dpsMax,
		maxAge = options.maxAge,
		expression = self:GetExpression(),
	}
end

---------------------------------------------------------------------------
-- Keystufe: Gruppennamen sind für Addons gesperrt (|K-Strings). Filtern kann nur Blizzards
-- Server-Suche über den Text im Blizzard-Suchfeld ("13-18") - und nur, wenn der Spieler ihn selbst
-- tippt (ingame getestet: per Addon eingefügter Text wird ignoriert). Deshalb zeigt der Such-Tab
-- Blizzards echtes Suchfeld eingebettet an (SearchTab:EmbedBlizzardSearchBox).
---------------------------------------------------------------------------

-- Enter im eingebetteten Blizzard-Suchfeld: Blizzard sucht selbst, KeyQueue übernimmt die Ergebnisse
-- (startet keine Queue - das macht weiter nur der goldene Knopf)
function Search:AdoptBlizzardSearch()
	if not self:CanBrowse() then
		return
	end
	-- Enter im Keystufen-Feld: auch ein leeres Feld ist eine bewusste Wahl
	KeyQueue.db.profile.search.lastLevel = Util.GetBlizzardSearchText() ~= "" and Util.GetBlizzardSearchText() or nil
	self.lastSearch = GetTime()
	self.searchedSignature = self:GetSearchSignature()
	self:BeginSearch()
end

-- Alles, was in die Suchanfrage selbst eingeht (ändert es sich, muss neu gesucht werden)
function Search:GetSearchSignature()
	local options = KeyQueue.db.profile.search
	-- ohne Keystufe: die wird nur per Enter oder "Suchen" gesucht, nie automatisch (Tippfehler,
	-- Blizzards Drosselung)
	local parts = { Util.GetMyRole() or "", tostring(IsInGroup()),
		tostring(options.hasTank), tostring(options.hasHealer) }
	local groups = {}
	for groupID, selected in pairs(options.activityGroups) do
		if selected then
			table.insert(groups, groupID)
		end
	end
	table.sort(groups)
	table.insert(parts, table.concat(groups, ","))
	for index = 1, 4 do
		table.insert(parts, options.playstyles[index] and "1" or "0")
	end
	return table.concat(parts, "|")
end

-- Keystufe zurücksetzen (Filter "Leeren"): Blizzard-Suchfeld leeren und neu suchen lassen
-- Keystufe merken: Blizzard leert sein Suchfeld bei /reload, KeyQueue zeigt den letzten Wert dann
-- an der Pille an (wiederherstellen kann nur der Spieler selbst - das Feld ist für Addons gesperrt)
function Search:RememberLevel()
	local text = Util.GetBlizzardSearchText()
	if text ~= "" then
		KeyQueue.db.profile.search.lastLevel = text
	end
end

function Search:ClearLevel()
	KeyQueue.db.profile.search.lastLevel = nil
	C_LFGList.ClearSearchTextFields()
	wipe(self.groups)
	self.lastSearch = nil
	self:Update()
end

-- Notlösung, falls das Einbetten nicht geht: Blizzards Gruppenfinder bei "Dungeons" öffnen,
-- Cursor im Suchfeld. Muss aus einem OnClick kommen.
function Search:OpenBlizzardSearch()
	if InCombatLockdown() or not (PVEFrame_ShowFrame and LFGListFrame) then
		return
	end
	PVEFrame_ShowFrame("GroupFinderFrame", "LFGListPVEStub")
	local selection = LFGListFrame.CategorySelection
	LFGListCategorySelection_SelectCategory(selection, GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2, 0)
	LFGListCategorySelection_StartFindGroup(selection)
	LFGListFrame.SearchPanel.SearchBox:SetFocus()
end

-- Muss direkt aus einem OnClick kommen
-- browse = nur Liste aktualisieren (Aktualisieren-Knopf), ohne eine Queue zu starten
function Search:DoSearch(browse)
	local options = KeyQueue.db.profile.search
	local activities = {}
	for groupID, selected in pairs(options.activityGroups) do
		if selected and groupID ~= 0 then -- 0 = "keiner gewählt"
			table.insert(activities, groupID)
		end
	end

	-- Blizzards erweiterter Filter: nur M+, gewählte Dungeons, solo nur Gruppen mit Platz für meine Rolle
	local solo = not IsInGroup()
	local tank, healer, damage = Util.RoleFlags(Util.GetMyRole())
	local playstyles = options.playstyles
	if self.matchmaking then
		-- Matchmaking: Stufe und Leader prüft KeyQueue selbst (Kennzeichen), Blizzard liefert alle M+-Gruppen
		activities, playstyles = {}, {}
		tank, healer, damage = false, false, false
	end
	local advanced = {
		needsTank = solo and tank, needsHealer = solo and healer, needsDamage = solo and damage,
		needsMyClass = false, hasTank = options.hasTank and true or false, hasHealer = options.hasHealer and true or false,
		activities = activities, minimumRating = 0,
		difficultyNormal = false, difficultyHeroic = false, difficultyMythic = false, difficultyMythicPlus = true,
		generalPlaystyle1 = playstyles[1] and true or false, generalPlaystyle2 = playstyles[2] and true or false,
		generalPlaystyle3 = playstyles[3] and true or false, generalPlaystyle4 = playstyles[4] and true or false,
	}

	C_LFGList.Search(CATEGORY_DUNGEONS, 0, 0, C_LFGList.GetLanguageSearchFilter(), nil, advanced)
	self:RememberLevel()
	self.lastSearch = GetTime()
	self.searchedSignature = self:GetSearchSignature()
	if not browse then
		self.queueStart = self.queueStart or GetTime()
	end
	self:BeginSearch()
end

-- Ohne Queue (nur Liste aktualisieren) bleibt die Oberfläche ruhig: kein "Suche läuft", die alte
-- Liste bleibt stehen, bis die neuen Ergebnisse da sind - sonst flattern Knopf, Status und Liste.
function Search:BeginSearch()
	if self:IsQueued() then
		self:SetState("searching")
	else
		self.browsePending = true
	end
end

function Search:OnResults()
	if self.state == "idle" and not self.browsePending then
		return -- Suche kam nicht von KeyQueue
	end
	self.browsePending = nil
	self.quietFailure = nil
	self.throttledAt = nil
	self:RememberLevel() -- Suche mit Keystufe (auch per Enter im Blizzard-Feld): Stufe merken
	self:ReadResults()
	if self.state == "searching" then
		self:SetState(self:IsQueued() and "queued" or "idle")
	else
		self:Update()
	end
end

function Search:OnSearchFailed(_, reason)
	if self.state == "searching" or self.browsePending then
		self.browsePending = nil
		reason = Util.Readable(reason)
		if reason == "throttled" then
			-- Blizzard bremst zu schnelle Suchen: kein Chat, Hinweis in der Liste; die nächste
			-- Eingabe (Klick, Enter) sucht erneut, weil die Suche als "nicht erledigt" gilt
			self.throttledAt = GetTime()
			self.searchedSignature = nil
			self.lastSearch = nil
		elseif not self.quietFailure then
			KeyQueue:Msg(L["SEARCH_FAILED"]:format(tostring(reason or "?")))
		end
		self.quietFailure = nil
		if self.state == "searching" then
			self:SetState(self:IsQueued() and "queued" or "idle")
		else
			self:Update()
		end
	end
end

function Search:OnResultUpdated(_, resultID)
	for index, group in ipairs(self.groups) do
		if group.id == resultID then
			local updated = self:SafeReadGroup(resultID) or group
			if updated.delisted then
				table.remove(self.groups, index) -- nicht mehr gelistet: aus der Liste nehmen
			else
				self.groups[index] = updated
				self:Evaluate(updated)
			end
			self:UpdateSoon()
			return
		end
	end
end

-- Liste frisch halten: neu suchen, wenn sie älter als REFRESH_AFTER ist. Search braucht eine echte
-- Eingabe - aufgerufen aus Klicks (Fenster öffnen, Tab "Suchen") und Tastendruck/Klick in die Welt.
-- typing = Tastendruck im Keystufen-Feld: sofort suchen, auch wenn noch eine Suche läuft
-- (die neueste Suche ersetzt die alte)
function Search:AutoRefresh(typing)
	if not self:CanBrowse() or InCombatLockdown() then
		return false
	end
	local changed = self.searchedSignature ~= self:GetSearchSignature()
	if typing then
		if not changed then
			return false
		end
	else
		if self.state == "searching" or self.browsePending then
			return false
		end
		local since = self.lastSearch and GetTime() - self.lastSearch
		if since and (since < MIN_SEARCH_GAP or (not changed and since < REFRESH_AFTER)) then
			return false
		end
	end
	self.quietFailure = true -- automatische Suche: kein Chat-Hinweis, wenn Blizzard sie ablehnt
	self:DoSearch(not self:IsQueued())
	return true
end

---------------------------------------------------------------------------
-- Ergebnisse lesen und filtern (ohne Klick)
---------------------------------------------------------------------------

-- Teile der Ergebnisse können geschützt sein (Midnight "Secret Values", z. B. in Instanzen):
-- eine unlesbare Gruppe überspringen statt die ganze Liste abzubrechen
function Search:SafeReadGroup(resultID)
	local ok, group = pcall(self.ReadGroup, self, resultID)
	return ok and group or nil
end

function Search:ReadGroup(resultID)
	local info = C_LFGList.GetSearchResultInfo(resultID)
	if not info then
		return nil
	end
	local activityID = info.activityIDs and info.activityIDs[1]
	local activity = activityID and C_LFGList.GetActivityInfoTable(activityID)
	if not (activity and activity.isMythicPlusActivity) then
		return nil
	end

	local counts = C_LFGList.GetSearchResultMemberCounts(resultID) or {}
	local members, classes, hasLeaver = {}, {}, false
	for index = 1, (Util.Readable(info.numMembers) or 0) do
		local player = C_LFGList.GetSearchResultPlayerInfo(resultID, index)
		local class = player and Util.Readable(player.classFilename)
		if class then
			table.insert(classes, class)
		end
		if player and Util.Readable(player.isLeaver) then
			hasLeaver = true
		end
		table.insert(members, {
			class = class,
			role = player and Util.Readable(player.assignedRole),
			specID = player and Util.SpecID(class, Util.Readable(player.specName)), -- für Melee/Ranged
			isLeader = player and Util.Readable(player.isLeader) and true or false,
			name = player and Util.Readable(player.name), -- meist nur bei Freunden/Gilde bekannt
		})
	end

	-- Erfahrung des Leaders in genau diesem Dungeon (wie Raider.IO, aber direkt von Blizzard)
	local dungeonInfo = type(info.leaderDungeonScoreInfo) == "table" and info.leaderDungeonScoreInfo[1]
	local leaderBestLevel = dungeonInfo and Util.Readable(dungeonInfo.bestRunLevel) or 0
	local leaderTimed = dungeonInfo and Util.Readable(dungeonInfo.finishedSuccess) and true or false
	local leaderName = Util.Readable(info.leaderName)
	-- bester Run des Leaders über alle Dungeons (für das Leader-Profil)
	local overall = type(info.leaderBestDungeonScoreInfo) == "table" and info.leaderBestDungeonScoreInfo
	local leaderOverallBest = overall and Util.Readable(overall.bestRunLevel) and {
		level = Util.Readable(overall.bestRunLevel),
		name = Util.Readable(overall.mapName),
		timed = Util.Readable(overall.finishedSuccess) and true or false,
	} or nil

	local requiredScore = Util.Readable(info.requiredDungeonScore) or 0
	local _, appStatus = C_LFGList.GetApplicationInfo(resultID)
	return {
		id = resultID,
		activityGroupID = activity.groupFinderActivityGroupID,
		challengeMapID = Util.ChallengeMapID(Util.Readable(activity.mapID)),
		dungeon = self:GetDungeonName(activity.groupFinderActivityGroupID) or activity.shortName or activity.fullName,
		title = info.name, -- geschützter |K-String: nur anzeigen, nicht auswerten
		comment = info.comment, -- Notiz des Leaders, ebenfalls nur anzeigen
		leaderName = leaderName,
		leaderFaction = Util.Readable(info.leaderFactionGroup), -- 0 Horde, 1 Allianz
		friends = (Util.Readable(info.numBNetFriends) or 0) + (Util.Readable(info.numCharFriends) or 0),
		guildMates = Util.Readable(info.numGuildMates) or 0,
		leaderBestLevel = leaderBestLevel,
		leaderOverallBest = leaderOverallBest,
		leaderTimed = leaderTimed,
		playstyle = Util.Readable(info.generalPlaystyle),
		hasLeaver = hasLeaver,
		declined = leaderName and self.declined[Util.NameKey(leaderName)] or false,
		numMembers = Util.Readable(info.numMembers) or #members,
		ageMinutes = math.floor((Util.Readable(info.age) or 0) / 60),
		autoAccept = Util.Readable(info.autoAccept) and true or false,
		hasVoice = type(Util.Readable(info.voiceChat)) == "string" and info.voiceChat ~= "",
		sameRealm = leaderName ~= nil and not leaderName:find("-", 1, true),
		leaderScore = Util.PlayerScore(leaderName, Util.Readable(info.leaderOverallDungeonScore)), -- RIO, sonst Blizzard
		requiredScore = requiredScore,
		requiredItemLevel = Util.Readable(info.requiredItemLevel) or 0,
		isKeyQueue = Matcher.IsMarkerScore(requiredScore),
		kqLevel = Matcher.DecodeMarkerLevel(requiredScore), -- Keystufe aus dem KQ-Kennzeichen (Name ist gesperrt)
		delisted = Util.Readable(info.isDelisted) and true or false,
		remaining = {
			TANK = Util.Readable(counts.TANK_REMAINING) or 0,
			HEALER = Util.Readable(counts.HEALER_REMAINING) or 0,
			DAMAGER = Util.Readable(counts.DAMAGER_REMAINING) or 0,
		},
		members = members,
		classes = classes,
		appStatus = appStatus or "none",
	}
end

-- Namen der Mitglieder nachladen: Blizzard liefert sie oft erst kurz nach den Suchergebnissen
function Search:RefreshMemberNames(group)
	if not group or not group.id then
		return
	end
	for index, member in ipairs(group.members or {}) do
		if not member.name then
			local info = C_LFGList.GetSearchResultPlayerInfo(group.id, index)
			member.name = info and Util.Readable(info.name)
		end
	end
end

function Search:Evaluate(group)
	local me = {
		roles = Util.GetPartyRoles(), classes = Util.GetGroupClasses(),
		score = Util.GetMyScore(), itemLevel = Util.GetMyItemLevel(),
	}
	local criteria = self:GetCriteria()
	group.matches, group.reason = Matcher.MatchGroup(criteria, group, me)
	-- Matchmaking solo: passt, wenn eine meiner Queue-Rollen Platz hat
	if self.matchmaking and not group.matches and group.reason == "NO_SPACE" and not IsInGroup() then
		for role in pairs(ns.Queue:GetRoles()) do
			me.roles = { role }
			group.matches, group.reason = Matcher.MatchGroup(criteria, group, me)
			if group.matches then
				break
			end
		end
	end
	-- gesperrte Leader nie bewerben
	if group.matches and group.leaderName and ns.History:IsBlocked(Util.NameKey(group.leaderName)) then
		group.matches, group.reason = false, "BLACKLIST"
	end
end

function Search:ReadResults()
	local _, results = C_LFGList.GetSearchResults()
	wipe(self.groups)
	for _, resultID in ipairs(results or {}) do
		local group = self:SafeReadGroup(resultID)
		if group and not group.delisted then
			self:Evaluate(group)
			table.insert(self.groups, group)
		end
	end
	self:Sort()
end

function Search:Sort()
	local matchmaking = self.matchmaking
	table.sort(self.groups, function(a, b)
		if (a.matches and true or false) ~= (b.matches and true or false) then
			return a.matches and true or false
		end
		-- Matchmaking: KeyQueue-Gruppen zuerst (die nehmen jeden, der passt), dann die Gruppe, die am
		-- längsten wartet (kein Vorrang für Favoriten)
		if matchmaking then
			if (a.isKeyQueue and true or false) ~= (b.isKeyQueue and true or false) then
				return a.isKeyQueue and true or false
			end
			if (a.ageMinutes or 0) ~= (b.ageMinutes or 0) then
				return (a.ageMinutes or 0) > (b.ageMinutes or 0)
			end
			return (a.id or 0) < (b.id or 0)
		end
		-- Gruppen von Favoriten zuerst (auch für Auto-Bewerben)
		local favA = a.leaderName and ns.History:IsFavorite(Util.NameKey(a.leaderName)) or false
		local favB = b.leaderName and ns.History:IsFavorite(Util.NameKey(b.leaderName)) or false
		if favA ~= favB then
			return favA
		end
		return Matcher.CompareGroups(a, b)
	end)
end

-- Filter geändert: vorhandene Ergebnisse neu bewerten, ohne neu zu suchen
function Search:Refilter()
	for _, group in ipairs(self.groups) do
		self:Evaluate(group)
	end
	self:Sort()
	self:Update()
end

function Search:CountMatches()
	local count = 0
	for _, group in ipairs(self.groups) do
		if group.matches then
			count = count + 1
		end
	end
	return count
end

function Search:CountApplications()
	local count = 0
	for _, resultID in ipairs(C_LFGList.GetApplications() or {}) do
		local _, appStatus, pendingStatus = C_LFGList.GetApplicationInfo(resultID)
		if ACTIVE_APPLICATION[pendingStatus or appStatus] then
			count = count + 1
		end
	end
	return count
end

-- Laufende Bewerbungen mit Gruppe: { { group = ..., status = "applied"/"invited" }, ... }
function Search:GetActiveApplications()
	local list = {}
	for _, resultID in ipairs(C_LFGList.GetApplications() or {}) do
		local _, appStatus, pendingStatus = C_LFGList.GetApplicationInfo(resultID)
		local status = pendingStatus or appStatus
		if ACTIVE_APPLICATION[status] and Util.IsMythicPlusResult(resultID) then -- nur M+ (Raids usw. nicht)
			local ok, group = pcall(self.FindGroup, self, resultID)
			if ok and group then
				table.insert(list, { group = group, status = status })
			end
		end
	end
	return list
end

function Search:GetNextCandidate()
	for _, group in ipairs(self.groups) do
		if group.matches and group.appStatus == "none" then
			return group
		end
	end
end

---------------------------------------------------------------------------
-- Der Queue-Knopf: jeder Klick macht den nächsten sinnvollen Schritt
---------------------------------------------------------------------------

-- search, apply, wait, blocked
function Search:GetNextAction()
	if not self:CanQueue() then
		return "blocked"
	end
	if self.state == "searching" then
		return "wait"
	end
	-- Ohne laufende Queue startet der Knopf immer erst eine neue Suche
	if not self:IsQueued() then
		return "search"
	end
	local stale = not self.lastSearch or GetTime() - self.lastSearch > STALE_AFTER
	local candidate = self:GetNextCandidate()
	if candidate and self:CountApplications() < MAX_APPLICATIONS then
		return "apply", candidate
	end
	if stale then
		return "search"
	end
	return "wait"
end

-- Auto-Bewerben: Bewerben und Suchen brauchen eine echte Eingabe. Während der Queue löst jeder
-- Tastendruck oder Klick in die Spielwelt den nächsten Schritt aus (höchstens einen pro Eingabe).
-- Rückgabe: true, wenn etwas passiert ist.
-- source: "key" oder "mouse" (siehe AutoInvite:OnInput); über Tasten blockierte Wege bleiben aus
function Search:OnHardwareEvent(source)
	if not self:CanQueue() or InCombatLockdown() or self.state == "found" or self.state == "joined" then
		return false
	end
	local invite = ns.AutoInvite
	local canSearch = invite:KeyAllowed(source, "Search")
	-- nicht in der Queue (oder Auto-Bewerben aus): nur die Liste frisch halten, solange "Suchen" offen ist
	if not self:IsQueued() or not (self.matchmaking or KeyQueue.db.profile.search.autoApply) then
		return false -- ohne Queue sucht KeyQueue nicht nebenbei (die Liste ist Blizzards eigene)
	end
	local action, candidate = self:GetNextAction()
	if action == "apply" and invite:KeyAllowed(source, "ApplyToGroup") then
		invite:MarkInput(source)
		self:Apply(candidate.id)
		return true
	elseif action == "search" and canSearch then
		invite:MarkInput(source)
		self:DoSearch()
		return true
	end
	return false
end

-- Matchmaking-Queue starten (Panel, ohne eigenen Key). Muss direkt aus einem OnClick kommen.
function Search:StartMatchmaking()
	self.matchmaking = true
	self.matchStartServer = GetServerTime()
	self.quietFailure = nil
	self.queueStart = GetTime()
	self:DoSearch()
end

-- Muss direkt aus einem OnClick kommen
function Search:QueueClick()
	local action, candidate = self:GetNextAction()
	if action == "search" then
		self.quietFailure = nil
		self:DoSearch()
	elseif action == "apply" then
		self:Apply(candidate.id)
		self:ApplyMore()
	end
end

-- Mit einem Klick gleich bei mehreren passenden Gruppen bewerben (bis zum Limit von 5).
-- Lässt Blizzard nur eine Bewerbung pro Klick zu, merkt sich KeyQueue das (multiBlocked) und
-- versucht es nicht wieder.
function Search:ApplyMore()
	if self.multiBlocked or not KeyQueue.db.profile.search.autoApply then
		return
	end
	self.inMultiApply = true
	-- selbst mitzählen: Blizzards Bewerbungsliste aktualisiert sich erst nach dem Klick
	local count = self:CountApplications()
	while count < MAX_APPLICATIONS and not self.multiBlocked do
		local candidate = self:GetNextCandidate()
		if not candidate then
			break
		end
		local tank, healer, damage = self:ApplyRoles()
		C_LFGList.ApplyToGroup(candidate.id, tank, healer, damage)
		candidate.appStatus = "applied" -- auch damit GetNextCandidate weiterzählt
		count = count + 1
	end
	self.inMultiApply = nil
	self:Update()
end

-- Rollen für die Anmeldung: im Matchmaking alle gewählten Queue-Rollen (der Leader-Matchmaker teilt
-- zu), sonst die Rolle der Spec
function Search:ApplyRoles()
	if self.matchmaking then
		local roles = ns.Queue:GetRoles()
		return roles.TANK or false, roles.HEALER or false, roles.DAMAGER or false
	end
	return Util.RoleFlags(Util.GetMyRole())
end

-- Muss direkt aus einem OnClick kommen
function Search:Apply(resultID)
	if self:CountApplications() >= MAX_APPLICATIONS then
		KeyQueue:Msg(L["SEARCH_MAX_APPLICATIONS"]:format(MAX_APPLICATIONS))
		return
	end
	local tank, healer, damage = self:ApplyRoles()
	C_LFGList.ApplyToGroup(resultID, tank, healer, damage)
	if self.appExpires then
		self.appExpires[resultID] = nil -- neue Anmeldung: Restzeit neu von Blizzard holen
	end
	self.queueStart = self.queueStart or GetTime()
	for _, group in ipairs(self.groups) do
		if group.id == resultID then
			group.appStatus = "applied"
		end
	end
	if self.state == "idle" then
		self:SetState("queued")
	else
		self:Update()
	end
end

-- Restzeit einer laufenden Anmeldung in Sekunden (Blizzard zieht sie danach automatisch zurück).
-- Blizzards Wert stammt vom letzten Server-Update und läuft nicht mit: das Ende wird einmal je Anmeldung
-- festgehalten, sonst springt der Zähler bei jedem Aktualisieren zurück.
function Search:GetApplicationRemaining(resultID)
	self.appExpires = self.appExpires or {}
	local expires = self.appExpires[resultID]
	if not expires then
		local ok, _, _, _, duration = pcall(C_LFGList.GetApplicationInfo, resultID)
		duration = ok and Util.Readable(duration)
		if type(duration) ~= "number" or duration <= 0 then
			return nil
		end
		expires = GetTime() + duration
		self.appExpires[resultID] = expires
	end
	return math.max(0, expires - GetTime())
end

-- Anmelden mit Rollen und Notiz: Blizzards eigenes Anmeldefenster (die Notiz steht in einem geschützten
-- Blizzard-Feld - nur dieses Fenster kann sie mitschicken). Angemeldet wird erst mit Blizzards Knopf
-- "Anmelden"; KeyQueue bekommt das über LFG_LIST_APPLICATION_STATUS_UPDATED mit.
function Search:ApplyWithNote(resultID)
	local dialog = _G.LFGListApplicationDialog
	if not (dialog and LFGListApplicationDialog_Show) or not pcall(LFGListApplicationDialog_Show, dialog, resultID) then
		self:Apply(resultID) -- Fenster nicht verfügbar: normal anmelden
	end
end

-- Eine einzelne Bewerbung zurückziehen (Klick auf "Beworben"). Muss direkt aus einem OnClick kommen.
function Search:Withdraw(resultID)
	C_LFGList.CancelApplication(resultID)
	for _, group in ipairs(self.groups) do
		if group.id == resultID then
			group.appStatus = "cancelled"
		end
	end
	self:Update()
end

-- Alle Bewerbungen zurückziehen und Queue beenden. Muss direkt aus einem OnClick kommen.
function Search:Cancel()
	for _, resultID in ipairs(C_LFGList.GetApplications() or {}) do
		local _, appStatus = C_LFGList.GetApplicationInfo(resultID)
		-- nur M+-Anmeldungen zurückziehen: Raids, Quests usw. gehören nicht zur Queue
		if appStatus == "applied" and Util.IsMythicPlusResult(resultID) then
			C_LFGList.CancelApplication(resultID)
		end
	end
	self.queueStart = nil
	self.matchmaking, self.matchStartServer = nil, nil
	self.found = nil
	self.lastSearch = nil
	wipe(self.groups) -- Queue verlassen: alte Treffer weg, Knopf zeigt wieder "Queue starten"
	self:SetState("idle")
	ns.FoundPopup:Hide()
end

---------------------------------------------------------------------------
-- Einladung und Beitritt
---------------------------------------------------------------------------

function Search:FindGroup(resultID)
	for _, group in ipairs(self.groups) do
		if group.id == resultID then
			return group
		end
	end
	return self:SafeReadGroup(resultID)
end

function Search:OnApplicationStatus(_, resultID, newStatus)
	if self.appExpires and newStatus ~= "applied" then
		self.appExpires[resultID] = nil
	end
	for _, group in ipairs(self.groups) do
		if group.id == resultID then
			group.appStatus = newStatus
			-- abgelehnt: diese Gruppe (Leader) auf Wunsch künftig ausblenden
			if newStatus == "declined" and group.leaderName then
				self.declined[Util.NameKey(group.leaderName)] = true
				group.declined = true
			end
		end
	end
	-- KeyQueue ist nur für M+: Anmeldungen und Einladungen für Raids, Quests, PvP usw. lässt es in Ruhe
	local mythicPlus = Util.IsMythicPlusResult(resultID)
	-- angemeldet ohne laufende Queue (z. B. mit Notiz über Blizzards Anmeldefenster): Queue startet mit
	if newStatus == "applied" and mythicPlus and not self:IsQueued() and self:CanQueue() then
		self.queueStart = GetTime()
		self:SetState("queued")
	end
	-- Blizzard-Invite (Leader ohne KeyQueue): Annehmen per Klick über AcceptInvite
	if newStatus == "invited" and mythicPlus and self:IsQueued() then
		self:ShowFound({ mode = "lfg", resultID = resultID, group = self:FindGroup(resultID) })
	end
	self:Update()
end

-- KQ-Leader laden per InviteUnit ein: das ist eine normale Gruppeneinladung
function Search:OnPartyInvite(_, inviter)
	if not self:IsQueued() or Util.IsSecret(inviter) then
		return
	end
	local inviterKey = Util.NameKey(inviter)
	local match
	for _, group in ipairs(self.groups) do
		if group.leaderName and Util.NameKey(group.leaderName) == inviterKey and group.appStatus ~= "none" then
			match = group
			break
		end
	end
	if not match then
		return -- Einladung hat nichts mit der Queue zu tun
	end

	if KeyQueue.db.profile.general.autoAccept then
		AcceptGroup()
		StaticPopup_Hide("PARTY_INVITE")
	end
	self:ShowFound({ mode = "party", inviter = inviter, group = match })
end

function Search:ShowFound(found)
	self.found = found
	self:SetState("found")
	Util.Alert(SOUNDKIT.READY_CHECK)
	ns.FoundPopup:Show(found)
end

-- Aus dem "Gruppe gefunden"-Popup. Muss direkt aus einem OnClick kommen.
function Search:AcceptFound()
	local found = self.found
	if not found then
		return
	end
	if found.mode == "lfg" then
		C_LFGList.AcceptInvite(found.resultID)
	else
		AcceptGroup()
		StaticPopup_Hide("PARTY_INVITE")
	end
end

function Search:DeclineFound()
	local found = self.found
	if not found then
		return
	end
	if found.mode == "lfg" then
		C_LFGList.DeclineInvite(found.resultID)
	else
		DeclineGroup()
		StaticPopup_Hide("PARTY_INVITE")
	end
	self.found = nil
	self:SetState(self:IsQueued() and "queued" or "idle")
end

function Search:OnRosterUpdate()
	-- In eine fremde Gruppe aufgenommen: Queue ist erledigt
	if self:IsQueued() and IsInGroup() and not UnitIsGroupLeader("player") then
		self.queueStart = nil
		self.matchmaking, self.matchStartServer = nil, nil
		-- Key der neuen Gruppe merken (Anzeige in "Deine Gruppe", Dungeon übersteht /reload)
		self.joinedGroup = self.found and self.found.group or nil
		KeyQueue.db.char.joinedKey = self.joinedGroup and { dungeon = self.joinedGroup.dungeon } or nil
		self.found = nil
		self.joinedAt = time() -- für die Key-History: Gruppe kam über KeyQueue
		ns.FoundPopup:Hide()
		KeyQueue:Msg(L["SEARCH_JOINED"])
		Util.Alert(SOUNDKIT.UI_GROUP_FINDER_RECEIVE_APPLICATION or SOUNDKIT.READY_CHECK)
		self:SetState("joined")
	elseif self.state == "joined" and not IsInGroup() then
		self.joinedGroup = nil
		KeyQueue.db.char.joinedKey = nil
		self:SetState("idle") -- Gruppe verlassen: bereit für die nächste Queue
	else
		self:Update()
	end
end

---------------------------------------------------------------------------
-- Inspizieren: Spec und Gegenstandsstufe der Gruppenmitglieder (wie Unit-Tooltips anderer Addons).
-- WoW liefert sie erst nach NotifyInspect (Spieler in Reichweite). Eine Anfrage nach der anderen,
-- Ergebnis pro GUID gemerkt, damit nicht ständig neu gefragt wird.
---------------------------------------------------------------------------

local INSPECT_GAP, INSPECT_TIMEOUT, INSPECT_KEEP = 1.5, 6, 300

Search.inspected = {} -- [guid] = { specID, itemLevel, at }

function Search:GetInspected(unit)
	local guid = Util.Readable(UnitGUID(unit))
	return guid and self.inspected[guid]
end

-- Mitglieder ohne frische Daten anfragen (aufgerufen von der Gruppen-Ansicht)
function Search:RequestInspect(units)
	self.inspectQueue = self.inspectQueue or {}
	local now = GetTime()
	for _, unit in ipairs(units) do
		local guid = Util.Readable(UnitGUID(unit))
		local known = guid and self.inspected[guid]
		-- ohne Gegenstandsstufe (z. B. außer Reichweite) nach 20 s erneut versuchen
		local fresh = known and now - known.at < (known.itemLevel and INSPECT_KEEP or 20)
		if guid and not UnitIsUnit(unit, "player") and not fresh then
			local queued = false
			for _, entry in ipairs(self.inspectQueue) do
				queued = queued or entry.guid == guid
			end
			if not queued then
				table.insert(self.inspectQueue, { unit = unit, guid = guid })
			end
		end
	end
	if self.inspectTimer then
		return -- läuft schon
	end
	self:InspectNext()
end

function Search:InspectNext()
	self.inspectTimer = nil
	if self.inspecting and GetTime() - self.inspecting.at < INSPECT_TIMEOUT then
		return
	end
	self.inspecting = nil
	local queue = self.inspectQueue or {}
	-- nicht stören: im Kampf oder wenn der Spieler selbst gerade jemanden inspiziert
	if #queue == 0 or InCombatLockdown() or (InspectFrame and InspectFrame:IsShown()) then
		return
	end
	local entry = table.remove(queue, 1)
	if UnitExists(entry.unit) and Util.Readable(UnitGUID(entry.unit)) == entry.guid
		and CanInspect(entry.unit) and UnitIsConnected(entry.unit) then
		self.inspecting = { unit = entry.unit, guid = entry.guid, at = GetTime() }
		NotifyInspect(entry.unit)
	end
	if #queue > 0 or self.inspecting then
		self.inspectTimer = self:ScheduleTimer("InspectNext", INSPECT_GAP)
	end
end

-- Gruppen-Unit zu einer GUID (Inspektionen anderer Addons wie Oilvl/DBM nutzen wir mit)
local function UnitForGUID(guid)
	local prefix, count = "party", GetNumSubgroupMembers()
	if IsInRaid() then
		prefix, count = "raid", GetNumGroupMembers()
	end
	for index = 1, count do
		local unit = prefix .. index
		if Util.Readable(UnitGUID(unit)) == guid then
			return unit
		end
	end
end

-- Durchschnitts-Gegenstandsstufe aus den angelegten Gegenständen (falls Blizzards Wert fehlt)
local SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
local function ComputeItemLevel(unit)
	local total, count, mainHandTwoHand = 0, 0, false
	for _, slot in ipairs(SLOTS) do
		local link = GetInventoryItemLink(unit, slot)
		if link then
			local level = C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
			level = Util.Readable(level)
			if not level then
				return nil -- noch nicht geladen
			end
			total, count = total + level, count + 1
			if slot == 16 then
				local equipLoc = C_Item.GetItemInfoInstant and select(4, C_Item.GetItemInfoInstant(link))
				mainHandTwoHand = equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT"
				if mainHandTwoHand and not GetInventoryItemLink(unit, 17) then
					total, count = total + level, count + 1 -- Zweihänder zählt doppelt
				end
			end
		end
	end
	if count < 10 then
		return nil -- zu wenige Gegenstände sichtbar
	end
	return total / 16
end

function Search:OnInspectReady(_, guid)
	local mine = self.inspecting and self.inspecting.guid == guid
	local unit = mine and self.inspecting.unit or UnitForGUID(guid)
	if not unit then
		return
	end
	local specID = Util.Readable(GetInspectSpecialization(unit))
	local data = self.inspected[guid] or {}
	data.specID = (specID or 0) > 0 and specID or data.specID
	data.at = GetTime()
	self.inspected[guid] = data
	if mine then
		self.inspecting = nil
	end
	-- Gegenstandsstufe kommt oft erst, wenn alle Gegenstände geladen sind: kurz mehrmals nachlesen
	self.reading = self.reading or {}
	self.reading[guid] = { unit = unit, tries = 0, clear = mine }
	self:ReadInspectItemLevel()
	self:SendMessage("KEYQUEUE_INSPECT_UPDATE")
end

function Search:ReadInspectItemLevel()
	local pending = false
	for guid, entry in pairs(self.reading or {}) do
		entry.tries = entry.tries + 1
		local itemLevel = C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel
			and Util.Readable(C_PaperDollInfo.GetInspectItemLevel(entry.unit))
		if (itemLevel or 0) <= 0 then
			itemLevel = ComputeItemLevel(entry.unit)
		end
		if (itemLevel or 0) > 0 or entry.tries >= 8 then
			if (itemLevel or 0) > 0 and self.inspected[guid] then
				self.inspected[guid].itemLevel = itemLevel
			end
			self.reading[guid] = nil
			-- nur eigene Inspektion zurücksetzen (andere Addons lesen ihre selbst)
			if entry.clear and ClearInspectPlayer then
				ClearInspectPlayer()
			end
			self:SendMessage("KEYQUEUE_INSPECT_UPDATE")
		else
			pending = true
		end
	end
	if pending and not self.readTimer then
		self.readTimer = self:ScheduleTimer(function()
			self.readTimer = nil
			self:ReadInspectItemLevel()
		end, 0.4)
	end
end
