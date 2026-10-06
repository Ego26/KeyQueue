-- Comm: Addon-Nachrichten in der Party - Queue-Status für alle Party-Mitglieder synchron
local _, ns = ...

local KeyQueue = ns.addon

local Comm = KeyQueue:NewModule("Comm", "AceEvent-3.0")
ns.Comm = Comm

-- Addon-Message-Präfix (max. 16 Zeichen); Phase 0 nutzt ihn ebenfalls
Comm.PREFIX = "KeyQueue"

function Comm:OnEnable()
	C_ChatInfo.RegisterAddonMessagePrefix(Comm.PREFIX)
	self:RegisterEvent("CHAT_MSG_ADDON", "OnAddonMessage")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRosterUpdate")
end

-- Nachricht: "Q:<state>:<Sekunden seit Queue-Start>"
function Comm:SendQueueState(state, elapsed)
	if not IsInGroup(LE_PARTY_CATEGORY_HOME) or IsInRaid() then
		return
	end
	local message = ("Q:%s:%d"):format(state, math.floor(elapsed or 0))
	C_ChatInfo.SendAddonMessage(Comm.PREFIX, message, "PARTY")
end

function Comm:OnAddonMessage(_, prefix, text, channel, sender)
	if ns.Util.IsSecret(prefix) or ns.Util.IsSecret(text) or prefix ~= Comm.PREFIX or channel ~= "PARTY" then
		return
	end
	if ns.Util.NameKey(sender) == ns.Util.NameKey(GetUnitName("player", true)) then
		return
	end
	local state, elapsed = text:match("^Q:(%a+):(%d+)$")
	if state then
		self.partyQueue = { state = state, since = GetTime() - tonumber(elapsed), sender = sender }
		self:SendMessage("KEYQUEUE_PARTY_UPDATE")
	end
end

function Comm:OnRosterUpdate()
	if not IsInGroup() and self.partyQueue then
		self.partyQueue = nil
		self:SendMessage("KEYQUEUE_PARTY_UPDATE")
	end
end
