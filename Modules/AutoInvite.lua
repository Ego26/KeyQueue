-- AutoInvite: Bewerber prüfen und passende sofort per InviteUnit einladen (Leader-Seite)
-- Phase 0: InviteUnit geht ohne Klick, Bewerberdaten sind lesbar. Gruppen-Bewerbungen
-- lädt der Leader per Klick ein (InviteApplicant). Im Kampf warten Invites auf das Kampfende.
local _, ns = ...

local KeyQueue = ns.addon
local L = ns.L
local Matcher, Util = ns.Matcher, ns.Util

local AutoInvite = KeyQueue:NewModule("AutoInvite", "AceEvent-3.0", "AceTimer-3.0")
ns.AutoInvite = AutoInvite

local PENDING_TIMEOUT = 90
local MAX_GROUP_SIZE = 5

-- Bewerbungsstatus, nach denen ein Bewerber nicht mehr kommt
local FINISHED = {
	cancelled = true, declined = true, declined_full = true, declined_delisted = true,
	failed = true, invitedeclined = true, timedout = true,
}

-- Feed-Status: new, invited, queued, joined, declined, gone, party, match, rejected
-- "match" = passt, wartet auf einen Klick des Leaders (Auto-Invite aus oder andere Fraktion)

local FAILED_INVITE_WINDOW = 3 -- Sekunden: Fehlermeldung gehört zum gerade verschickten Invite

-- factionGroup kommt als Zahl (0 Horde, 1 Allianz); unbekannt = gleiche Fraktion annehmen
local function IsOtherFaction(factionGroup)
	if factionGroup == nil then
		return false
	end
	local faction = type(factionGroup) == "number" and PLAYER_FACTION_GROUP and PLAYER_FACTION_GROUP[factionGroup] or factionGroup
	local mine = UnitFactionGroup("player")
	return type(faction) == "string" and mine ~= nil and faction ~= mine
end

function AutoInvite:OnInitialize()
	self.feed = {}  -- applicantID -> Eintrag
	self.order = {} -- Reihenfolge des Eingangs ("wer zuerst passt")
end

function AutoInvite:OnEnable()
	self.session = KeyQueue.db.char.leaderSession

	self:RegisterEvent("LFG_LIST_APPLICANT_LIST_UPDATED", "Process")
	self:RegisterEvent("LFG_LIST_APPLICANT_UPDATED", "Process")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "SyncRoster")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "SendQueued")
	self:RegisterEvent("CHAT_MSG_SYSTEM", "OnSystemMessage")
	self:RegisterEvent("UI_ERROR_MESSAGE", "OnInviteError")
	self:RegisterEvent("ADDON_ACTION_BLOCKED", "OnActionBlocked")
	self:ScheduleRepeatingTimer("CheckPending", 5)
	self:CreateKeyCatcher()

	self.factionErrors = {}
	for _, text in ipairs({ ERR_PLAYER_WRONG_FACTION, ERR_TARGET_UNFRIENDLY, ERR_INVITE_UNFRIENDLY_S }) do
		if type(text) == "string" then
			self.factionErrors[text] = true
		end
	end

	self.failPatterns = {}
	for _, format in ipairs({ ERR_DECLINE_GROUP_S, ERR_ALREADY_IN_GROUP_S, ERR_BAD_PLAYER_NAME_S }) do
		if type(format) == "string" then
			table.insert(self.failPatterns, Util.FormatToPattern(format))
		end
	end
end

-- paused: der Matchmaking-Test listet einen echten Key und lädt nur seinen Testpartner ein - der normale
-- Auto-Invite darf dann keine fremden Bewerber einladen
function AutoInvite:IsActive()
	return self.session.active and not self.paused and C_LFGList.HasActiveEntryInfo()
end

function AutoInvite:Update()
	self:SendMessage("KEYQUEUE_LEADER_UPDATE")
end

---------------------------------------------------------------------------
-- Sitzung (ein Listing)
---------------------------------------------------------------------------

function AutoInvite:ReadNeeds()
	-- Matchmaking-Queue (Key eingebracht): volles Team (1/1/3) minus die eigene Gruppe
	if ns.Queue and ns.Queue:IsLeading() then
		local needs = { TANK = 1, HEALER = 1, DAMAGER = 3 }
		for _, role in ipairs(Util.GetPartyRoles()) do
			needs[role] = math.max(0, (needs[role] or 0) - 1)
		end
		return needs
	end
	local options = KeyQueue.db.profile.leader
	return {
		TANK = options.needTank and 1 or 0,
		HEALER = options.needHealer and 1 or 0,
		DAMAGER = options.needDamager or 0,
	}
end

function AutoInvite:BeginSession()
	local session = self.session
	session.active = true
	session.needs = self:ReadNeeds()
	session.pending = {}
	session.joined = {}
	session.listedAt = time()
	wipe(self.feed)
	wipe(self.order)
	self:Process()
end

function AutoInvite:EndSession()
	self.session.active = false
	-- nicht mehr gelistet: alte Anmeldungen weg (Liste im Tab "Erstellen" ist wieder leer)
	wipe(self.feed)
	wipe(self.order)
	self:Update()
end

-- Bedarf live ändern (Chips im Leader-Tab, während gelistet)
function AutoInvite:ApplyNeeds()
	if self.session.active then
		self.session.needs = self:ReadNeeds()
		self:Retry()
	end
end

-- Abgelehnte erneut prüfen, z. B. nach geändertem Bedarf oder einer Absage
function AutoInvite:Retry()
	for _, entry in pairs(self.feed) do
		if entry.status == "rejected" or entry.status == "match" then
			entry.status = "new"
		end
	end
	self:Process()
end

function AutoInvite:GetOpenSlots()
	local session = self.session
	local open = {}
	for _, role in ipairs(Matcher.ROLES) do
		open[role] = (session.needs or {})[role] or 0
	end
	for _, list in ipairs({ session.pending, session.joined }) do
		for _, member in pairs(list) do
			if member.role then
				open[member.role] = (open[member.role] or 0) - 1
			end
		end
	end
	return open
end

function AutoInvite:CountPending()
	local count = 0
	for _ in pairs(self.session.pending) do
		count = count + 1
	end
	return count
end

function AutoInvite:GetFreeSeats()
	return MAX_GROUP_SIZE - math.max(1, GetNumGroupMembers()) - self:CountPending()
end

function AutoInvite:GetGroupClasses()
	local classes = Util.GetGroupClasses()
	for _, member in pairs(self.session.pending) do
		if member.class then
			table.insert(classes, member.class)
		end
	end
	return classes
end

---------------------------------------------------------------------------
-- Bewerber
---------------------------------------------------------------------------

local MEMBER_FIELDS = { "name", "key", "class", "itemLevel", "score", "specID", "assignedRole", "roles", "relationship",
	"here" }

-- Bester Run des Bewerbers genau im gelisteten Dungeon (wie Blizzards "Bestleistung für Dungeon"):
-- { level, timed }, level 0 = dort noch nie; nil = Blizzard verrät es nicht
local function ReadHere(applicantID, index, activityID)
	if not activityID or not C_LFGList.GetApplicantDungeonScoreForListing then
		return nil
	end
	local ok, info = pcall(C_LFGList.GetApplicantDungeonScoreForListing, applicantID, index, activityID)
	if not ok or type(info) ~= "table" then
		return nil
	end
	local level = Util.Readable(info.bestRunLevel)
	if type(level) ~= "number" then
		return nil
	end
	return { level = level, timed = level > 0 and Util.Readable(info.finishedSuccess) == true }
end

-- Raider.IO als Rückfall, wenn Blizzard keinen Run im Dungeon kennt: bester Run dort { level, timed }
local function RaiderIOHere(name, mapID)
	local mplus = mapID and Util.GetRaiderIOProfile(name)
	for _, entry in ipairs(mplus and mplus.sortedDungeons or {}) do
		if entry.dungeon and entry.dungeon.keystone_instance == mapID and (entry.level or 0) > 0 then
			return { level = entry.level, timed = (entry.chests or 0) > 0 }
		end
	end
end

local function ReadMember(applicantID, index, activityID, mapID)
	local name, class, _, _, itemLevel, _, tank, healer, damage, assignedRole, relationship, dungeonScore, _, factionGroup, _,
		specID = C_LFGList.GetApplicantMemberInfo(applicantID, index)
	if not name or Util.IsSecret(name) then
		return nil -- Daten kommen noch
	end
	local member = {
		name = name,
		key = Util.NameKey(name),
		class = Util.Readable(class),
		itemLevel = Util.Readable(itemLevel) or 0,
		score = Util.PlayerScore(name, Util.Readable(dungeonScore)), -- RIO, sonst Blizzard
		specID = Util.Readable(specID),
		assignedRole = Util.Readable(assignedRole),
		roles = {
			TANK = Util.Readable(tank) and true or false,
			HEALER = Util.Readable(healer) and true or false,
			DAMAGER = Util.Readable(damage) and true or false,
		},
		-- Andere Fraktion: InviteUnit scheitert ("feindlich gesonnen"), nur InviteApplicant geht
		crossFaction = IsOtherFaction(Util.Readable(factionGroup)),
		-- "friend" (Freund, auch Battle.net) oder "guild" (Gildenmitglied), sonst nil
		relationship = Util.Readable(relationship),
		here = ReadHere(applicantID, index, activityID),
	}
	-- Blizzard kennt keinen Run dort: Raider.IO fragen (zählt auch für den Auto-Invite-Filter)
	if not (member.here and member.here.level > 0) then
		member.here = RaiderIOHere(name, mapID) or member.here
	end
	return member
end

-- Andere Fraktion oder Gruppen-Bewerbung: nur InviteApplicant, und das braucht eine Eingabe des Leaders
local function NeedsClick(entry)
	return entry.crossFaction or (entry.numMembers or 1) > 1
end

function AutoInvite:ReadApplicant(applicantID)
	local info = C_LFGList.GetApplicantInfo(applicantID)
	if not info then
		return nil
	end

	local entry = self.feed[applicantID]
	if not entry then
		entry = { id = applicantID, status = "new" }
		self.feed[applicantID] = entry
		table.insert(self.order, applicantID)
	end
	entry.appStatus = info.pendingApplicationStatus or info.applicationStatus
	entry.numMembers = info.numMembers or 1

	-- alle Mitglieder lesen (Gruppen-Bewerbung: bis zu 4); das erste steht für den Eintrag
	if not entry.members or #entry.members < entry.numMembers then
		local members = {}
		local activityID, mapID = ns.Listing:GetListedDungeon()
		for index = 1, entry.numMembers do
			local member = ReadMember(applicantID, index, activityID, mapID)
			if not member then
				break
			end
			members[index] = member
		end
		if not members[1] then
			return nil
		end
		entry.members = members
		for _, field in ipairs(MEMBER_FIELDS) do
			entry[field] = members[1][field]
		end
		entry.crossFaction = false
		for _, member in ipairs(members) do
			entry.crossFaction = entry.crossFaction or member.crossFaction
		end
		-- jetzt vollständig: Gruppen-Bewerbung neu prüfen
		if entry.status == "party" and #members == entry.numMembers then
			entry.status = "new"
		end
		-- nach /reload: schon eingeladen?
		if self.session.pending[entry.key] then
			entry.status = "invited"
			entry.role = self.session.pending[entry.key].role
		end
	end

	if FINISHED[entry.appStatus] then
		self:OnApplicantGone(entry)
	end
	return entry
end

-- Plätze für alle Mitglieder eines Eintrags reservieren bzw. freigeben
function AutoInvite:Reserve(entry)
	for index, member in ipairs(entry.members or { entry }) do
		local role = entry.assignment and entry.assignment[index] or (index == 1 and entry.role) or member.assignedRole
		self.session.pending[member.key] = { role = role, class = member.class, at = time() }
	end
end

function AutoInvite:Release(entry)
	local released = false
	for _, member in ipairs(entry.members or { entry }) do
		if member.key and self.session.pending[member.key] then
			self.session.pending[member.key] = nil
			released = true
		end
	end
	return released
end

function AutoInvite:OnApplicantGone(entry)
	-- Beitritt beendet die Bewerbung auch - wer schon in der Gruppe ist, hat nicht abgesagt
	local roster = Util.GetRosterKeys()
	if self:InRoster(entry, roster) then
		self:MarkJoined(entry, roster)
	elseif self:Release(entry) then
		entry.status = "declined"
	elseif entry.status ~= "joined" and entry.status ~= "declined" then
		entry.status = "gone"
	end
end

local function IsBlocked(entry, blacklist)
	for _, member in ipairs(entry.members or { entry }) do
		if member.key and blacklist[member.key] then
			return true
		end
	end
	return false
end

-- Eingangsreihenfolge, aber bevorzugt: erst Bewerbungen mit einem Favoriten, dann mit einem Freund
-- (auch Battle.net) oder Gildenmitglied, dann alle anderen. Eingeladen wird trotzdem nur, wer die
-- Kriterien erfüllt - die Reihenfolge entscheidet nur, wer bei mehreren Passenden zuerst dran ist.
function AutoInvite:GetOrder()
	-- Matchmaking: wer zuerst kam, zuerst - Favoriten, Freunde und Gilde ohne Vorrang
	if ns.Queue and ns.Queue:IsLeading() then
		local order = {}
		for _, applicantID in ipairs(self.order) do
			table.insert(order, applicantID)
		end
		return order
	end
	local tiers = { {}, {}, {} }
	for _, applicantID in ipairs(self.order) do
		local entry = self.feed[applicantID]
		local tier = 3
		for _, member in ipairs(entry and (entry.members or { entry }) or {}) do
			if ns.History:IsFavorite(member.key) then
				tier = 1
			elseif (member.relationship == "friend" or member.relationship == "guild") and tier > 2 then
				tier = 2
			end
		end
		table.insert(tiers[tier], applicantID)
	end
	local order = tiers[1]
	for tier = 2, 3 do
		for _, applicantID in ipairs(tiers[tier]) do
			table.insert(order, applicantID)
		end
	end
	return order
end

function AutoInvite:Process()
	if not self:IsActive() then
		self:Update()
		return
	end

	local options = KeyQueue.db.profile.leader
	local blacklist = KeyQueue.db.global.blacklist
	local leading = ns.Queue and ns.Queue:IsLeading()
	local autoInvite = leading or options.autoInvite
	local criteria
	if leading then
		-- Matchmaking: Mindestwertung der Queue, Bewerber im Wertungsfenster um mich (wächst mit der Zeit)
		criteria = {
			minScore = KeyQueue.db.profile.queue.minScore,
			ratingCenter = Util.GetMyScore(),
			ratingWindow = ns.Matchmaker.Window({ queuedAt = ns.Queue.startedServer }, GetServerTime()),
		}
	else
		criteria = {
			minScore = options.minScore,
			maxScore = options.maxScore,
			minItemLevel = options.minItemLevel,
			minTimedHere = options.minTimedHere,
			needBloodlust = options.needBloodlust,
			needBattleRez = options.needBattleRez,
		}
	end

	for _, applicantID in ipairs(C_LFGList.GetApplicants() or {}) do
		self:ReadApplicant(applicantID)
	end

	-- in Eingangsreihenfolge prüfen: wer zuerst passt, wird zuerst eingeladen.
	-- "match" wird jedes Mal neu geprüft - sonst lädt ein späterer Klick ein, obwohl die Rolle
	-- inzwischen besetzt ist. Wartet ein früherer Bewerber auf die Eingabe des Leaders (andere
	-- Fraktion, Gruppe), hält er seinen Platz eine Weile: Spätere füllen ihn nicht vorher auf.
	local now = GetTime()
	local held = { roles = {}, seats = 0, classes = {} }
	for _, applicantID in ipairs(self:GetOrder()) do
		local entry = self.feed[applicantID]
		if entry and entry.name and (entry.status == "new" or entry.status == "match") and entry.appStatus == "applied" then
			if IsBlocked(entry, blacklist) then
				entry.status, entry.reason = "rejected", "BLACKLIST"
			elseif self:GetFreeSeats() - held.seats < (entry.numMembers or 1) then
				entry.status, entry.reason = "rejected", "GROUP_FULL"
			else
				local open = self:GetOpenSlots()
				for role, count in pairs(held.roles) do
					open[role] = (open[role] or 0) - count
				end
				local classes = self:GetGroupClasses()
				for _, class in ipairs(held.classes) do
					table.insert(classes, class)
				end
				local state = { open = open, classes = classes }
				local ok, result = Matcher.Evaluate(criteria, state, entry)
				if not ok then
					entry.status = result == "PARTY" and "party" or "rejected"
					entry.reason = result
				else
					if type(result) == "table" then
						entry.assignment, entry.role = result, result[1]
					else
						entry.role = result
					end
					if autoInvite and not NeedsClick(entry) then
						self:Invite(entry)
					else
						-- wartet auf eine Eingabe: Zeilenknopf oder nächster Tastendruck (siehe OnHardwareEvent)
						entry.status = "match"
						if autoInvite then
							-- 0 = Platz bleibt, bis der Leader bestätigt oder überspringt (keine Fraktion wird benachteiligt)
							local hold = options.holdSeconds or 0
							entry.holdUntil = entry.holdUntil or (hold > 0 and now + hold or math.huge)
							if self:IsHolding(entry, now) then
								self:AddHold(held, entry)
							end
							self:AlertClick(entry)
						end
					end
				end
			end
		end
	end
	self:Update()
end

-- Platz gehalten: passt, wartet auf die Eingabe des Leaders, Haltezeit läuft noch, nicht übersprungen
function AutoInvite:IsHolding(entry, now)
	return entry.status == "match" and entry.holdUntil ~= nil and entry.holdUntil > (now or GetTime())
		and not entry.skipped
end

function AutoInvite:AddHold(held, entry)
	for index, member in ipairs(entry.members or { entry }) do
		local role = entry.assignment and entry.assignment[index] or (index == 1 and entry.role) or member.assignedRole
		if role then
			held.roles[role] = (held.roles[role] or 0) + 1
		end
		held.seats = held.seats + 1
		if member.class then
			table.insert(held.classes, member.class)
		end
	end
end

-- Haltezeit abgelaufen: Platz für Spätere freigeben (einmal pro Eintrag)
function AutoInvite:CheckHolds()
	local now, expired = GetTime(), false
	for _, entry in pairs(self.feed) do
		if entry.status == "match" and entry.holdUntil and entry.holdUntil <= now and not entry.holdExpired then
			entry.holdExpired = true
			expired = true
		end
	end
	if expired then
		self:Retry()
	end
end

function AutoInvite:Invite(entry)
	self:Reserve(entry)
	if InCombatLockdown() then
		entry.status = "queued"
		return
	end
	self:SendInvite(entry)
end

function AutoInvite:SendInvite(entry)
	C_PartyInfo.InviteUnit(entry.name)
	entry.status = "invited"
	entry.invitedAt = GetTime()
	KeyQueue:Msg(L["LEADER_INVITED"]:format(Util.ClassName(entry.name, entry.class)))
end

-- Passt, braucht aber eine Eingabe: Chat-Hinweis (Ton und Popup kommen vom InvitePopup)
function AutoInvite:AlertClick(entry)
	if not entry.alerted then
		entry.alerted = true
		local name = Util.ClassName(entry.name, entry.class)
		if (entry.numMembers or 1) > 1 then
			KeyQueue:Msg(L["LEADER_CLICK_NEEDED_PARTY"]:format(name, entry.numMembers))
		else
			KeyQueue:Msg(L["LEADER_CLICK_NEEDED"]:format(name))
		end
	end
end

-- Nächster Bewerber, der eine Eingabe braucht. onlyMatched: nur geprüfte (für den Tastendruck);
-- sonst auch Gruppen-Bewerbungen, deren Mitglieder noch nicht vollständig lesbar sind.
function AutoInvite:GetClickCandidate(onlyMatched)
	if not self:IsActive() then
		return nil
	end
	local free = self:GetFreeSeats()
	local party
	for _, applicantID in ipairs(self:GetOrder()) do
		local entry = self.feed[applicantID]
		if entry and entry.name and entry.appStatus == "applied" and (entry.numMembers or 1) <= free
			and not (onlyMatched and entry.skipped) then
			if entry.status == "match" then
				return entry
			elseif entry.status == "party" and not party and not onlyMatched then
				party = entry
			end
		end
	end
	return party
end

-- Zeilenknopf oder Tastendruck: direkt aus dem Eingabe-Handler.
-- Vorher mit dem aktuellen Stand neu prüfen (Process ruft nichts Geschütztes auf).
function AutoInvite:InviteCandidate(entry)
	self:Process()
	if entry.status ~= "match" and entry.status ~= "party" then
		return -- passt nicht mehr (z. B. Rolle inzwischen besetzt)
	end
	if entry.status == "party" then
		self:InviteParty(entry.id)
	else
		self:InviteMatch(entry.id)
	end
end

function AutoInvite:SendQueued()
	self:CreateKeyCatcher()
	for _, entry in pairs(self.feed) do
		if entry.status == "queued" then
			self:SendInvite(entry)
		end
	end
	self:Update()
end

-- Passender Bewerber per Eingabe: gleiche Fraktion per InviteUnit, sonst über die Blizzard-Bewerbung
function AutoInvite:InviteMatch(applicantID)
	local entry = self.feed[applicantID]
	if not entry or entry.status ~= "match" then
		return
	end
	if NeedsClick(entry) then
		C_LFGList.InviteApplicant(applicantID)
		entry.status = "invited"
		self:Reserve(entry)
		KeyQueue:Msg(L["LEADER_INVITED"]:format(Util.ClassName(entry.name, entry.class)))
	else
		self:Invite(entry)
	end
	self:Update()
end

-- Gruppen-Bewerbung ohne vollständige Daten: Leader entscheidet selbst (Klick)
function AutoInvite:InviteParty(applicantID)
	local entry = self.feed[applicantID]
	if entry then
		C_LFGList.InviteApplicant(applicantID)
		entry.status = "invited"
		self:Reserve(entry)
		self:Update()
	end
end

---------------------------------------------------------------------------
-- Eingabe des Leaders als Auslöser
---------------------------------------------------------------------------

-- InviteApplicant braucht eine Eingabe (Phase 0: aus Timern/Events blockiert). Jeder Tastendruck
-- des Leaders ist so eine Eingabe: ein unsichtbarer Frame hört mit, reicht die Taste unverändert
-- weiter und lädt dabei höchstens einen passenden Bewerber ein.
function AutoInvite:CreateKeyCatcher()
	if self.keyCatcher or InCombatLockdown() then
		return -- SetPropagateKeyboardInput ist im Kampf gesperrt; nach dem Kampf erneut
	end
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	-- erst weiterreichen, dann zuhören: schlägt das Weiterreichen fehl, darf der Frame
	-- keine Tasten bekommen (er würde sie sonst schlucken)
	frame:SetPropagateKeyboardInput(true)
	if frame.GetPropagateKeyboardInput and frame:GetPropagateKeyboardInput() == false then
		return
	end
	frame:EnableKeyboard(true)
	frame:SetScript("OnKeyDown", function()
		self:OnInput("key")
	end)
	self.keyCatcher = frame

	-- Mausklicks in die Spielwelt (Kamera drehen, Ziel wählen) zählen genauso
	if WorldFrame and not self.worldHooked then
		self.worldHooked = true
		WorldFrame:HookScript("OnMouseDown", function()
			self:OnInput("mouse")
		end)
	end
end

-- Eine echte Eingabe des Spielers: höchstens eine geschützte Aktion - zuerst Einladen (Leader),
-- sonst der nächste Schritt der Suche (Auto-Bewerben)
-- source: "key" (Tastendruck) oder "mouse" (Klick in die Spielwelt)
function AutoInvite:OnInput(source)
	if ns.Queue and ns.Queue:OnHardwareEvent(source) then
		return
	end
	if not self:OnHardwareEvent(source) then
		ns.Search:OnHardwareEvent(source)
	end
end

-- Lehnt Blizzard eine geschützte Aktion ab, die über einen Tastendruck kam, wird dieser Weg für die
-- Sitzung abgeschaltet (Mausklicks bleiben) - so entsteht keine Fehlerserie bei jeder Taste.
-- Einträge: [Funktionsname] = true, z. B. "Search", "ApplyToGroup", "InviteApplicant"
AutoInvite.keyBlocked = {}

function AutoInvite:MarkInput(source)
	self.lastKeyCall = source == "key" and GetTime() or nil
end

function AutoInvite:OnActionBlocked(_, addon, func)
	if addon ~= "KeyQueue" or type(func) ~= "string" then
		return
	end
	-- mehrere Bewerbungen in einem Klick abgelehnt: künftig nur eine pro Klick
	if ns.Search.inMultiApply and func:find("ApplyToGroup", 1, true) then
		ns.Search.multiBlocked = true
	end
	if not self.lastKeyCall or GetTime() - self.lastKeyCall > 1 then
		return
	end
	for _, name in ipairs({ "Search", "ApplyToGroup", "InviteApplicant", "CreateListing" }) do
		if func:find(name, 1, true) then
			self.keyBlocked[name] = true
		end
	end
end

function AutoInvite:KeyAllowed(source, name)
	return source ~= "key" or not self.keyBlocked[name]
end

function AutoInvite:OnHardwareEvent(source)
	local options = KeyQueue.db.profile.leader
	local leading = ns.Queue and ns.Queue:IsLeading()
	if self.paused or not (leading or (options.autoInvite and options.inviteOnKey)) or InCombatLockdown() then
		return false
	end
	if not self:KeyAllowed(source, "InviteApplicant") then
		return false
	end
	self:Process() -- erst aktueller Stand, dann höchstens einen einladen
	local entry = self:GetClickCandidate(true)
	if entry then
		self:MarkInput(source)
		self:InviteCandidate(entry)
		return true
	end
	return false
end

---------------------------------------------------------------------------
-- Gruppe, Absagen, Zeitüberschreitung
---------------------------------------------------------------------------

function AutoInvite:FindEntry(key)
	for _, entry in pairs(self.feed) do
		for _, member in ipairs(entry.members or { entry }) do
			if member.key == key then
				return entry
			end
		end
	end
end

function AutoInvite:InRoster(entry, roster)
	for _, member in ipairs(entry.members or { entry }) do
		if member.key and roster[member.key] then
			return true
		end
	end
	return false
end

-- Mitglieder in der Gruppe zählen als beigetreten (Platz bleibt belegt, Rolle wie reserviert)
function AutoInvite:MarkJoined(entry, roster)
	local session = self.session
	for index, member in ipairs(entry.members or { entry }) do
		if member.key and roster[member.key] and not session.joined[member.key] then
			local reserved = session.pending[member.key]
			local role = reserved and reserved.role or (entry.assignment and entry.assignment[index])
				or (index == 1 and entry.role) or member.assignedRole
			session.joined[member.key] = { role = role, class = member.class, at = time() }
			session.pending[member.key] = nil
			KeyQueue:Msg(L["LEADER_JOINED"]:format(Util.ClassName(member.name or member.key, member.class)))
		end
	end
	entry.status = "joined"
end

function AutoInvite:SyncRoster()
	local session = self.session
	local roster = Util.GetRosterKeys()
	-- Bewerber in der Gruppe: auch wenn Blizzard die Bewerbung vorher schon als beendet gemeldet hat
	-- oder das Listing beim Volllaufen schon geschlossen wurde
	for _, entry in pairs(self.feed) do
		if entry.status ~= "joined" and self:InRoster(entry, roster) then
			self:MarkJoined(entry, roster)
		end
	end
	if not session.active then
		self:Update()
		return
	end
	-- Reservierungen ohne Feed-Eintrag (z. B. nach /reload)
	for key, member in pairs(session.pending) do
		if roster[key] then
			session.joined[key] = member
			session.pending[key] = nil
			KeyQueue:Msg(L["LEADER_JOINED"]:format(key))
		end
	end
	-- Wer die Gruppe verlässt, macht seinen Platz wieder frei
	for key in pairs(session.joined) do
		if not roster[key] then
			session.joined[key] = nil
		end
	end
	self:Retry()
end

-- "Ziel ist feindlich gesonnen": InviteUnit ging an die andere Fraktion (Fraktion war unbekannt).
-- Die Meldung nennt keinen Namen - betroffen sind die gerade per InviteUnit Eingeladenen.
function AutoInvite:OnInviteError(_, _, message)
	if not self.session.active or Util.IsSecret(message) or type(message) ~= "string" then
		return
	end
	if not self.factionErrors[message] then
		return
	end
	local now, changed = GetTime(), false
	for _, entry in pairs(self.feed) do
		if entry.status == "invited" and entry.invitedAt and now - entry.invitedAt <= FAILED_INVITE_WINDOW then
			self:Release(entry)
			entry.crossFaction = true
			entry.invitedAt = nil
			entry.status = "match"
			self:AlertClick(entry)
			changed = true
		end
	end
	if changed then
		self:Update()
	end
end

function AutoInvite:OnSystemMessage(_, message)
	if not self.session.active or Util.IsSecret(message) or type(message) ~= "string" then
		return
	end
	if self.factionErrors[message] then
		self:OnInviteError(nil, nil, message)
		return
	end
	for _, pattern in ipairs(self.failPatterns) do
		if message:find(pattern) then
			for key in pairs(self.session.pending) do
				local short = key:match("^[^%-]+")
				if message:find(short, 1, true) then
					self.session.pending[key] = nil
					local entry = self:FindEntry(key)
					if entry then
						entry.status = "declined"
					end
					self:Retry()
					return
				end
			end
		end
	end
end

function AutoInvite:CheckPending()
	if not self.session.active then
		return
	end
	self:CheckHolds()
	local now, changed = time(), false
	for key, member in pairs(self.session.pending) do
		local entry = self:FindEntry(key)
		-- Einladung über den Gruppenfinder läuft noch: Platz bleibt reserviert, bis Blizzard sie beendet
		local open = entry and (entry.appStatus == "invited" or entry.appStatus == "inviteaccepted")
		if not open and now - (member.at or now) > PENDING_TIMEOUT then
			self.session.pending[key] = nil
			if entry and entry.status ~= "joined" then
				entry.status = "declined"
			end
			changed = true
		end
	end
	if changed then
		self:Retry()
	end
end

-- Für die Anzeige: Feed in Eingangsreihenfolge, neueste oben
function AutoInvite:GetFeed()
	local list = {}
	for i = #self.order, 1, -1 do
		local entry = self.feed[self.order[i]]
		if entry and entry.name then
			table.insert(list, entry)
		end
	end
	return list
end
