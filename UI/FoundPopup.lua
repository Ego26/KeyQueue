-- FoundPopup: der "Gruppe gefunden"-Moment - großes Popup, Bildschirm-Aufblitzen, Sound
local _, ns = ...

local L = ns.L
local Theme, Util = ns.Theme, ns.Util

local FoundPopup = {}
ns.FoundPopup = FoundPopup

local WIDTH, PAD = 420, 20

function FoundPopup:Create()
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(WIDTH, 250)
	frame:SetPoint("CENTER", 0, 140)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	Theme.DropShadow(frame)
	Theme.SetSurface(frame, Theme.color.bg, Theme.color.activeBorder)
	frame:Hide()
	self.frame = frame

	-- Kopf: Bildmarke, "Gruppe gefunden!", darunter der Dungeon
	local mark = frame:CreateTexture(nil, "ARTWORK")
	mark:SetSize(44, 44)
	mark:SetPoint("TOPLEFT", PAD, -PAD)
	mark:SetTexture(Theme.media.icon, nil, nil, "TRILINEAR")
	local title = Theme.Text(frame, 20, "text", nil, nil, true)
	title:SetPoint("TOPLEFT", mark, "TOPRIGHT", 14, -2)
	title:SetText(L["FOUND_TITLE"])
	self.dungeon = Theme.Text(frame, 13, "muted")
	self.dungeon:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)

	-- Gruppe als Fläche: Name (mit Stufe), Leader mit RIO, deine Rolle
	local card = CreateFrame("Frame", nil, frame)
	card:SetPoint("TOPLEFT", mark, "BOTTOMLEFT", 0, -16)
	card:SetPoint("RIGHT", -PAD, 0)
	card:SetHeight(86)
	Theme.SetSurface(card, Theme.color.surface)
	self.card = card
	self.groupTitle = Theme.Text(card, 15)
	Theme.SetGameFont(self.groupTitle, 15)
	self.groupTitle:SetPoint("TOPLEFT", 14, -14)
	self.groupTitle:SetPoint("RIGHT", -14, 0)
	self.groupTitle:SetWordWrap(false)
	self.leader = Theme.Text(card, 12, "text")
	Theme.SetGameFont(self.leader, 12)
	self.leader:SetPoint("TOPLEFT", self.groupTitle, "BOTTOMLEFT", 0, -8)
	self.role = Theme.Text(card, 12, "muted")
	self.role:SetPoint("TOPLEFT", self.leader, "BOTTOMLEFT", 0, -6)

	local accept = Theme.Button(frame, L["FOUND_ACCEPT"], "primary", 220, 40)
	accept:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -16)
	accept:SetScript("OnClick", function()
		ns.Search:AcceptFound() -- direkt im Klick: AcceptInvite braucht den Hardware-Event
		frame:Hide()
	end)
	local decline = Theme.Button(frame, L["FOUND_DECLINE"], "ghost", 120, 40)
	decline:SetPoint("LEFT", accept, "RIGHT", 10, 0)
	decline:SetPoint("RIGHT", card, "RIGHT", 0, 0)
	decline:SetScript("OnClick", function()
		ns.Search:DeclineFound()
		frame:Hide()
	end)
	frame:SetHeight(PAD + 44 + 16 + 86 + 16 + 40 + PAD)

	-- Blizzards eigenes Einladungsfenster ausblenden, solange unseres offen ist (sonst zwei Fenster)
	if LFGListInviteDialog then
		LFGListInviteDialog:HookScript("OnShow", function(dialog)
			if frame:IsShown() and not InCombatLockdown() then
				dialog:Hide()
			end
		end)
	end

	-- Bildschirm-Aufblitzen in der Akzentfarbe
	local flash = CreateFrame("Frame", nil, UIParent)
	flash:SetAllPoints()
	flash:SetFrameStrata("FULLSCREEN_DIALOG")
	flash:EnableMouse(false)
	local flashTexture = flash:CreateTexture(nil, "BACKGROUND")
	flashTexture:SetAllPoints()
	flashTexture:SetColorTexture(unpack(Theme.color.violet))
	flash:SetAlpha(0)
	local fade = flash:CreateAnimationGroup()
	local alpha = fade:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0.35)
	alpha:SetToAlpha(0)
	alpha:SetDuration(0.9)
	alpha:SetSmoothing("OUT")
	self.flash = fade
end

local ROLE_NAMES = { TANK = "ROLE_TANK", HEALER = "ROLE_HEALER", DAMAGER = "ROLE_DAMAGER" }

function FoundPopup:Show(found)
	if not self.frame then
		self:Create()
	end
	local group = found.group
	self.dungeon:SetText(group and group.dungeon or "")
	self.groupTitle:SetText(group and group.title or "")
	if group and group.leaderName then
		self.leader:SetText(L["FOUND_LEADER"]:format(Ambiguate(group.leaderName, "none"), Util.ScoreText(group.leaderScore)))
	elseif found.inviter then
		self.leader:SetText(L["FOUND_LEADER"]:format(found.inviter, "-"))
	else
		self.leader:SetText("")
	end
	local role = Util.GetMyRole()
	self.role:SetText(L["FOUND_ROLE"]:format(Util.RoleIcon(role, 13) .. " " .. L[ROLE_NAMES[role] or "ROLE_DAMAGER"]))
	self.frame:Show()
	self.flash:Play()
	if found.mode == "lfg" and LFGListInviteDialog and LFGListInviteDialog:IsShown() and not InCombatLockdown() then
		LFGListInviteDialog:Hide()
	end
end

function FoundPopup:Hide()
	if self.frame and self.frame:IsShown() then
		self.frame:Hide()
		-- ohne Annehmen/Ablehnen geschlossen: steht die Einladung noch, Blizzards Fenster wieder zeigen
		if LFGListInviteDialog and LFGListInviteDialog_CheckPending and not InCombatLockdown() then
			pcall(LFGListInviteDialog_CheckPending, LFGListInviteDialog)
		end
	end
end

---------------------------------------------------------------------------
-- InvitePopup: Queue-Pop für den Leader. Andere Fraktion und Gruppen-Bewerbungen lassen sich nur
-- mit einer Eingabe einladen (InviteApplicant) - wie beim Blizzard-Dungeonbrowser bestätigt ein Klick
-- (oder irgendeine Taste) den Match. Gleiche Fraktion läuft weiter ganz ohne Eingabe.
---------------------------------------------------------------------------

local InvitePopup = {}
ns.InvitePopup = InvitePopup
LibStub("AceEvent-3.0"):Embed(InvitePopup)

function InvitePopup:Create()
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(460, 214)
	frame:SetPoint("CENTER", 0, 140)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	Theme.DropShadow(frame)
	Theme.SetSurface(frame, Theme.color.bg, Theme.color.activeBorder)
	frame:Hide()
	self.frame = frame

	local mark = frame:CreateTexture(nil, "ARTWORK")
	mark:SetSize(48, 48)
	mark:SetPoint("TOPLEFT", 20, -22)
	mark:SetTexture(Theme.media.icon, nil, nil, "TRILINEAR") -- Bildmarke auf Kachel

	local title = Theme.Text(frame, 20, "text", nil, nil, true)
	title:SetPoint("TOPLEFT", mark, "TOPRIGHT", 14, -2)
	title:SetText(L["LEADER_POP_TITLE"])

	self.reason = Theme.Text(frame, 12, "muted")
	self.reason:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

	-- bis zu 4 Zeilen: Rolle, Name (Klassenfarbe), Score/iLvl
	self.lines = {}
	for index = 1, 4 do
		local line = Theme.Text(frame, 13)
		Theme.SetGameFont(line, 13)
		line:SetPoint("TOPLEFT", mark, "BOTTOMLEFT", 0, -14 - (index - 1) * 20)
		line:SetPoint("RIGHT", -20, 0)
		line:SetWordWrap(false)
		self.lines[index] = line
	end

	local invite = Theme.Button(frame, L["LEADER_POP_INVITE"], "primary", 220, 40)
	invite:SetPoint("BOTTOMLEFT", 20, 20)
	invite:SetScript("OnClick", function()
		-- direkt im Klick: InviteApplicant braucht den Hardware-Event
		if self.entry then
			ns.AutoInvite:InviteCandidate(self.entry)
		end
	end)

	local skip = Theme.Button(frame, L["LEADER_POP_SKIP"], "ghost", 120, 40)
	skip:SetPoint("LEFT", invite, "RIGHT", 10, 0)
	skip:SetScript("OnClick", function()
		if self.entry then
			self.entry.skipped = true
		end
		ns.AutoInvite:Retry() -- gehaltener Platz wird sofort frei
	end)

	-- Restzeit der Platz-Reservierung
	local elapsed = 0
	frame:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed >= 0.5 then
			elapsed = 0
			self:RefreshHold()
		end
	end)

	self.hint = Theme.Text(frame, 10, "muted")
	self.hint:SetPoint("BOTTOMRIGHT", -20, 8)
	self.hint:SetJustifyH("RIGHT")
	self.hint:SetText(L["LEADER_POP_HINT"])
end

function InvitePopup:Refresh()
	local options = ns.addon.db.profile.leader
	local entry = options.autoInvite and ns.AutoInvite:GetClickCandidate(true) or nil
	if not entry then
		self.entry = nil
		if self.frame then
			self.frame:Hide()
		end
		return
	end
	if not self.frame then
		self:Create()
	end

	local members = entry.members or { entry }
	self.reasonText = #members > 1 and L["LEADER_POP_PARTY"]:format(#members) or L["LEADER_POP_CROSSFACTION"]
	for index, line in ipairs(self.lines) do
		local member = members[index]
		if member then
			local role = entry.assignment and entry.assignment[index] or (index == 1 and entry.role) or member.assignedRole
			line:SetText(Util.RoleIcon(role, 14) .. "  " .. Util.ClassName(Ambiguate(member.name or "?", "none"), member.class)
				.. "   " .. Theme.Colorize(L["LEADER_ENTRY_STATS"]:format(math.floor(member.itemLevel or 0), Util.ScoreText(member.score)), "muted"))
			line:Show()
		else
			line:Hide()
		end
	end
	self.frame:SetHeight(158 + #members * 20)

	-- neuer Match: auftauchen wie ein Queue-Pop
	if self.entry ~= entry or not self.frame:IsShown() then
		self.entry = entry
		self.frame:Show()
		Util.Alert(SOUNDKIT.UI_GROUP_FINDER_RECEIVE_APPLICATION or SOUNDKIT.READY_CHECK)
	end
	self:RefreshHold()
end

-- "Andere Fraktion - ...  ·  Platz reserviert: 0:42"
function InvitePopup:RefreshHold()
	local entry = self.entry
	if not entry then
		return
	end
	local text = self.reasonText or ""
	if ns.AutoInvite:IsHolding(entry) then
		local hold
		if entry.holdUntil == math.huge then
			hold = L["LEADER_POP_HOLD_OPEN"]
		else
			hold = L["LEADER_POP_HOLD"]:format(Util.FormatTime(math.ceil(entry.holdUntil - GetTime())))
		end
		text = text .. "  \194\183  " .. Theme.Colorize(hold, "gold")
	end
	self.reason:SetText(text)
end

InvitePopup:RegisterMessage("KEYQUEUE_LEADER_UPDATE", "Refresh")
