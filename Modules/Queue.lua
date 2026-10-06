-- Queue: die Matchmaking-Queue aus dem Panel an der Gruppensuche (Weg 2 - der Key-Halter ist der
-- Matchmaker; ingame getestet über zwei Realms). Zwei Wege je nach "Key einbringen":
--   lead: der eigene Key wird als KeyQueue-Gruppe gelistet (Keystufe im Kennzeichen). KeyQueue lädt
--         passende Bewerber automatisch ein - wer zuerst kam zuerst, Wertungsfenster, Rollen, Sperrliste;
--         gleiche Fraktion ohne Klick, andere Fraktion bei der nächsten Eingabe (Blizzard verlangt sie).
--   join: KeyQueue sucht KeyQueue-Gruppen (Stufe im Wunschbereich, Leader im Wertungsfenster, Platz für
--         eine meiner Rollen) und meldet sich an - bis zu 5 gleichzeitig, nebenbei bei Mausklick/Tastendruck.
-- Gleichbehandlung: Fraktion, Realm, Favoriten geben keinen Vorrang - nur die Wartezeit.
-- Geschützte Aufrufe (Listen, Suchen, Anmelden, Abmelden) laufen nur aus Klicks bzw. echten Eingaben.
local _, ns = ...

local KeyQueue = ns.addon
local L = ns.L
local Util = ns.Util

local Queue = KeyQueue:NewModule("Queue", "AceEvent-3.0", "AceTimer-3.0")
ns.Queue = Queue

local CREATE_CHECK = 3 -- Sekunden: ist die Gruppe danach nicht gelistet, braucht es einen neuen Klick

function Queue:OnEnable()
	self:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE", "OnEntryUpdate")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRosterUpdate")
end

function Queue:IsActive()
	return self.mode ~= nil
end

function Queue:IsLeading()
	return self.mode == "lead"
end

function Queue:IsJoining()
	return self.mode == "join"
end

-- Wartet der Key-Halter noch auf das Listen (vorbereitet, Listing braucht eine weitere Eingabe)?
function Queue:IsListPending()
	return self.mode == "lead" and self.listPending == true
end

function Queue:GetElapsed()
	return self.startedAt and (GetTime() - self.startedAt) or 0
end

function Queue:Update()
	self:SendMessage("KEYQUEUE_QUEUE_UPDATE")
end

-- Rollen der Queue: gewählte (nur spielbare), sonst die der aktuellen Spec
function Queue:GetRoles()
	local available = Util.GetAvailableRoles()
	local roles = {}
	for role in pairs(KeyQueue.db.profile.queue.roles) do
		if available[role] then
			roles[role] = true
		end
	end
	if next(roles) == nil then
		roles[Util.GetMyRole() or "DAMAGER"] = true
	end
	return roles
end

-- Kann ich meinen Key einbringen? (Schlüsselstein, solo oder als Gruppenleiter)
function Queue:CanLead()
	return Util.GetKeystone() ~= nil and (not IsInGroup() or UnitIsGroupLeader("player"))
end

---------------------------------------------------------------------------
-- Start/Stopp: nur aus dem Klick auf den Queue-Knopf (Hardware-Event)
---------------------------------------------------------------------------

function Queue:Toggle()
	if self.mode == "lead" and self.listPending then
		self:List() -- zweiter Klick: jetzt listen
	elseif self.mode then
		self:Stop()
	else
		self:Start()
	end
end

function Queue:Start()
	if InCombatLockdown() then
		return
	end
	self.startedAt, self.startedServer = GetTime(), GetServerTime()
	if KeyQueue.db.profile.queue.bringKey and self:CanLead() then
		-- Klick 1: Key vorbereiten. Gelistet wird bei der nächsten Eingabe (Blizzard: zwei Klicks)
		self.mode = "lead"
		self.listPending = true
		ns.Listing:Prepare()
		KeyQueue:Msg(L["Q_PREPARED"])
	else
		self.mode = "join"
		ns.Search:StartMatchmaking()
	end
	self:Update()
end

-- Muss aus einer echten Eingabe kommen (Klick oder Taste)
function Queue:List()
	if not self.listPending or InCombatLockdown() then
		return
	end
	self.listPending = false
	ns.Listing:Create()
	-- nicht gelistet (blockiert, kein Key mehr): beim nächsten Klick erneut versuchen
	self:ScheduleTimer(function()
		if self.mode == "lead" and not C_LFGList.HasActiveEntryInfo() then
			self.listPending = true
			self:Update()
		end
	end, CREATE_CHECK)
	self:Update()
end

function Queue:Stop()
	local mode = self.mode
	self.mode, self.listPending, self.startedAt, self.startedServer = nil, nil, nil, nil
	if mode == "lead" and C_LFGList.HasActiveEntryInfo() then
		ns.Listing:Remove()
	elseif mode == "join" then
		ns.Search:Cancel()
	end
	self:Update()
end

-- Jede echte Eingabe (Taste, Klick in die Welt): vorbereiteten Key listen. Über Tasten blockierte
-- Wege schaltet AutoInvite für die Sitzung ab (KeyAllowed). Rückgabe: true, wenn etwas passiert ist.
function Queue:OnHardwareEvent(source)
	if not self:IsListPending() or InCombatLockdown() then
		return false
	end
	local invite = ns.AutoInvite
	if not invite:KeyAllowed(source, "CreateListing") then
		return false
	end
	invite:MarkInput(source)
	self:List()
	return true
end

---------------------------------------------------------------------------
-- Ende der Queue: Gruppe voll (Blizzard nimmt das Listing raus) bzw. selbst in eine Gruppe gekommen
---------------------------------------------------------------------------

function Queue:OnEntryUpdate()
	if self.mode == "lead" and not self.listPending and not C_LFGList.HasActiveEntryInfo() then
		local full = GetNumGroupMembers() >= 5
		self.mode, self.startedAt, self.startedServer = nil, nil, nil
		if full then
			KeyQueue:Msg(L["Q_TEAM_READY"])
			Util.Alert(SOUNDKIT.READY_CHECK)
		end
	end
	self:Update()
end

function Queue:OnRosterUpdate()
	if self.mode == "join" and IsInGroup() and not UnitIsGroupLeader("player") then
		self.mode, self.startedAt, self.startedServer = nil, nil, nil -- drin: Search zeigt "Du bist drin"
	end
	self:Update()
end
