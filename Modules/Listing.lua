-- Listing: Gruppe für den eigenen Key erstellen und schließen (Leader-Seite)
-- Phase 0: SetEntryTitle und CreateListing brauchen je einen eigenen Klick; das
-- Blizzard-Erstellungsfenster darf nicht angefasst werden. KQ-Gruppen erkennt man am
-- Mindestscore, der die Keystufe trägt (Matcher.EncodeMarkerScore).
local _, ns = ...

local KeyQueue = ns.addon
local L = ns.L
local Matcher, Util = ns.Matcher, ns.Util

local Listing = KeyQueue:NewModule("Listing", "AceEvent-3.0", "AceTimer-3.0")
ns.Listing = Listing

local PLAYSTYLE = Enum.LFGEntryGeneralPlaystyle and Enum.LFGEntryGeneralPlaystyle.FunSerious or 3
local CREATE_TIMEOUT = 10

function Listing:OnEnable()
	self:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE", "OnEntryUpdate")
	self:RegisterEvent("LFG_LIST_ENTRY_CREATION_FAILED", "OnCreationFailed")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "Changed")
	self:RegisterEvent("BAG_UPDATE_DELAYED", "Changed")
end

function Listing:Changed()
	self:SendMessage("KEYQUEUE_LEADER_UPDATE")
end

function Listing:IsListed()
	return C_LFGList.HasActiveEntryInfo()
end

-- Aktives Listing mit KQ-Erkennungszeichen (überlebt auch ein /reload)
function Listing:IsKeyQueueListing()
	if not C_LFGList.HasActiveEntryInfo() then
		return false
	end
	local info = C_LFGList.GetActiveEntryInfo()
	return info ~= nil and Matcher.IsMarkerScore(Util.Readable(info.requiredDungeonScore))
end

-- nokey, notleader, prepare (Klick 1), ready (Klick 2), creating, listed
-- Dungeon des eigenen Listings: Aktivität und Schlüsselstein-Karte (Erfahrung der Bewerber genau dort)
function Listing:GetListedDungeon()
	local info = C_LFGList.GetActiveEntryInfo()
	if not info then
		return nil
	end
	local activityID = Util.Readable(info.activityIDs and info.activityIDs[1] or info.activityID)
	local activity = activityID and C_LFGList.GetActivityInfoTable(activityID)
	return activityID, activity and Util.ChallengeMapID(Util.Readable(activity.mapID))
end

function Listing:GetState()
	if C_LFGList.HasActiveEntryInfo() then
		return "listed"
	end
	if self.creating then
		return "creating"
	end
	if IsInGroup() and not UnitIsGroupLeader("player") then
		return "notleader"
	end
	local key = Util.GetKeystone()
	if not key then
		return "nokey"
	end
	if self.preparedActivity == key.activityID then
		return "ready"
	end
	return "prepare"
end

-- Klick 1: Gruppentitel setzen. Muss direkt aus einem OnClick kommen.
function Listing:Prepare()
	local key = Util.GetKeystone()
	if not key then
		return
	end
	C_LFGList.SetEntryTitle(key.activityID, key.groupID, 0, PLAYSTYLE)
	self.preparedActivity = key.activityID
	self:Changed()
end

-- Klick 1 "nebenbei": jeder andere Klick auf dem Weg zum Listen-Knopf (Tab "Gruppe erstellen",
-- Fenster öffnen, Filter-Pillen) bereitet den Key vor - dann reicht beim Knopf ein einziger Klick.
-- Muss direkt aus einem OnClick kommen; ohne Wirkung, wenn nichts vorzubereiten ist.
function Listing:PrepareIfNeeded()
	if self:GetState() == "prepare" and not InCombatLockdown() then
		self:Prepare()
	end
end

-- Klick 2: Gruppe listen. Muss direkt aus einem (anderen) OnClick kommen.
function Listing:Create()
	local key = Util.GetKeystone()
	if not key or self.preparedActivity ~= key.activityID then
		return
	end
	local options = KeyQueue.db.profile.leader
	-- Matchmaking-Queue (Key eingebracht): Mindestwertung aus der Queue, kein Mindest-Item-Level
	local leading = ns.Queue and ns.Queue:IsLeading()
	local minScore = leading and (KeyQueue.db.profile.queue.minScore or 0) or options.minScore

	-- Kennzeichen mit Keystufe; liegt es über der eigenen Wertung, lässt Blizzard nicht listen -
	-- dann Tausender abbauen (die genaue Mindestwertung prüft der Matcher ohnehin selbst)
	local validate = C_LFGList.ValidateRequiredDungeonScore
	local marker = Matcher.EncodeMarkerScore(minScore, key.level)
	while validate and marker >= 1000 and not validate(marker) do
		marker = marker - 1000
	end
	if validate and not validate(marker) then
		KeyQueue:Msg(L["LEADER_SCORE_ABOVE_YOURS"])
		return
	end
	local minItemLevel = leading and 0 or (options.minItemLevel or 0)
	if minItemLevel > Util.GetMyItemLevel() then
		KeyQueue:Msg(L["LEADER_ILVL_ABOVE_YOURS"])
		return
	end

	local activity = C_LFGList.GetActivityInfoTable(key.activityID)
	-- alte Sitzung beenden, falls die Meldung "Listing geschlossen" noch nicht da war
	if ns.AutoInvite.session.active then
		ns.AutoInvite:EndSession()
	end
	self.creating = true
	self:Changed()
	local ok = C_LFGList.CreateListing({
		activityIDs = { key.activityID },
		isAutoAccept = false,
		-- nur eigene Fraktion: alle Bewerber gehen per InviteUnit, Auto-Invite läuft auch AFK.
		-- Andere Fraktion geht nur über InviteApplicant, und das braucht eine Eingabe des Leaders.
		isCrossFactionListing = (activity and activity.allowCrossFaction and options.crossFaction) and true or false,
		isPrivateGroup = false,
		newPlayerFriendly = false,
		playstyle = 0,
		generalPlaystyle = PLAYSTYLE,
		requiredDungeonScore = marker,
		requiredItemLevel = minItemLevel,
		requiredPvpRating = 0,
	})
	if ok == false then
		self:OnCreationFailed()
		return
	end
	-- nur ein Zeitlimit gleichzeitig: ein altes von einem früheren Listing darf das neue nicht abbrechen
	if self.createTimer then
		self:CancelTimer(self.createTimer)
	end
	self.createTimer = self:ScheduleTimer("OnCreateTimeout", CREATE_TIMEOUT)
end

function Listing:OnCreateTimeout()
	self.createTimer = nil
	if self.creating and not C_LFGList.HasActiveEntryInfo() then
		self:OnCreationFailed()
	end
end

-- Muss direkt aus einem OnClick kommen
function Listing:Remove()
	C_LFGList.RemoveListing()
end

function Listing:OnEntryUpdate()
	if C_LFGList.HasActiveEntryInfo() then
		-- unser Listing (gerade erstellt oder am Erkennungszeichen erkannt): Auto-Invite-Sitzung starten.
		-- Beim schnellen Schließen/Neu-Listen kommen Blizzards Meldungen manchmal vertauscht an -
		-- das Erkennungszeichen macht das unabhängig davon.
		local ours = self.creating or self:IsKeyQueueListing()
		self.creating = false
		if ours and not ns.AutoInvite.session.active then
			KeyQueue:Msg(L["LEADER_LISTED"])
			ns.AutoInvite:BeginSession()
		end
	elseif not self.creating then
		-- Listing weg; läuft gerade ein neues Listen, ist das nur die verspätete Meldung des alten
		ns.AutoInvite:EndSession()
	end
	self:Changed()
end

function Listing:OnCreationFailed()
	self.creating = false
	self.preparedActivity = nil -- Titel sicherheitshalber neu setzen lassen
	KeyQueue:Msg(L["LEADER_CREATE_FAILED"])
	self:Changed()
end

-- Smarte Vorgaben: Bedarf aus der eigenen Rolle und der aktuellen Party ableiten
function Listing:SuggestNeeds()
	local options = KeyQueue.db.profile.leader
	local count = { TANK = 0, HEALER = 0, DAMAGER = 0 }
	for _, role in ipairs(Util.GetPartyRoles()) do
		count[role] = count[role] + 1
	end
	options.needTank = count.TANK == 0
	options.needHealer = count.HEALER == 0
	options.needDamager = math.max(0, 3 - count.DAMAGER)
end
